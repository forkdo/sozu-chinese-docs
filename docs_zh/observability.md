# 可观测性 —— 架构与扩展点

本文档解释 Sōzu **如何**发出指标、日志、审计事件和追踪上下文，
接缝在哪里，以及添加新仪器时应遵循哪些约定。
**当前发出指标和访问日志字段**的清单参见
[`configure.md`](configure.md)。H2 mux 内部实现参见
[`h2_mux_internals.md`](h2_mux_internals.md)。

## 拓扑

每个 Sōzu worker 是一个**单线程 mio 事件循环**，具有三个并发可观测表面：

```
                            ┌──────────────────────────────┐
                            │       worker process          │
                            │                                │
   accept loop ──┐          │   ┌─ thread-local METRICS ─┐  │       ┌─ statsd UDP ─┐
   TLS handshake │          │   │                         │──┼──────▶│ network drain│
   H2 mux        │── incr! ─┼─▶ │   Aggregator            │  │       └──────────────┘
   H1 editor     │  count!  │   │  (counters, gauges,     │  │
   backend pool  │  gauge!  │   │   HDR-time histograms)  │──┼──┐
   socket I/O    │  gauge_  │   │                         │  │  │  ┌─ sozu CLI ─┐
   …             │  add!    │   └─────────────────────────┘  │  └─▶│ local drain│
                 │  time!   │                                 │     └────────────┘
                            │
                            │   log_context!  ─────────────► main log stream
                            │   (structured prefix)            (info/warn/error)
                            │
                            │   log_access!   ─────────────► access log stream
                            │   (RequestRecord)               (ASCII or protobuf)
                            │
                            │   SubscribeEvents bus ───────► control-plane events
                            │   (EventKind)                    (incl. audit log line — MUX-style, at info level)
                            └──────────────────────────────┘
```

三个属性塑造每个扩展点：

1. **每个 worker 单线程** —— 循环内无 `Arc<Mutex>`。
   `METRICS` 是 `thread_local!`（`lib/src/metrics/mod.rs`）。
2. **边缘触发的 epoll via mio** —— 从读路径排队的任何内容必须
   在 readiness tracker 上 `signal_pending_write`
   （agent memory 中的 `feedback_epollet_signal_pending_write`）。
   这只在 metrics socket 本身停滞时影响指标刷新时机 ——
   对仪器作者通常透明。
3. **处处使用 `&'static str` 键** —— 计数器和 gauge 只接受
   `&'static str` 键（`count_add` / `set_gauge` 的类型签名）。
   每错误 / 每类别细分必须在编译时实例化键。

## 指标原语

| 宏 | 签名 | 使用场景 | 示例 |
|---|---|---|---|
| `incr!(key)` / `incr!(key, cluster_id, backend_id)` | `&'static str` | 递增 1。3 参数形式带 cluster+backend 标签。 | `incr!("h2.frames.rx.data");` |
| `count!(key, value)` | `&'static str, i64` | 递增 N（如字节计数）。 | `count!("bytes_in", n as i64);` |
| `decr!(key)` | `&'static str` | 递减 1。与之前的 `incr!` 配对。 | `decr!("http.active_requests");` |
| `gauge!(key, value)` | `&'static str, usize` | **绝对快照。** ⚠️ 各发射点最后写入胜出 —— 仅对单一发射器的代理级状态安全（如 `client.connections`）。 | `gauge!("client.connections_max", n);` |
| `gauge_add!(key, delta)` / `gauge_add!(key, delta, cluster, backend)` | `&'static str, i64` | **生命周期增量。** 跨发射点正确聚合。每次 `+1` 配对关闭路径上的 `-1`。 | `gauge_add!("backend.pool.size", 1);` |
| `time!(key, ms)` / `time!(key, cluster_id, ms)` | `&'static str, usize` | 毫秒延迟。以 HDR 直方图存储在本地 drain。 | `time!("backend_response_time", cluster, ms);` |

### Gauge 正确性

最常见的指标 bug 是从每连接 / 每流上下文发出 `gauge!()`：
仪表板看到的值是"最后写入者写的值"，而非聚合状态。
**默认使用 `gauge_add!()` 用于从多个发射点递增的指标。**
H2 连接 gauge（`h2.connection.{active_streams,window_bytes,pending_window_updates}`）
在未发现此 bug 一段时间后转换为 `gauge_add!` 生命周期增量
加上 `impl Drop` 对称清理。

### Gauge 下溢

过去的生产事故（`a650ad69`、`d2f01ed4`）都来自
`gauge_add!(-1)` 在没有先运行配对 `+1` 的情况下运行。
`MetricValue::update` 和 `AggregatedMetric::update` 都将值饱和到 0，
并在 debug 和 release 构建中发出单行 `error!` 日志；都不 panic。
下次快照时指标仍错误，但进程继续运行，日志行命名出问题的键。
两种模式防止此类 bug：

1. **将增减与跟踪的状态共位。** 如果 gauge 测量"活跃后端连接"，
   在后端连接创建的同一点发出 `+1`，在关闭的同一点发出 `-1`。
2. **当关闭路径散布在代码库中时，将清理移入 `impl Drop`**
   （优雅关机、强制断开、panic-unwind）。
   `impl Drop for ConnectionH2` 是典范示例：
   无论哪条关闭路径运行，它减去连接曾经发出的任何
   `gauge_add!(+N)`。

### 基数预算

StatsD（UDP）宽容但 Prometheus / influxdb 不宽容。两条规则：

1. **仅静态键。** 键是 `&'static str` —— 通过 `concat!`、
   字面量或启动时 `LazyLock` 泄漏在编译时合成。
   每 IP 标签必须哈希到有界桶表（参见
   `lib/src/server.rs::PER_SOURCE_BUCKETS` 的典范 256 桶模式
   带 `LazyLock` 静态字符串数组）。
2. **可选粒度。** `MetricDetail`（proto）/
   `MetricDetailLevel`（config）让操作员选择
   `process | frontend | cluster | backend`。
   镜像 HAProxy 的 `extra-counters` 可选。
   新标签维度应尊重此旋钮；接线层是后续 MR。

### 本地 drain 重置周期

本地 drain（`LocalDrain` in `lib/src/metrics/local_drain.rs`）
维护两张地图：`proxy_metrics`（代理级）和 `cluster_metrics`
（每集群 + 每后端）。**两者自 worker 启动以来都是累积的。**
没有自动计时器重置它们 —— 曾经每秒 UTC 整点清除
`cluster_metrics` 的 wall-clock `if now.minute() == 0
&& now.second() == 0` 块被移除了，因为它在操作员仪表板中
产生虚假尖刺 / 归零，并且 gauge 必须在清除之间保留
（长生命周期 H2 会话可能在清除后关闭并使 gauge 计数器下溢）。
想要重置的操作员发出 `sozu metrics clear`（proto：
`MetricsConfiguration::Clear`），一次性清空两张地图
AND 清空 master 进程自己的 `main_metrics`。
`RemoveCluster` / `RemoveBackend` IPC 时也丢弃每集群条目，
因此退役集群不会泄漏指标键；在 StatsD
`network_drain` 上，相同两个事件丢弃集群的
`cluster_metrics`、`backend_metrics` 和排队 `MetricLine`s，
因此线端立即静音（集群的任何未发送 statsd 区间被丢弃 ——
有界于硬编码在 `NetworkDrain::send_metrics` 中的一秒网络 drain 周期）。

`RemoveCluster` 也为每个 drain 设置墓碑（`removed_clusters:
HashSet<String>`），以便后续对同一集群 ID 的发射在地板上丢弃，
而非通过 `entry().or_default()` 复活行。这在生产中有意义：
`lib/src/http.rs` / `https.rs` / `tcp.rs` 中的每代理
`remove_cluster` 路径丢弃集群配置但不关闭进行中的会话，
因此长生命周期 H2 / WebSocket / TCP 会话继续为已删除集群
发出访问日志 / 响应时间 / gauge 指标。没有墓碑，这些发射
会继续增长集群行直到最后会话关闭；有了墓碑，线和本地
drain 保持安静。墓碑在相同 ID 的 `AddCluster` 上清除
（集群可以在删除后回来）和 `sozu metrics clear` 上清除
（操作员发起的全量重置）。

对仪表盘的启示：`sozu metrics` 输出中的计数器是单调的；
图表应计算 `rate()` / `irate()` 而非将连续快照视为窗口计数。
直方图自 worker 启动以来累积每个样本，因此
`Percentiles.p_99` 是生命周期 p99，而非窗口化的。

每桶计数器是 `u64`，因此在现实 uptime / RPS 组合下无需担心饱和。

操作员清除注意事项：在实时流量期间发出 `sozu metrics clear`
会重置进行中的 gauge 准确性。在清除前打开的会话并在关闭时
递减 gauge（如 `connections_per_backend`）落在饱和到零的路径上，
每次发生发出单行 `error!` 日志，命名出问题的键。这是故意的；
新会话到达时 gauge 恢复。想要重置计数但保持活跃 gauge 完整
的操作员不应使用 `sozu metrics clear` —— 等待仪表板数学中
的累积计数器回绕。

## 日志原语

通过每协议 `log_context!` / `log_module_context!` /
`log_context_lite!` 宏的结构性前缀 —— 每文件定义：

| 前缀 | 文件 | 携带 |
|---|---|---|
| `MUX` | `protocol/mux/mod.rs` | session ULID, peer/local, frontend, backend list |
| `MUX-H2` | `protocol/mux/h2.rs` | …plus position, state, total RST counts, draining |
| `MUX-H1` | `protocol/mux/h1.rs` | …plus stream id, parked, close_notify |
| `MUX-ROUTER` | `protocol/mux/router.rs` | 通过 `HttpContext::log_context()` 渲染 `[session req cluster backend]` |
| `MUX-CONN` / `MUX-CONV` / `MUX-PARSER` / `MUX-PKAWA` / `MUX-STREAM` | 对应文件 | 仅模块级（无 per-session 上下文） |
| `KAWA-H1` | `protocol/kawa_h1/mod.rs` | session, frontend, request/response parsing phase |
| `RUSTLS` | `protocol/rustls.rs` | SNI/ALPN byte lengths, version, source, frontend |
| `PIPE` | `protocol/pipe.rs` | addresses, frontend/backend status & readiness |
| `TCP` | `tcp.rs` | frontend, backend, peer (缓存于 `SessionTcpStream`) |
| `SOCKET` | `socket.rs` | session, peer, local, RTT, state |

**约定：**

- 使用文件中定义的宏。不要从协议代码直接调用
  `log::info!`/`log::error!` —— 前缀标签对日志搜索是负载性的。
- 按意图分级严重性：`debug!`/`trace!` 用于预期的空闲关闭、
  超时、嘈杂状态。`warn!`/`error!` 用于真正的协议错误或
  不变式破坏。（参见 `feedback_log_context_before_theorising` 的推理。）
- 当 `HttpContext` 在作用域内时，优先使用
  `$http_ctx.log_context()`（`kawa_h1/editor.rs:587`）
  而非手工滚动 `LogContext { ... }` 结构体字面量 ——
  辅助函数是规范格式化器。

### 敏感值日志边界

`Debug` 在 Sōzu 中是生产日志投影，而非无损检查格式。
通用日志站点格式化命令请求、worker 响应、保留任务和状态、
router/listener 错误和 TLS 运行时对象使用 `{:?}`。
因此那些路径可达的每种类型必须在其字段可包含操作员或
客户控制材料时产生有界元数据。

受保护材料包括证书和私钥内容、链、证书名称和指纹、
证书查询域和结果、集群标识符、HTTP 路由 host/path/method/tag、
重定向和重写值、TCP SNI 和 ALPN 值、自定义答案键和身体、
和头名称和值。它们的日志投影可能仅保留操作有用的元数据，
如 socket 地址、枚举变体、布尔值、存在标志、集合计数和
聚合字节长度。证书和键槽除了其长度外渲染为 `[redacted]`。

典范的 `[session request cluster backend]` 前缀是显式
关联信封，不是通用对象转储：其 cluster/backend 槽保持无损，
以便操作员为一请求连接行。相同标识符在 `Debug` 输出、
保留任务/状态转储、错误文本或临时消息字段中出现时必须仍有界。
此例外仅限于命名的关联槽；它不允许在 verbose `Session(...)`
主体中包含原始 authority、path、method、SNI、ALPN、证书 SAN
或请求载荷字段。

在每个可到达日志sink的层应用边界：

- 携带敏感字段的生成 protobuf 类型在 `command/build.rs`
  中通过 `prost_build::Config::skip_debug` 列出；它们的
  有界实现在 `command/src/proto/mod.rs`。顶级
  `Request` 和其 `RequestType` 枚举仅渲染详尽请求种类，
  因此字符串值动词直接在 `WorkerRequest` 内也有界。
- 配置、响应、保留状态、gatherer、router、listener 和 TLS
  包装器必须总结自己的集合和字符串键地图，而非依赖
   enclosing 类型隐藏它们。`TaskContainer` 仅渲染
  具体任务种类和 timeout 存在；它从不委托给保留的
  `GatheringTask` 的 `Debug` 实现。
- 直接 `debug!`、`info!`、`warn!`、`error!` 和失败消息
  投影必须插值相同计数、种类、地址和字节长度。
  安全的 `Debug` 实现不能保护直接格式化原始字段的日志语句。
  TLS preread/handshake 和 mux 路由日志因此渲染
  cluster/authority/SNI/ALPN/SAN 计数、匹配种类和聚合
  字节长度而非单个值。
- 错误和 poisoned-lock 路径遵循相同规则；异常控制流
  不是披露被拒绝值或保留对象的权限。

这刻意是仅日志边界。protobuf wire 编码、Serde/JSON 输出、
保留状态键、证书查询响应载荷和存储在 `StateError`、
`RouterError` 和 `RetrieveClusterError::SniAuthorityMismatch`
中的原始字段保持不变。这些错误类型仅 bound `Display`/`Debug`；
匹配其公共变体的调用方仍接收完整标识符、前端键、拒绝原因、
host、path、method、SNI 值和 authorities。
用于操作/状态键的 `RequestHttpFrontend::Display` 也保持无损。
明确授权检索这些值的调用方继续接收它们；通用诊断不。

回归测试对每个受保护字段使用不同长哨兵，并断言合同的三部分：
哨兵不存在、预期计数/长度元数据存在、输出保持在固定大小界限内。
覆盖必须包括叶 `Debug` 实现、通用/嵌套命令包装器、
保留状态或任务、直接日志语句和运行时 TLS 及错误路径（如适用）。

### 每洪水检测器辅助宏模式

当违规漏斗（`H2FloodViolation`、`RustlsError`、`H2Error`）
需要每个变体的 `&'static str` 指标键时，定义 `concat!`-based 宏：

```rust
macro_rules! h2_error_metric_key {
    ($prefix:literal, $error:expr) => {
        match $error {
            H2Error::NoError => concat!($prefix, ".no_error"),
            H2Error::ProtocolError => concat!($prefix, ".protocol_error"),
            // …14 臂，穷举 —— 添加新 H2Error 变体在此处使构建失败
        }
    };
}
```

然后用每个方向一个辅助函数包装：

```rust
fn metric_for_goaway_sent(error: H2Error) -> &'static str {
    h2_error_metric_key!("h2.goaway.sent", error)
}
```

这使细分与底层枚举同步（新变体使构建失败），同时保留
`&'static str` 语义。

## 访问日志

模式在 `command/src/logging/access_logs.rs::RequestRecord`
中，protobuf wire 形状在
`command/src/command.proto::ProtobufAccessLog`。添加字段需要：

1. `RequestRecord<'a>` 上的字段（Rust 结构体，
   `lib/src/protocol/...` 填充）。
2. `ProtobufAccessLog` 上的字段（proto，追加新可选标签 ——
   从不重用或重新排序现有标签）。
3. 在每个发射点填充：
   - H1: `lib/src/protocol/kawa_h1/mod.rs::log_request`
   - H2 mux: `lib/src/protocol/mux/stream.rs::generate_access_log`
   - TCP: `lib/src/tcp.rs::log_request`
   - WS / WSS 升级后 pipe: `lib/src/protocol/pipe.rs::log_request`
4. 更新 `access_logs.rs` 中的 `RequestRecord::duplicate()`，
   以便 protobuf 路径序列化新字段。
5. 在 [`configure.md`](configure.md) §OpenTelemetry / §TLS
   握手元数据中记录该字段。

TLS 元数据字段（`tls_version`、`tls_cipher`、`tls_sni`、
`tls_alpn`）来自 `lib/src/https.rs` 的 rustls 握手上下文，
通过 `mux::Context` 传入 `HttpContext`。pipe 路径通过
`https.rs::upgrade_mux` 调用的 `Pipe::set_tls_metadata`
拾取它们。

## 追踪 —— 当前状态

**这只是 W3C `traceparent` 直通。** 无数 span 生命周期、
OTLP exporter、SDK 依赖。在 `opentelemetry` 编译时特性标志后：

- `traceparent` 在
  `lib/src/protocol/kawa_h1/editor.rs::on_request_headers`
  中解析（同一回调在 H1 上和通过 `pkawa.rs` 解码的 H2 帧上运行）。
- 为每个 Sōzu 跳生成新 span ID；值在出站请求上重写并存储在
  `HttpContext.otel` 上。
- 访问日志暴露 `trace_id`、`span_id`、`parent_span_id`。
- 访问日志包含 `start_time`（proto field 30, `Uint128`,
  纳秒纪元）—— 在请求开始时通过
  `SessionMetrics::mark_request_start()` 捕获的 wall-clock 时间戳。
  重建 OTel spans 的消费者应优先使用此字段而非
  `time - request_time`，后者混合 `CLOCK_REALTIME` 和
  `CLOCK_MONOTONIC`，在短生命周期请求上产生不可靠的开始时间戳。

要更进一步（真实 spans、OTLP exporter、B3/Datadog 传播），
参见 [`configure.md`](configure.md) 中的"超出范围"节。
它将位于新特性标志后，而非扩展 `opentelemetry` 的范围。

## 管控面审计 trail

unix 命令 socket 上的每个特权变更（`AddCluster`、
`RemoveCertificate`、`ActivateListener`、…）经过三个可观测表面：

1. 匹配的 `EventKind` 的 `Event` 发布到
   `SubscribeEvents` 总线。14 个变更变体枚举在
   `command/src/command.proto::EventKind`。
2. `incr!("config.<verb>")` 计数器递增（如
   `config.cluster_added`）。
3. 在 MUX 家族布局中以 `info!` 级别发出结构化审计日志行
   （关键字 `Command(...)` 而非 `Session(...)`，后者命名
   数据平面会话）。每个自由表单字段（`target`、
   `actor_comm`、`actor_user`、`socket`、`reason`）
   在渲染时消毒 —— 控制字符（`\x00..=\x1f`、`\x7f`）
   替换为 `?`，因此攻击者影响输入无法通过嵌入的
   `\t` / `\n` / ANSI 转义伪造额外审计行。渲染形式
   （ANSI 颜色关闭）：

   ```
   [01HXS4GZ9EYP3F2R7K8M6B4N2C 01HXS4H5K2QR9C7PVWXY8T6ZNA my_app -]	AUDIT	Command(verb=cluster_added, actor_uid=1000, actor_gid=1000, actor_pid=12345, actor_user=florentin, actor_comm=sozu, client_id=42, socket=/run/sozu/sozu.sock, target=cluster:my_app, result=ok, sozu_version=1.1.1)
   ```

   ### 字段参考

   **必填字段**（始终存在）：

   - `verb` —— 审计操作的稳定静态标识符
     （如 `cluster_added`、`state_loaded`、`listener_updated`）。
     每个 verb 一个 `config.<verb>` statsd 计数器。
   - `actor_uid` / `actor_gid` / `actor_pid` —— 来自
     unix 命令 socket 的 `SO_PEERCRED` 的对端凭据。
     读取失败 / 非 Linux 构建时为 `unknown`。
   - `actor_user` —— 解析的 POSIX 账户名
     （接受时的 `getpwuid_r(uid)`）。NSS 无 UID 匹配时为 `unknown`。
   - `actor_comm` —— 接受时的 `/proc/<pid>/comm`
     （最多 15 字符），让 SOC 区分带 `command` 子命令的
     `sozu` 二进制与共享 UID 的 ad-hoc shell。
   - `client_id` —— 每次接受单调计数器。不同于
     `session_ulid` 括号槽，后者作为单个 sozu CLI
     调用发出的每个 verb 的 grep 关联键存活。
   - `socket` —— 客户端连接的命令 socket 路径。
     让共享 SIEM sink 的多实例 sozu 部署选择
     每条行由哪个实例发出。
   - `target` —— verb 特定的自由表单描述符
     （如 `cluster:my-cluster`、`file:/var/lib/sozu/state.bin`、
     `stop:hard`、`listener:http:127.0.0.1:8080`）。
     对于 `UpdateHttp/Https/TcpListener`，每个补丁字段渲染为
     `field=old→new`。对于 `ReplaceCertificate`，
     旧和新证书指纹都包含（`certificate:<addr>:old=<fp>:new=<fp>`）。
     已消毒。
   - `result` —— `ok` 或 `err`。
   - `sozu_version` —— 构建时的 `CARGO_PKG_VERSION`。
     混合 fleet 审计流的取证钉。

   **可选字段**（相关时出现）：

   - `error_code` —— 结构化失败桶：
     `dispatch_error`、`worker_failure`、`worker_timeout`、
     `peer_cred_unavailable`、`invalid_input`、`io_error`、
     `other`。当 `result=err` 时存在。
   - `reason` —— 截断的人类可读失败详情（最多 256 字符，已消毒）。
     与 `error_code` 配对。
   - `elapsed_ms` —— 请求接受到审计发射之间的 wall-clock 时间。
     在完成时行上设置。
   - `fanout` —— worker fan-out 结果：
     `ok`、`partial`、`timeout` 或 `local_only`。
     对在 worker 上散射的 verb 在完成时设置。
   - `workers` —— 每 worker 计数
     `<ok>/<err>/<expected>`。与 `fanout` 配对。
   - `request_sha256` —— proto `Request` wire 编码的
     截断（64-bit，16 十六进制字符）SHA-256。
     对在 `worker_request` 流经的 verb 设置。
     用于去重 / 重放检测。

   ### 专用 sink：`audit_logs_target`

   操作员可以通过 `audit_logs_target` 配置选项将审计行路由到
   专用文件（区别于 `log_target`）。设置为纯文件系统路径
   （如 `/var/log/sozu/audit.log`）让每条审计行也追加到那里。
   文件以 `O_APPEND | O_CREAT` 和模式 `0o640`（所有者读写，
   组读）打开，因此授予 `audit` 组 tail-only 访问是一个
   文件系统 ACL 之遥。ANSI 转义序列在写入专用 sink 前剥离，
   因此文件保持 SIEM 可解析即使 `log_colored = true`。
   写入失败记录警告但不阻塞变更。
   `None`（默认）保持审计行仅通过 `log_target` 路由。

   ### JSON sink：`audit_logs_json_target`

   对于偏好不解析人类可读行的 SIEM 管道，
   `audit_logs_json_target` 将每行结构化 JSON 对象写入
   专用文件。相同 `O_APPEND | O_CREAT | 0o640` 语义。
   模式稳定；每个键始终存在，缺失值为 JSON `null`：

   ```json
   {
     "ts": "2026-04-23T13:14:15.123456Z",
     "boot_generation": 0,
     "session_ulid": "01HXS4GZ9EYP3F2R7K8M6B4N2C",
     "request_ulid": "01HXS4H5K2QR9C7PVWXY8T6ZNA",
     "actor": {
       "uid": 1000, "gid": 1000, "pid": 12345,
       "user": "florentin", "comm": "sozu", "role": "user"
     },
     "client_id": 42,
     "connect_ts": "2026-04-23T13:14:14.500000Z",
     "socket": "/run/sozu/sozu.sock",
     "verb": "cluster_added",
     "target": "cluster:my_app",
     "result": "ok",
     "cluster_id": "my_app",
     "backend_id": null,
     "sozu_version": "1.1.1",
     "build_git_sha": "9a1b2c3d4e5f",
     "extras": {
       "elapsed_ms": 17,
       "fanout": {"status": "ok", "workers_ok": 2, "workers_err": 0, "workers_expected": 2},
       "request_sha256": "0123456789abcdef"
     }
   }
   ```

   两个 sink 独立 —— 同时设置以获得操作员友好的 tail 流
   + 机器可解析归档。

   ### 保留策略

   PCI-DSS 10.7 要求审计 trail **保留 ≥ 1 年**，
   最近 **3 个月立即可用**进行分析。ISO 27001 A.8.15
   推荐类似但推迟到组织政策。

   `audit_logs_target` 和 `audit_logs_json_target` 是
   操作员 logrotate / 归档管道下的追加-only 文件 ——
   Clever Cloud Linux 部署的推荐形状是：

   - `/etc/logrotate.d/sozu` 每天旋转
     `/var/log/sozu/audit*.{log,jsonl}`，
     1 天后用 `xz` 压缩，90 天后归档离站。
   - 离站归档桶保留 **400 天**以清除 PCI-DSS 1 年窗口带缓冲。
   - 通过 `setfacl -m g:audit:r-x /var/log/sozu/`
     限制主机上读访问；仅 `audit` 组应能 tail 活文件。
   - 每行 stamped 的 `Server.boot_generation` 字段让
     日志分析器拼接跨热升级 re-exec 的会话而无需信任 PID。

   Sōzu 自身不旋转或压缩审计文件 —— 委托给 OS 级 rotator。
   想要原生旋转的操作员应使用带 `copytruncate` 指令的
   `logrotate`（因为 sōzu 保持文件句柄打开）或在 rename 后
   发送 `SIGHUP` 触发重新打开（尚未实现 —— TODO）。

   ### 每个 worker 散射 verb 两行

   散射到每个 worker 的 verb（AddCluster、RemoveHttpFrontend、
   UpdateHttpsListener、AddCertificate、…）发出**两条**
   审计行：

   - **尝试时**：`result=ok` 意味着"被主进程状态接受"。
     在 `state.dispatch` 成功后立即触发。无 fanout / elapsed_ms。
   - **完成时**：每个 worker 响应后（或散射超时触发）发出。
     携带 `fanout=ok|partial|timeout`、
     `workers=<ok>/<err>/<expected>`、`elapsed_ms`、
     和 —— 当 `result=err` 时 —— `error_code` + `reason`。

   操作员通过共享的
   `[session_ulid request_ulid …]` 括号关联两者。

   ### 仅本地 verb

   不散射的 verb —— `SoftStop`/`HardStop` 请求、
   `LoggingLevelChanged`、`UpgradeMain` / `UpgradeWorker`
   初始化、`SubscribeEvents`、`SaveState` 和
   `LoadState` 完成 —— 发出单条审计行携带
   `result` 和（如适用）`error_code` + `reason`。
   `LoadState` 和 `SaveState` 在 `target=file:<path>`
   中嵌入 `ok:<n> errors:<n>` 计数。

   括号槽遵循与 `MUX` / `MUX-ROUTER` / `RUSTLS` / `PIPE` /
   `TCP` 行共享的
   `[session_ulid request_ulid cluster_id|- backend_id|-]`
   约定。

`actor_uid` 通过 `SO_PEERCRED` 在 unix socket 接受时捕获
（`bin/src/command/server.rs`，存储在
`ClientSession.actor_uid`）。失败系统调用或非 Linux 构建
折叠为 `actor_uid=unknown` 而非 panic。这满足
PCI-DSS 10.2 / ISO 27001 A.8.15 / SOC 2 审计 trail
要求而无需外部审计 shim。

添加新审计 verb：

1. 在 proto 中添加 `EventKind` 变体（保留现有标签）。
2. 更新 `command/src/proto/display.rs` 中的 `Display for Event`。
3. 在 `bin/src/command/requests.rs` 处理器中：
   - 将 `Event` 推送到总线（找现有
     `EventKind::CLUSTER_ADDED` 发射点复制）。
   - 发射 `incr!("config.<verb>")`。
   - 通过 `audit_log_context!` 宏在
     `bin/src/command/requests.rs` 中发射审计行 ——
     它自动将 verb 渲染到 MUX
     `Session(verb=..., actor_uid=..., client_id=...,
     target=..., result=...)` 块中。

## 扩展检查清单

合并仪器变更前：

- [ ] 指标键是 `&'static str`（编译时字面量或 `LazyLock` 泄漏）。
- [ ] 每方向 / 每错误 / 每帧细分使用 `concat!`-based 辅助宏，
  使构建在新枚举变体时失败。
- [ ] 基数有界 —— 要么无标签，要么标签来自固定大小表，
  要么哈希到已知大小的桶中。
- [ ] 从多个点发射的 gauge 使用 `gauge_add!`（生命周期增量）
  并在关闭路径上将每个 `+N` 与 `-N` 配对。考虑
  `impl Drop` 用于对称清理。
- [ ] 新协议模块定义自己的 `log_context!` /
  `log_module_context!` 带唯一前缀标签。
- [ ] 从敏感命令、状态、路由或 TLS 数据可达的类型和直接
  日志站点仅暴露有界计数/长度/种类/地址，带有
  哨兵缺席和固定输出界限回归测试。
- [ ] 新访问日志字段落在 `RequestRecord`、
  `ProtobufAccessLog`（新标签）、所有四个发射点和
  `RequestRecord::duplicate()` 上。
- [ ] [`configure.md`](configure.md) 在同一 changeset 中更新。
- [ ] 特权管控面 verb 落地 `EventKind` +
  `config.<verb>` 计数器 + 审计日志行
  （MUX `Session(...)` 布局、`info!` 级别、
  通过 `audit_log_context!` 宏路由）。

## 参见

- [`configure.md`](configure.md) —— 当前发出指标、访问日志字段、
  OpenTelemetry 通穿的完整清单。
- [`h2_mux_internals.md`](h2_mux_internals.md) —— H2 mux 状态机
  和洪水检测器设计。
- [`lib/src/protocol/mux/LIFECYCLE.md`](../lib/src/protocol/mux/LIFECYCLE.md)
  —— 带 `file.rs:LINE` 引用 的流/槽生命周期。
- [`CLAUDE.md`](../CLAUDE.md) —— agent 约定包括日志宏纪律、
  指标宏列表和安全敏感区域。
