# H2 Mux 内部实现

面向开发者的 HTTP/2 多路复用器实现参考。架构概览与图表见 [architecture.md](./architecture.md)。面向用户端的配置见 [configure.md](./configure.md)。

本文档覆盖以下源文件：

| 文件 | 职责 |
|------|------|
| `lib/src/protocol/mux/h2.rs` | `ConnectionH2` 结构体、状态机、流量控制、洪水检测 |
| `lib/src/protocol/mux/pkawa.rs` | HPACK 解码、伪头部验证、RFC 9218 优先级解析 |
| `lib/src/protocol/mux/mod.rs` | Mux 会话、Stream、Router、ready() 循环、流生命周期 |
| `lib/src/protocol/mux/converter.rs` | Kawa-to-H2 帧编码（`H2BlockConverter`） |
| `lib/src/protocol/mux/parser.rs` | H2 二进制帧解析器（nom） |
| `lib/src/protocol/mux/serializer.rs` | H2 帧序列化器（SETTINGS、GOAWAY、RST_STREAM） |

---

## ConnectionH2 子结构

`ConnectionH2` 是核心的 H2 连接类型，泛型参数为 `Front: SocketHandler`。
其字段被拆分为多个专注的子结构，以实现关注点分离：

```
ConnectionH2<Front>
 |
 |-- socket: Front                          // TLS 或 TCP 套接字
 |-- state: H2State                         // 帧级状态机
 |-- position: Position                     // Server 或 Client(cluster, scheme)
 |-- readiness: Readiness                   // 边缘触发式兴趣追踪
 |
 |-- flow_control: H2FlowControl            // 连接级流量控制
 |   |-- window: i32                        // 发送窗口（根据 RFC 9113 s6.9.2 可为负值）
 |   |-- received_bytes_since_update: u32   // 自上次 WINDOW_UPDATE 以来的入站字节数
 |   |-- pending_window_updates: Vec<(u32, u32)>  // 排队中的 (stream_id, increment) 对
 |
 |-- bytes: H2ByteAccounting                // 开销归属记账
 |   |-- zero_bytes_read: usize             // 尚未归属的 stream 0 读取字节
 |   |-- overhead_bin: usize                // 接收到的开销字节（连接级帧）
 |   |-- overhead_bout: usize               // 发送的开销字节（连接级帧）
 |
 |-- drain: H2DrainState                    // 优雅关闭状态
 |   |-- draining: bool                     // 发送首条 GOAWAY 后为 true
 |   |-- peer_last_stream_id: Option<StreamId>  // 来自对端 GOAWAY（用于重试）
 |
 |-- flood_detector: H2FloodDetector        // CVE 缓解速率限制器
 |   |-- config: H2FloodConfig              // 6 个可配置阈值
 |   |-- rst_stream_count, ping_count, ...  // 每窗口计数器
 |   |-- glitch_count: u32                  // 累计异常计数器
 |   |-- window_start: Instant              // 滑动窗口起点
 |
 |-- prioriser: Prioriser                   // RFC 9218 流优先级
 |   |-- priorities: HashMap<StreamId, (u8, bool)>  // urgency + incremental
 |
 |-- decoder: loona_hpack::Decoder          // HPACK 解码器（入站）
 |-- encoder: loona_hpack::Encoder          // HPACK 编码器（出站）
 |-- local_settings: H2Settings             // 我们 advertise 的设置
 |-- peer_settings: H2Settings              // 对端 advertised 的设置
 |-- streams: HashMap<StreamId, GlobalStreamId>  // H2 stream ID → 共享池索引
 |-- highest_peer_stream_id: StreamId       // 用于 GOAWAY last_stream_id
 |-- converter_buf: Vec<u8>                 // 可复用的 HPACK 编码缓冲区
 |-- lowercase_buf: Vec<u8>                 // 可复用的头部 key 小写缓冲区
 |-- pending_rst_streams: Vec<(StreamId, H2Error)>  // 排队中的 RST_STREAM 帧
 |-- rst_sent: HashSet<StreamId>            // 去重：已发送的 RST_STREAM
 |-- settings_sent_at: Option<Instant>      // SETTINGS ACK 超时追踪
 |-- zero: GenericHttpStream                // 连接级（stream 0）缓冲区
 |-- timeout_container: TimeoutContainer    // 会话超时管理
```

访问模式直接使用子结构名称：

```rust
self.flow_control.window -= consumed;
self.bytes.overhead_bin += size;
self.drain.draining = true;
self.flood_detector.check_flood();
self.prioriser.get(&stream_id);
```

---

## RFC 9218 可扩展优先级

### Prioriser 结构体

`Prioriser` 管理 RFC 9218 定义的单流调度优先级。它封装了一个
`HashMap<StreamId, (u8, bool)>`，其中元组为 `(urgency, incremental)`。

**方法：**

| 方法 | 签名 | 行为 |
|--------|-----------|----------|
| `push_priority` | `(&mut self, StreamId, PriorityPart) -> bool` | 插入/更新优先级。自依赖时返回 `true`（协议错误）。将 urgency 钳制到 0-7。忽略已废弃的 RFC 7540 树形优先级。 |
| `get` | `(&self, &StreamId) -> (u8, bool)` | 返回 `(urgency, incremental)`。缺失时默认为 `(3, false)`。 |
| `remove` | `(&mut self, &StreamId)` | 在流清理时移除条目。 |

### parse_rfc9218_priority()

位于 `pkawa.rs`，此函数解析 `priority` HTTP 头部值：

```rust
fn parse_rfc9218_priority(value: &[u8]) -> (u8, bool)
```

头部使用 RFC 8941 结构化字段字典格式。示例：

| 输入 | 解析结果 |
|-------|--------|
| `u=0, i` | urgency=0, incremental=true |
| `u=3` | urgency=3, incremental=false |
| `i` | urgency=3（默认）, incremental=true |
| `u=9` | urgency=7（钳制后）, incremental=false |
| （缺失） | urgency=3, incremental=false |
| `i=?0` | urgency=3, incremental=false |

解析器按 `,` 分割，修剪 OWS（RFC 9110 s5.6.3 定义的 SP/HTAB），并处理
令牌 `u=N` 和 `i`/`i=?1`/`i=?0`。格式错误的令牌会被静默忽略。

### 优先级如何影响流调度

在 `write_streams()` 中，收集所有活动流 ID 并排序：

```rust
let mut priorities = self.streams.keys().collect::<Vec<_>>();
priorities.sort_by(|a, b| {
    let (ua, _) = self.prioriser.get(a);
    let (ub, _) = self.prioriser.get(b);
    ua.cmp(&ub).then_with(|| a.cmp(b))
});
```

较低 urgency 值优先服务（urgency 0 = 最高优先级）。
urgency 相同的流中，较低 stream ID 优先以保证稳定性。
`incremental` 标志被存储但尚未用于同 urgency 级别的轮询调度。

### 优先级清理

优先级条目在 4 个生命周期节点被移除，以防止 HashMap 无限增长：

1. **dead_streams 循环**（`write_streams` 末尾）：`self.prioriser.remove(&stream_id)`
2. **收到 RST_STREAM**（在 `handle_frame` 中）：通过流移除清理
3. **GoAway 处理**（`close_all_streams`）：清空 streams 映射
4. **`end_stream`**（后端发起的关闭）：`self.prioriser.remove(&id)`

---

## 洪水检测

### H2FloodConfig

带有安全编译时默认值的可配置阈值：

| 字段 | 默认值 | CVE | 攻击类型 |
|-------|---------|-----|--------|
| `max_rst_stream_per_window` | 100 | CVE-2023-44487, CVE-2019-9514 | Rapid Reset / Reset Flood |
| `max_ping_per_window` | 100 | CVE-2019-9512 | Ping Flood |
| `max_settings_per_window` | 50 | CVE-2019-9515 | Settings Flood |
| `max_empty_data_per_window` | 100 | CVE-2019-9518 | 空帧攻击 |
| `max_continuation_frames` | 20 | CVE-2024-27316 | CONTINUATION Flood |
| `max_glitch_count` | 100 | （累计） | 通用协议滥用 |

滑动窗口持续时间为 1 秒（`FLOOD_WINDOW_DURATION`）。

### H2FloodDetector

通过 `H2FloodDetector::new(config)` 创建。跟踪每种帧类型的每窗口计数器，
以及用于各种协议违规的累计 `glitch_count`。

**滑动窗口衰减**（`maybe_reset_window`）：当窗口过期时，
计数器减半（而非清零）。这种半衰衰减能够捕获"突发-等待"攻击模式：
攻击者发送突发流量，等待窗口重置，然后再次突发。

**检查流程**（`check_flood`）：

```
check_flood()
  |-- maybe_reset_window()   // 窗口过期则半衰衰减
  |-- rst_stream_count > 阈值?  --> Some(EnhanceYourCalm)
  |-- ping_count > 阈值?        --> Some(EnhanceYourCalm)
  |-- settings_count > 阈值?    --> Some(EnhanceYourCalm)
  |-- empty_data_count > 阈值?  --> Some(EnhanceYourCalm)
  |-- continuation_count > 阈值? --> Some(EnhanceYourCalm)
  |-- accumulated_header_size > 64KB? --> Some(EnhanceYourCalm)
  |-- glitch_count > 阈值?      --> Some(EnhanceYourCalm)
  '-- None（全部正常）
```

**CONTINUATION 专属计数器**在头部块完成时重置（`reset_continuation()`），
因为它们跟踪的是每块计数，而非每窗口计数。

### glitch_count 机制

`glitch_count` 用于递增那些不符合特定洪水模式但表明整体滥用的协议异常：

- 在已关闭流上的帧（RST_STREAM、WINDOW_UPDATE、已在关闭流上的 DATA）
- 其他不足以立即触发 GOAWAY 的次要协议违规

与基于速率的计数器不同，`glitch_count` 使用相同的半衰窗口，
提供累计滥用检测。

### 超过阈值时会发生什么

当 `check_flood()` 返回 `Some(EnhanceYourCalm)` 时：

1. 记录警告日志，标识具体超出的阈值
2. 调用 `goaway(H2Error::EnhanceYourCalm)`
3. 连接进入 `H2State::Error`，`drain.draining = true`
4. 序列化带有错误码 ENHANCE_YOUR_CALM (0xb) 的 GOAWAY 帧
5. 连接转换到 `H2State::GoAway` 进行最终写入 + 断开

### 每监听器可配置性

阈值可通过 protobuf 监听器配置进行配置。`HttpListenerConfig`
和 `HttpsListenerConfig` 均暴露可选字段：

```protobuf
// 在 HttpListenerConfig 和 HttpsListenerConfig 中：
// 洪水检测阈值：
optional uint32 h2_max_rst_stream_per_window = 13;
optional uint32 h2_max_ping_per_window = 14;
optional uint32 h2_max_settings_per_window = 15;
optional uint32 h2_max_empty_data_per_window = 16;
optional uint32 h2_max_continuation_frames = 17;
optional uint32 h2_max_glitch_count = 18;
// 连接调优：
optional uint32 h2_initial_connection_window = 19;
optional uint32 h2_max_concurrent_streams = 20;
optional uint32 h2_stream_shrink_ratio = 21;
```

当缺失（`None`）时，应用内置默认值：
- 洪水阈值来自 `H2FloodConfig::default()`
- 连接调优来自 `H2ConnectionConfig::default()`

`H2ConnectionConfig` 控制连接级参数：

| 字段 | 默认值 | 描述 |
|-------|---------|-------------|
| `initial_connection_window` | 1048576 (1MB) | 连接接收窗口（RFC 9113 §6.9.2），钳制到 [65535, 2^31-1] |
| `max_concurrent_streams` | 100 | `SETTINGS_MAX_CONCURRENT_STREAMS`，同时也决定 pending WINDOW_UPDATE 上限 |
| `stream_shrink_ratio` | 2 | 流 Vec 收缩阈值：`total > active * ratio`，最小值 2 |

这允许操作者针对每个监听器同时调优安全性和性能。

---

## 开销分配

### 问题

在 HTTP/2 中，连接级帧（SETTINGS、PING、WINDOW_UPDATE、GOAWAY、
SETTINGS ACK）消耗带宽但不属于任何特定流。为了在访问日志和指标中
实现准确的单流字节记账，必须按比例分配这些开销。

### distribute_overhead()

一个**自由函数**（非方法），以避免借用冲突：

```rust
fn distribute_overhead(
    metrics: &mut SessionMetrics,
    overhead_bin: &mut usize,
    overhead_bout: &mut usize,
    stream_bytes: (usize, usize),
    total_bytes: (usize, usize),
    active_streams: usize,
)
```

提取为自由函数是因为 `write_streams()` 通过 converter 借用 `self.encoder`，
同时需要更新单流指标和连接开销计数器。`&mut self` 方法会产生冲突。

**分配公式：**

```
share_in  = overhead_bin  * (stream_bytes_in  / total_bytes_in)
share_out = overhead_bout * (stream_bytes_out / total_bytes_out)
```

当 `total_bytes` 为零（尚无流传输数据）时，回退到均匀分配：
`overhead / max(active_streams, 1)`。

分配后，已从开销累加器中扣除分配的量，因此剩余的开销会 carry over
到后续流。

### compute_stream_byte_totals()

```rust
fn compute_stream_byte_totals(&self, context: &Context) -> (usize, usize)
```

遍历所有活动流，累加 `(bin + backend_bin, bout + backend_bout)`。
必须在获取单个流的可变借用之前调用，以避免与 context 的借用冲突。

### 开销字节的来源

字节在以下两处被归类为开销：

- **`attribute_bytes_to_overhead()`**：处理连接级帧（SETTINGS、PING、
  WINDOW_UPDATE）后调用。将 `zero_bytes_read` 移入 `bytes.overhead_bin`。
- **`flush_zero_to_socket()`**：从零缓冲区写入的每一字节
  （连接级帧）递增 `bytes.overhead_bout`。

### 如何馈入 SessionMetrics

在流完成时（`complete_server_stream` 或 `reset_stream`），
在发出访问日志之前，将开销分配到流的 `SessionMetrics`：

```rust
self.distribute_overhead(&mut stream.metrics, byte_totals);
let (client_rtt, server_rtt) = self.snapshot_rtts(&endpoint, stream.linked_token());
stream.generate_access_log(
    false,
    Some("H2::Complete"),
    listener,
    client_rtt,
    server_rtt,
);
```

这确保访问日志中的 `metrics.bin` 和 `metrics.bout` 包含流的
连接开销按比例分配的部分，并确保 TCP_INFO 衍生的
`client_rtt` / `server_rtt` 单元格在发出时从活动的
前端/后端套接字填充。

---

## 方法分解

`ConnectionH2` 实现被分解为专注的方法，以管理 H2 状态机的复杂性：

### readable() 入口点

```rust
pub fn readable(&mut self, context, endpoint) -> MuxResult
```

根据 `H2State` 分发：

| 状态 | 委托给 |
|-------|-------------|
| `Header` | `handle_header_state(context)` |
| `ContinuationHeader(headers)` | `handle_continuation_header_state(&headers)` |
| `Frame(header)` | 内联 `handle_frame()` 逻辑 |
| `ContinuationFrame(headers)` | 内联 continuation 组装 |
| `ClientPreface` / `ServerSettings` | 握手验证 |
| `Discard` | 跳过载荷字节 |

### handle_header_state()

从 `self.zero` 解析 9 字节帧头，验证流（新建、已有、关闭或空闲），
为奇数 ID 的 HEADERS 创建新流，并转换到 `H2State::Frame(header)`
以读取载荷。

此方法的关键决策：
- MAX_CONCURRENT_STREAMS 执行：排队 RST_STREAM(REFUSED_STREAM) 并
  转换到 `Discard` 状态以跳过 HEADERS 载荷
- 缓冲池耗尽：与 MAX_CONCURRENT_STREAMS 相同处理
- 关闭流与空闲流检测：关闭流上的帧获得 RST_STREAM 或 GOAWAY
  （取决于帧类型）；空闲流上的帧获得 GOAWAY(PROTOCOL_ERROR)

### handle_continuation_header_state()

解析 CONTINUATION 帧头，验证 stream ID 连续性，跟踪
CONTINUATION 洪水计数器（CVE-2024-27316），并累加头部块片段长度。

### writable() 入口点

```rust
pub fn writable(&mut self, context, endpoint) -> MuxResult
```

1. 调用 `flush_pending_control_frames()` 作为前导
2. 根据 `(H2State, Position)` 分发：
   - 握手状态：序列化客户端序言、SETTINGS、连接 WINDOW_UPDATE
   - 代理状态：委托给 `write_streams(context, endpoint)`

### flush_pending_control_frames()

在应用帧之前刷新控制数据，顺序如下：

1. **SETTINGS ACK 超时检查**：如果对端在 5 秒内未 ACK，
   发送 GOAWAY(SETTINGS_TIMEOUT)
2. **零缓冲区恢复**：如果之前的控制帧写入部分完成（WouldBlock），
   通过 `flush_zero_to_socket()` 恢复刷新
3. **WINDOW_UPDATE 帧**：将排队的 `pending_window_updates` 序列化
   到零缓冲区，按 stream ID 合并，然后刷新
4. **排队 RST_STREAM 帧**：将 `pending_rst_streams` 排空到零缓冲区，
   带有洪水检测（`MAX_PENDING_RST_STREAMS` 上限）。
   代理发出的 RST（DATA-on-closed、`refuse_stream_and_discard`、
   `reset_stream`）通过标准的 `ConnectionH2::enqueue_rst` 辅助函数排队，
   该函数通过 `self.rst_sent` 去重，递增 `total_rst_streams_queued`，
   并触发 WRITABLE。此路径独立于拥有 `Stream` 是否仍在
   `self.streams` 中，因此能存活于 `remove_dead_stream` 驱逐
   （每流错误调用者在 `reset_stream` 返回后同步调用）。
   `finalize_write` 在队列非空时保留 `Ready::WRITABLE`，
   因此部分写入导致刷新延迟（RST_STREAM 排空阶段受
   `expect_write.is_none()` 门控）会在下一个 tick 重新运行，
   而非让排队的 RST 搁置。

如果调用方应提前返回，返回 `Some(MuxResult)`；否则返回 `None`。

### write_streams()

主数据平面写入路径：

1. 恢复任何部分写入的流（`expect_write`）
2. 预计算 `byte_totals` 用于开销分配
3. 设置借用 `self.encoder` 的 `H2BlockConverter`
4. 按优先级排序流（urgency，然后 stream_id）
5. 对每个流：将 kawa 块转换为 H2 帧，写入套接字
6. 回收已完成的流，分配开销，发出访问日志
7. 清理 `dead_streams`（从 streams 映射、rst_sent、prioriser 移除）
8. 如果转换器缓冲区增长超过 16KB 则收缩

**为什么 write_streams() 无法进一步分解**：`H2BlockConverter`
在优先级循环期间借用 `self.encoder`。这阻止了在循环体中调用
任何 `&mut self` 方法。自由函数 `distribute_overhead()` 为指标
绕过了此限制，但 converter 设置和优先级迭代必须保持在单个方法作用域内。

### flush_zero_to_socket()

```rust
fn flush_zero_to_socket(&mut self) -> bool
```

在循环中将零缓冲区写入套接字。套接字停滞（WouldBlock）时返回 `true`，
完全排空时返回 `false`。计数写入字节为 `overhead_bout`。排空后
清除缓冲区以重置位置。

### 关闭与断开路径

该分支的最终强化工作集中在关闭路径，其中 H2 流状态、GOAWAY 序列化和
rustls 缓冲交互：

- `Mux::delay_close_for_frontend_flush()` 将在前端仍有 TLS 数据或
  GOAWAY 字节缓冲时将即时会话关闭转为最终可写阶段。
  在 TLS 前端上，首先要求 rustls 生成 `close_notify`。
- `Mux::drive_frontend_shutdown_io()` 在 worker 排空期间主动运行
  `readable()` 和 `writable()`。这很重要，因为优雅的 H2 关闭可能
  需要再读一次以观察对端 EOF / END_STREAM，以及再写一次以发出
  最终的 GOAWAY 或刷新缓冲的 TLS 记录，即使 epoll 未交付新的
  就绪事件。
- `ConnectionH2::prune_inactive_streams_while_closing()` 移除在
  连接级关闭前从未变为活动的 H2 stream-ID 映射（例如，在 GOAWAY
  期间被放弃的部分或超大 HEADERS 块）。如果没有此修剪，关闭
  可能永远等待不再对应有用工作的空闲条目。
- `peer_gone_after_final_goaway()` 是前端 H2 连接的终端关闭条件。
  一旦最终 GOAWAY 已排队、所有流映射已消失、且对端已挂起，
  剩余的 rustls 积压无法交付，会话可立即关闭。
- `FrontRustls::peer_disconnected` 在 EOF/HUP 后抑制新 TLS 写入，
  使关闭路径不会持续重试对已死对端的应用写入。
- HTTPS 使用 `shutdown(Write)` 而非 `shutdown(Both)`。在 Linux 上，
  `shutdown(Both)` 会丢弃未读的接收缓冲区数据，可能将原本干净的
  排空后关闭转为 TCP RST，截断排空循环已刷新的字节。

### complete_server_stream()

静态辅助函数，最终化服务端流：递增 `http.e2e.h2` 计数器、停止
后端指标、生成访问日志、重置指标，并将流转换到 `StreamState::Recycle`。

---

## OpenTelemetry 集成

### 特性标志

所有 OpenTelemetry 代码受以下门控：

```rust
#[cfg(feature = "opentelemetry")]
```

禁用时，访问日志记录中的 `otel` 字段为 `None`。

### Mux 层中的工作原理

OpenTelemetry 上下文传播由 `HttpContext` 处理（定义在
`lib/src/protocol/kawa_h1/editor.rs`），其包含：

```rust
#[cfg(feature = "opentelemetry")]
pub otel: Option<sozu_command::logging::OpenTelemetry>,
```

在 H1 编辑器路径（`editor.rs`）的流创建期间，`traceparent`
和 `tracestate` 头部从入站请求中提取：

1. `parse_traceparent()` 从 W3C Trace Context 格式
   `00-{trace_id}-{parent_id}-{flags}` 提取
   `(trace_id: [u8; 32], parent_id: [u8; 16])`
2. 为代理跃点生成新的 `span_id`
3. 使用新 span ID 重写 `traceparent` 头部
4. 如果不存在 `traceparent`，则注入一个；孤立的 `tracestate` 被省略

### SpanContext 传播到访问日志

在访问日志发出时（`Stream::generate_access_log`，位于 `mod.rs`）：

```rust
#[cfg(feature = "opentelemetry")]
otel: context.otel.as_ref(),
#[cfg(not(feature = "opentelemetry"))]
otel: None,
```

`OpenTelemetry` 结构体（trace_id、span_id、parent_span_id）被传递给
日志格式化器，使代理访问日志能与分布式跟踪关联。

### H2 专属考虑

H2 路径通过统一的 `Stream` 抽象与 H1 路径共享 `HttpContext`。
`traceparent`/`tracestate` 头部提取在 kawa 块级别发生，对 H1 和 H2
解码头部均同样有效。没有 H2 专属的 OpenTelemetry 代码；
集成设计上与协议无关。

---

## HPACK 安全

### 可失败的 write_all() 模式

`pkawa.rs` 中的所有 HPACK 解码回调都使用可失败的写入到 kawa 存储：

```rust
if kawa.storage.write_all(value).is_err() {
    invalid_headers = true;
    return;
}
```

这防止了解码头部块超出可用存储时的缓冲区溢出。
`invalid_headers` 标志在解码完成后检查，
触发流重置（`H2Error::ProtocolError`）而非连接错误。

### invalid_headers 标志

由解码回调针对以下任一情况设置为 `true`：

- 头部名称中的大写 ASCII（RFC 9113 s8.2）
- 连接专属头部：`connection`、`proxy-connection`、
  `transfer-encoding`、`upgrade`、`keep-alive`（RFC 9113 s8.2.2）
- 值为 `trailers` 之外的 `TE` 头部（RFC 9113 s8.2.2）
- 重复的伪头部（`:method`、`:scheme`、`:path`、`:authority`）
- 常规头部之后的伪头部
- 未知伪头部（以 `:` 开头但未被识别）
- 无效的 `content-length`（非数字）
- 存储写入失败（缓冲区已满）

解码后 `invalid_headers` 为 `true` 时：
- 对于请求：返回 `Err((H2Error::ProtocolError, false))` —— 流错误
- 对于响应：同样处理

错误元组中的 `false` 表示这是流级错误，而非连接级。
调用方发送 RST_STREAM 而非 GOAWAY。

### SETTINGS ACK 时的表大小同步

根据 RFC 7541 s4.2，HPACK 动态表大小必须在 SETTINGS 被确认时同步：

```rust
// 接收对端的 SETTINGS ACK 时：
self.decoder.set_max_allowed_table_size(
    self.local_settings.settings_header_table_size as usize,
);

// 接收对端的 SETTINGS 时：
self.peer_settings.settings_header_table_size = v;
self.encoder.set_max_table_size(v as usize);
```

解码器的允许表大小与我们 advertise 的一致；编码器表大小与对端
advertise 的一致。这防止了会导致 `CompressionError`（GOAWAY）
的失同步。

### 大头部后的缓冲区收缩

`converter_buf` 和 `lowercase_buf` 是在每次 `write_streams()` 周期
中移入和移出 `H2BlockConverter` 的可复用缓冲区：

```rust
// 从 converter 回收缓冲区后：
if self.converter_buf.capacity() > 16_384 {
    self.converter_buf.shrink_to(4096);
}
if self.lowercase_buf.capacity() > 16_384 {
    self.lowercase_buf.shrink_to(4096);
}
```

这防止单个具有异常大头部的请求永久膨胀连接生命周期内的内存。

---

## 测试

### 测试清单

185 个 e2e 测试，分布在 7 个文件中：

| 文件 | 数量 | 焦点 |
|------|-------|------|
| `e2e/src/tests/tests.rs` | 40 | 通用 HTTP 代理、keep-alive、路由、worker 生命周期 |
| `e2e/src/tests/h2_security_tests.rs` | 41 | 安全边界情况：洪水检测阈值、rapid reset、CONTINUATION 炸弹、settings flood、空 DATA flood、glitch 计数、畸形帧处理 |
| `e2e/src/tests/h2_tests.rs` | 64 | 协议正确性：HEADERS、DATA、流量控制、GOAWAY、流生命周期、优先级、HPACK、并发流、窗口更新、优雅关闭、H2 后端行为 |
| `e2e/src/tests/mux_tests.rs` | 21 | 跨协议场景：H1-to-H2 后端、H2-to-H1 后端、端到端 H2、混合协议组合 |
| `e2e/src/tests/h1_security_tests.rs` | 8 | H1 专属安全（请求走私、头部注入） |
| `e2e/src/tests/tls_tests.rs` | 6 | TLS 握手、ALPN 协商、证书处理、关闭语义 |
| `e2e/src/tests/tcp_tests.rs` | 5 | 原始 TCP 代理 |

### 测试基础设施

测试使用 `e2e` crate，提供：

- `mock::h2_backend` —— 基于 h2 crate 的 H2 后端模拟
- `mock::https_client` —— 支持 ALPN 的 TLS 客户端
- `mock::sync_backend` / `mock::async_backend` —— HTTP/1.1 模拟后端
- `sozu::worker` —— 用于集成测试的嵌入式 sozu worker

### h2spec 一致性

实现针对 145/145 个 h2spec 测试用例目标，以实现 RFC 9113 一致性。
h2spec 是外部一致性测试工具（https://github.com/summerwind/h2spec），
验证帧级协议正确性。

### 关闭聚焦的回归覆盖

最近的分支测试明确覆盖上述关闭强化：

- `test_h2_double_goaway_graceful_shutdown`
- `test_h2_graceful_shutdown_completes_large_transfer`
- `test_h2_graceful_shutdown_waits_for_inflight_request`

它们共同测试 double-GOAWAY 序列、worker 排空期间未完成的大响应完成、
以及软停止等待活动请求而非过早拆除会话的要求。

### 大资产 H1→H2 回归覆盖

从 H1 后端流向 H2 前端的 multi-MB 分块响应历史上是此分支上
wake-gap / 边缘触发就绪 bug 最热门的来源。
`e2e/src/tests/h2_correctness_tests.rs` 中的大资产套件锁定了这些修复：

- `test_h2_php_apache_chunked_flush_drains_fully` —— 312 KiB 分块正文，
  每块刷新节奏测试 `mux/h1.rs:341-346, 351-357`（C1）。
- `test_h2_slow_backend_idle_timeout_cancels` —— 64 KiB 分块正文在
  4 秒内流式传输，测试出站刷新 `stream_last_activity_at`（C2）。
- `test_h2_chunked_backend_crash_mid_stream_rsts` —— 验证分块-EOF
  降级到 `ParsingPhase::Error` + `RST_STREAM(InternalError)`（C3）。
- `test_h2_large_gzipped_chunked_drains_fully` —— 来自 cleverapps.io
  2026-04 工单的客户形状回归防护：7.76 MB 确定性负载，
  gzip 压缩并分块，通过扩展 `ChunkedFlushH1Backend` 服务，
  带有 `Content-Encoding: gzip`。客户端遵循 Chromium-146 配置
  （SETTINGS 带 `INITIAL_WINDOW_SIZE=6_291_456`，一次性
  `WINDOW_UPDATE(0, 15_663_105)`，每流 `WINDOW_UPDATE(sid, 32 KiB)`
  节奏，`priority: u=3, i`）。在 8 秒内断言 gzip 线路负载的
  sha256 字节一致性。流式排空辅助函数
  `drain_h2_stream_streaming` 通过边到达边哈希 DATA 负载，
  并在读取之间仅保留最多一帧的 `carry` 尾部，保持内存线性
  （而非每流一帧）。
- `test_h2_large_chunked_7mb_drains_fully` —— 纯规模伴侣。
  相同 7.76 MB 总量，`b'Z'` 填充，无 gzip —— 隔离 multi-MB
  排空 + Chromium 请求形状 + 每流 `WINDOW_UPDATE` 节奏，
  与内容编码交互隔离。

`H2FloodDetector` 将 stream-0 `WINDOW_UPDATE` 帧 capped 到
`DEFAULT_MAX_WINDOW_UPDATE_STREAM0_PER_WINDOW = 100` 每滑动窗口
（`lib/src/protocol/mux/h2.rs:259`，强制执行位于 `:856`）。
排空辅助函数仅刷新每流窗口；`h2_handshake_chromium_146` 期间的
一次性连接级突增是测试期间发出的唯一 stream-0 `WINDOW_UPDATE`。

### 安全属性

实现维护 H2 读写路径的零 panic 策略。所有可失败操作（帧解析、
HPACK 解码、缓冲区写入）返回错误，转换为 GOAWAY 或 RST_STREAM
而非 panic。`h2.rs` 顶部的编译时断言 guards 防止在 32 位以下
平台上的静默指针截断：

```rust
const _: () = assert!(
    std::mem::size_of::<usize>() >= 4,
    "sozu requires at least 32-bit pointers"
);
```
