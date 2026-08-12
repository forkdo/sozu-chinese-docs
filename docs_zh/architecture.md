# 架构

这部分主要面向希望了解 sōzu 工作原理的人。

## 主/工作进程模型

Sōzu 采用一个主进程和多个工作进程的模式。这使得当一个工作进程遇到问题并崩溃时，它能继续运行，并在必要时逐个升级工作进程。

### 单线程，无共享架构

每个工作进程运行一个单线程，并带有一个基于 epoll 的事件循环。为避免同步问题，每个工作进程都拥有整个路由配置的副本。路由的每一次修改都通过配置消息进行。日志和指标由每个工作进程单独发送，将聚合和序列化事件的工作留给外部服务。
所有监听的 TCP 套接字都使用 [SO_REUSEPORT](https://lwn.net/Articles/542629/) 选项打开，允许多个进程在同一地址上监听。

### 配置

外部工具通过一个 unix 套接字与主进程交互，配置更改消息将由主进程分发给工作进程。
配置消息是“差异”，例如“添加一个后端服务器”或“删除一个 HTTP 前端”，而不是一次性更改整个配置。这使得 sōzu 能够在有流量的情况下更智能地处理配置更改。

配置消息以 protobuf 二进制格式传输，它们定义在 [command 库](https://github.com/sozu-proxy/sozu/tree/main/command)中。有三种可能的消息回复：processing（表示消息已收到但更改尚未生效）、failure 或 ok。

主进程暴露一个用于配置的 unix 套接字，而不是在 localhost 上暴露一个 HTTP 服务器，因为 unix 套接字的访问可以通过文件系统权限来保护。

## 代理

### 使用 mio 的事件循环

每个工作进程都运行一个基于 epoll（在 Linux 上）或 kqueue（在 OSX 和 BSD 上）的事件循环，使用 [mio 库](https://github.com/tokio-rs/mio)。

Mio 提供了一个跨平台抽象，允许调用者接收事件，例如套接字变为可读（意味着它收到了一些数据）。

Sōzu 要求 mio 以[边缘触发模式](http://man7.org/linux/man-pages/man7/epoll.7.html)发送套接字的所有事件。
这样，它只接收一次事件，并将其存储在一个
[`Readiness` 结构体](https://github.com/sozu-proxy/sozu/blob/main/lib/src/lib.rs)中。
然后它将使用该信息和“兴趣”（指示当前协议状态机是否想在套接字上读取或写入）。

每个套接字事件都带有一个 `Token` 返回，指示其在 `Slab` 数据结构中的索引。一个客户端会话可以有多个套接字（通常是一个前端套接字和一个后端套接字）。

### 协议

每个代理实现（HTTP、HTTPS 和 TCP）将在每个客户端会话中使用一个状态机来描述当前使用的协议。它旨在允许从一个协议升级到下一个协议。例如，你可以有以下 progression：

- 在 TLS 握手协议中启动
- 握手完成后，升级到最近协商的 TLS 流上的 HTTP 协议
- 升级到 websockets

每个协议都将与 `Readiness` 结构一起工作，以指示它是否想在每个套接字上读取或写入。例如，[基于 rustls 的握手](https://github.com/sozu-proxy/sozu/blob/main/lib/src/protocol/rustls.rs) 只对前端套接字感兴趣。

第四个代理实现 **UDP**，对数据报流量（DNS、syslog、NTP、通用 UDP）进行负载均衡。它是无连接的，因此刻意位于上述按会话 `accept()`/状态机模型之外：单个监听器套接字服务于多个虚拟四元组*流*，每个流都有自己已连接的上游套接字用于对称的 NAT 回程。流的完整生命周期、用户态 conntrack 流表、拆除以及加固规则，在 [`lib/src/protocol/udp/LIFECYCLE.md`](https://github.com/sozu-proxy/sozu/tree/main/lib/src/protocol/udp/LIFECYCLE.md) 中端到端地逐步讲解（含 `file.rs:LINE` 引用）。另请参阅 [`lib/src/protocol/udp`](https://github.com/sozu-proxy/sozu/tree/main/lib/src/protocol/udp) 以及 [`doc/configure.md`](configure.md) 的 UDP 章节。

它们都在 [`lib/src/protocol`](https://github.com/sozu-proxy/sozu/tree/main/lib/src/protocol) 中定义。

### HTTP/2 与 Mux 层

HTTP/2 支持通过 `lib/src/protocol/mux/` 中统一的复用器（`Mux`）实现。
Mux 层通过带有 `H1` 和 `H2` 变体的 `Connection` 枚举来处理 HTTP/1.1 和 HTTP/2 连接，
从而支持前端和后端协议的任意组合。

#### 协议组合

```
  Client             Sōzu               Backend
  ──────           ────────            ─────────
   H1  ──────────▶  Mux  ──────────▶   H1        (classic)
   H1  ──────────▶  Mux  ──────────▶   H2        (H2 backend, h2c)
   H2  ──────────▶  Mux  ──────────▶   H1        (H2 frontend, H1 backend)
   H2  ──────────▶  Mux  ──────────▶   H2        (end-to-end H2)
```

前端协议由 TLS 握手期间的 ALPN 协商决定（明文则使用 H2 prior knowledge）。
后端协议由 `cluster.http2` protobuf 配置标志控制。

#### Mux 会话结构

一个 `MuxState` 会话拥有一个前端 `Connection` 以及一个包含零个或多个后端 `Connection` 的 `Router`。
所有连接共享一个持有 `Vec<Stream>` 的 `Context`。

```
MuxState
├── frontend: Connection<FrontRustls>     ◄── one frontend socket
│   ├── H1(ConnectionH1)                      (either H1 or H2)
│   └── H2(ConnectionH2)
│
├── router: Router
│   └── backends: HashMap<Token, Connection<TcpStream>>
│       ├── Token(7)  → H1(ConnectionH1)  ◄── backend to cluster "app-1"
│       ├── Token(12) → H2(ConnectionH2)  ◄── backend to cluster "app-2" (h2c)
│       └── ...
│
└── context: Context
    ├── streams: Vec<Stream>              ◄── shared stream pool
    │   ├── [0] Stream { state: Linked(Token(7)),  front: Kawa, back: Kawa, ... }
    │   ├── [1] Stream { state: Linked(Token(12)), front: Kawa, back: Kawa, ... }
    │   ├── [2] Stream { state: Recycle, ... }
    │   └── ...
    ├── pool: Weak<RefCell<Pool>>         ◄── buffer allocator
    └── listener: Rc<RefCell<L>>
```

#### 流生命周期

每个 `Stream` 在处理请求/响应对时经历不同的状态：

```
             ┌──────────────────────────────────────────────────┐
             │                                                  │
             ▼                                                  │
          ┌──────┐   HEADERS    ┌──────┐   connect()   ┌────────┐
  new ──▶ │ Idle │ ──────────▶ │ Link │ ────────────▶ │ Linked  │
          └──────┘   received   └──────┘   to backend  │(Token)  │
             ▲                                          └────┬───┘
             │                                               │
             │       ┌─────────┐   response    ┌─────────┐   │ backend
             │       │ Recycle │ ◀──────────── │end_stream│ ◀─┘ done or
             │       └────┬────┘   complete     └─────────┘    error
             │            │                         │
             │ reuse      │                         │ can't retry
             └────────────┘                         ▼
                                              ┌──────────┐
                                              │ Unlinked │ ──▶ error response
                                              └──────────┘
```

- **Idle**：流已分配但还没有请求。在 H2 中，处于此状态的流可以从先前的请求回收。
- **Link**：请求头已解析完毕，等待 `Router` 连接到后端。
- **Linked(Token)**：已连接到由 `Token` 标识的后端。数据双向流动。
- **Unlinked**：后端已断开且请求无法重试。会生成默认错误响应（502/503/504）。
- **Recycle**：响应已完全发送。在 H2 中，流被归还到池中以便复用。
  在 H1 中，会话关闭或重置以支持 keep-alive。

#### StreamParts：方向感知的借用

一个 `Stream` 包含两个 Kawa 缓冲区（`front` 和 `back`）。`split(&position)` 方法
返回一个 `StreamParts` 结构体，带有与方向对应的别名：

```
                        Stream
             ┌─────────────────────────┐
             │  front: Kawa (Request)  │
             │  back:  Kawa (Response) │
             │  window: i32            │
             │  context: HttpContext    │
             └────────┬────────────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
   Position::Server          Position::Client
   (frontend conn)           (backend conn)
          │                       │
          ▼                       ▼
   StreamParts {             StreamParts {
     rbuffer: &front,          rbuffer: &back,
     wbuffer: &back,           wbuffer: &front,
     window, context           window, context
   }                         }
```

前端（Server 位置）从 `front` 读取并写入 `back`。
后端（Client 位置）从 `back` 读取并写入 `front`。
这种反转是让 H1 和 H2 连接能够共享流的关键抽象。

#### H2 连接状态机

每个 `ConnectionH2` 运行一个帧级别的读取状态机。该结构体被分解为若干逻辑子结构体以便维护：

- `H2FlowControl` —— 连接级窗口、对端窗口、初始窗口大小
- `H2ByteAccounting` —— 开销字节、零窗口计数
- `H2DrainState` —— GoAway 已发送标志、最后一个流 ID、待处理 RST 流
- `H2FloodConfig` —— 6 个可配置的洪水检测阈值（按监听器）
- `Prioriser` —— 每个流的 RFC 9218 紧急度 + 增量跟踪

详细内部机制请参阅 [h2_mux_internals.md](./h2_mux_internals.md)。

H2 状态机：

```
              ┌───────────────┐
              │ ClientPreface │   (server waits for "PRI * HTTP/2.0..." + SETTINGS)
              └───────┬───────┘
                      │ preface valid
                      ▼
              ┌───────────────┐
              │ServerSettings │   (server sends own SETTINGS + ACK)
              └───────┬───────┘
                      │ settings exchanged
                      ▼
     ┌──────────────────────────────────┐
     │            Header                │ ◄──────────────────────────┐
     │  (read 9-byte frame header)      │                            │
     └───────────────┬──────────────────┘                            │
                     │ parsed FrameHeader                            │
                     ▼                                               │
     ┌──────────────────────────────────┐                            │
     │         Frame(header)            │   expect_header()          │
     │  (read payload_len bytes)        │ ──────────────────────────▶│
     └───────────────┬──────────────────┘                            │
                     │                                               │
          ┌──────────┼───────────┐                                   │
          │          │           │                                    │
          ▼          ▼           ▼                                    │
     HEADERS      DATA      SETTINGS/PING/...                        │
     (if end_headers=0)         │                                    │
          │                     └────────────────────────────────────▶│
          ▼                                                          │
     ┌──────────────────────┐                                        │
     │ ContinuationHeader   │  (read 9-byte continuation header)     │
     └──────────┬───────────┘                                        │
                │                                                    │
                ▼                                                    │
     ┌──────────────────────┐                                        │
     │ ContinuationFrame    │  (accumulate header block)             │
     └──────────┬───────────┘                                        │
                │ end_headers=1                                      │
                └────────────────────────────────────────────────────▶│
                                                                     │
     ┌──────────────────────┐                                        │
     │       GoAway         │  (drain: send GOAWAY, close)           │
     └──────────────────────┘                                        │
     ┌──────────────────────┐                                        │
     │       Error          │  (protocol error detected)             │
     └──────────────────────┘
```

在写入时，`writable()` 方法委托给 `write_streams()`，后者按 RFC 9218 紧急度
（紧急度越低 = 优先级越高）对所有流排序，然后在相同紧急度内按流 ID 进行 FIFO。
每个流的 Kawa 块通过 `H2BlockConverter` 转换为 H2 帧。连接级和流级的流控窗口
限制了每次迭代可发送的 DATA 字节数。

#### H2 流控

流控在每个 RFC 9113 §6.9 的两个层级上运作：

```
    ConnectionH2                          Stream
  ┌──────────────┐                    ┌──────────────┐
  │ window: i32  │  ◄── connection    │ window: i32  │  ◄── stream
  │              │      level         │              │      level
  └──────┬───────┘                    └──────┬───────┘
         │                                   │
         │  effective window = min(connection.window, stream.window)
         │
         ▼
  Sending DATA: decrement both windows by bytes sent.
  Receiving DATA: track received_bytes_since_update.

  When received_bytes_since_update > initial_window_size / 2:
    → Queue connection-level WINDOW_UPDATE
    → Queue stream-level WINDOW_UPDATE
    → Flush during writable() before sending DATA
```

WINDOW_UPDATE 帧按流 ID 在 `pending_window_updates` 中合并，并在 `writable()` 开始时
内联冲刷，避免额外的事件循环迭代。

#### H2 帧处理流水线

```
  Socket ──read──▶ zero.storage ──parse──▶ FrameHeader ──▶ Frame
                   (connection                              │
                    buffer)                                  │
                                                ┌───────────┼───────────┐
                                                ▼           ▼           ▼
                                             HEADERS      DATA     SETTINGS
                                                │           │        PING
                                                │           │       GOAWAY
                                                ▼           ▼      WINDOW_UPDATE
                                          ┌──────────┐ ┌────────┐
                                          │  pkawa   │ │ stream │
                                          │  HPACK   │ │ .front │
                                          │  decode  │ │ .push  │
                                          │  + kawa  │ │ _block │
                                          │  blocks  │ └────────┘
                                          └──────────┘

  stream.back ──kawa::prepare()──▶ H2BlockConverter ──▶ HPACK encode
                                                           │
                                   gen_frame_header() ◄────┘
                                          │
                                          ▼
                                   kawa.out ──write──▶ Socket
```

- **入站**：`parser.rs`（nom）解码二进制帧。`pkawa.rs` 将 HPACK 头解码为 Kawa 块。
  DATA 载荷是对流存储缓冲区的零拷贝切片。
- **出站**：`converter.rs`（`H2BlockConverter`）将 Kawa 块编码为 H2 帧。
  HPACK 编码使用 `loona-hpack::Encoder`。大型头块会自动拆分为
  HEADERS + CONTINUATION 帧，以遵守 `max_frame_size`。

#### 模块布局

```
lib/src/protocol/mux/
├── mod.rs          Mux 会话、Stream、Router、ready() 循环、流生命周期 (1818 行)
├── h1.rs           HTTP/1.1 连接 (ConnectionH1) (823 行)
├── h2.rs           HTTP/2 连接 (ConnectionH2)、状态机、流控、
│                   flood 检测、RFC 9218 优先级、关闭处理 (7562 行)
├── parser.rs       H2 二进制帧解析器 (nom)、线格式常量 (2246 行)
├── serializer.rs   H2 帧序列化器 (cookie-factory)、SETTINGS/GOAWAY/RST_STREAM (557 行)
├── converter.rs    Kawa → H2 帧转换器 (H2BlockConverter)、HPACK 编码 (1410 行)
├── pkawa.rs        H2 → Kawa 转换器、HPACK 解码、伪头验证、
│                   RFC 9218 优先级头解析 (2229 行)
├── connection.rs   共享的前端/后端连接类型与簿记 (578 行)
├── router.rs       后端拨号 / 池 / Router::connect 编排 (678 行)
├── stream.rs       每流状态、所有权、双向 EOS 跟踪 (290 行)
├── answers.rs      Mux 侧默认 HTTP 应答 (302 行)
├── shared.rs       跨连接共享状态 (93 行)
└── debug.rs        诊断辅助 (80 行)
```

总计：13 个模块共 18 666 行 Rust。运行
`wc -l lib/src/protocol/mux/*.rs` 可在任意 HEAD 上重新推导。

#### 关键设计决策

mux 在分支上积极维护的参考是
`lib/src/protocol/mux/LIFECYCLE.md`，它以 `file.rs:LINE` 引用对照当前 HEAD
逐步讲解每一次状态转换。

- **双向端到端流跟踪**：每个 `Stream` 上独立的 `front_received_end_of_stream` 和
  `back_received_end_of_stream` 字段，防止前端和后端连接相互干扰对方的流状态。
- **无共享流池**：流存储在按 `GlobalStreamId` 索引的 `Vec<Stream>` 中。每个 `ConnectionH2`
  通过 `HashMap<StreamId, GlobalStreamId>` 将自己的 H2 流 ID 映射到全局 ID。这使得
  H2 前端和 H2 后端能够引用同一个流而无需共享所有权。
- **HPACK 安全性**：解码回调（`pkawa.rs`）使用可失败的 `write_all()` 调用，并按
  RFC 9113 §8.2 校验头（无大写、无连接相关头、伪头顺序）。无效头触发流重置，而非连接错误。
- **GoAway 排干**：收到 GoAway 帧时，连接进入 `draining` 模式。新流被拒绝，但已有流
  正常完成。高于 `peer_last_stream_id` 的流有资格在新连接上重试。
- **主动驱动的优雅关闭**：在 worker 排干期间，mux 层在常规 epoll 循环之外强制进行
  H2 可读、可写遍历，以便观察最终的對端 EOF / END_STREAM 事件、冲刷 GOAWAY 和 TLS 记录，
  并清理由不完整的 HEADERS 块创建的陈旧流映射。
- **H2 后端（h2c）**：由 `command/src/command.proto` 中的 `cluster.http2` 控制。
  Sōzu 与后端使用明文 H2 通信。`:scheme` 伪头派生自前端监听器协议（HTTP 或 HTTPS），
  而非后端连接。`cluster.http2` 仅是后端能力提示 —— 它不控制前端 H2。
  前端 H2 由监听器上的 TLS ALPN 协商驱动（`alpn_protocols` 包含 `"h2"`）；
  一个 `http2 = false` 的集群仍可在前端为 H2 客户端提供服务，在后端边界进行 H2 → H1 转换。
- **RFC 9218 优先级**：`Prioriser` 结构体从 `priority` 头跟踪每个流的紧急度（0-7）和
  增量标志。`write_streams()` 中的流调度先按紧急度排序（越低 = 优先级越高），再按流 ID 排序。
  默认紧急度按 RFC 9218 为 3。
- **可配置的洪水检测**：六个阈值（RST_STREAM、PING、SETTINGS、空 DATA、CONTINUATION、
  glitch 计数）可通过 protobuf 按监听器配置，并带有编译期默认值。超出任一阈值都会触发
  GOAWAY(ENHANCE_YOUR_CALM)。
- **按比例分配开销**：连接级开销字节（SETTINGS、PING、WINDOW_UPDATE）按各流传输的字节数
  成比例地分配给流，而非平均分配。这确保了按流计费的准确性和指标的准确性。
- **OpenTelemetry 追踪传播**：在 `opentelemetry` 特性标志之后，在 H2 流创建期间提取
  `traceparent`/`tracestate` 头，并传播进访问日志条目，用于分布式追踪关联。

## 日志记录

[记录器](https://github.com/sozu-proxy/sozu/tree/main/command/src/logging) 旨在使用 Rust 的格式化系统减少分配和字符串插值。它可以在各种后端上发送日志：stdout、文件、TCP、UDP、Unix 套接字。

记录器可以通过一个线程局部存储变量从任何地方通过日志宏调用。

## 指标

[指标](https://github.com/sozu-proxy/sozu/tree/main/lib/src/metrics) 的工作方式与记录器类似，可以通过宏和 TLS 从任何地方访问。我们支持两种“drains”：一种通过 statsd 兼容协议在网络上发送指标，另一种在本地聚合指标，以通过配置套接字进行查询。

## 负载均衡

对于给定的集群，Sōzu 维护一个后端列表，连接将被重定向到这些后端。
Sōzu 检测损坏的服务器，并仅将流量重定向到健康的服务器，有多种可用的负载均衡算法：
轮询（默认）、随机、最少连接和二次幂。

## TLS

Sōzu 是一个由 rustls 支持的 TLS 端点。
它使用 TLS 密钥和证书解密流量，并将其未加密地转发到后端。

## 深入探讨

### 缓冲区

Sōzu 经过优化，内存使用非常有限。
所有流量都（短暂地）存储在一个固定大小（通常为 16 kB）的可重用缓冲区池中。

### 通道

它们是 unix 套接字之上的一个抽象层，使与 sōzu 的通信更容易。
