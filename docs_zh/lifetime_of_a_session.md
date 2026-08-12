# 会话的生命周期

## 1. 目标读者与目的

这是“一个请求如何流经 Sōzu”的运维与新贡献者入门点。它解释了单线程 mio worker、
各协议状态机的位置、HTTP/1.1 与 HTTP/2 的边界划分，以及接下来应该阅读哪些文件。

关于各协议的深入细节，请跟随这些 `LIFECYCLE.md` 姊妹篇：

- HTTP/2 复用器：[`lib/src/protocol/mux/LIFECYCLE.md`](../lib/src/protocol/mux/LIFECYCLE.md)
- HTTP/1.1（由 Kawa 支撑）：[`lib/src/protocol/kawa_h1/LIFECYCLE.md`](../lib/src/protocol/kawa_h1/LIFECYCLE.md)
- PROXY 协议预检：[`lib/src/protocol/proxy_protocol/LIFECYCLE.md`](../lib/src/protocol/proxy_protocol/LIFECYCLE.md)
- UDP 数据报流（无连接；位于按会话模型之外）：[`lib/src/protocol/udp/LIFECYCLE.md`](../lib/src/protocol/udp/LIFECYCLE.md)
- 主/工作进程监管：[`bin/src/command/LIFECYCLE.md`](../bin/src/command/LIFECYCLE.md)

本文保持叙述性。所引用的路径相对于仓库；已移除带 SHA 固定的永久链接，因为它们会过时。

## 2. 概念原语

### 2.1 mio 事件循环

一个 Sōzu 工作进程是一个拥有单个 `mio::Poll`（`lib/src/server.rs:323, 342`）的操作系统线程。
在 Linux 上它是对 `epoll(7)` 的薄封装；在 BSD 和 macOS 上是 `kqueue(2)`。该 worker
将所有套接字 —— 监听套接字、前端、后端、指标、unix 命令通道对 —— 都注册到这一个
轮询器上，然后循环从 `Events` 中读取事件并分发给正确的会话。循环时间可通过
`epoll_time` time! 指标观测（`lib/src/server.rs:593-595`）。

### 2.2 边沿触发就绪与可写不变量

mio 以边沿触发模式运行：当套接字切换为可读或可写时，内核只通知 worker 一次。
如果 Sōzu 在那次唤醒时没有把内核缓冲区完全排空，在*下一个*边沿到来之前它不会收到其他事件。

为了在这种约定下存活，每个协议模块都通过 `Readiness` 跟踪器
（`lib/src/protocol/mux/connection.rs:200, 203`）路由其就绪状态，并使用两个辅助函数：

- `signal_pending_write` —— 由已经产生、最终必须发出字节的代码设置，即便可写的
  epoll 边沿可能已经被消费掉了。
- `arm_writable` —— 当字节从*可读*代码路径排入队列时设置，以便下一次泵循环迭代
  无需等待另一次内核唤醒就把它们写出。

如果新代码从可读路径排入了输出字节，却忘记调用 `arm_writable`（mux）或
`signal_pending_write`（kawa_h1 / pipe），会话就会“卡住” —— 字节停留在缓冲区中，
下一次 epoll 事件永远不会到达。这个分支上过去的截断 bug 全都源于此。`mux::answers`
模块将其记录为“invariant-15 pair”（`lib/src/protocol/mux/answers.rs:280, 298`）；
该不变量的归属地在 `mux::connection`（`lib/src/protocol/mux/connection.rs:14`）。

### 2.3 Token、SessionManager 与 slab

每次 mio 注册都携带一个 `Token`（一个 `usize`）。`SessionManager`
（`lib/src/server.rs:166`）拥有一个 `Slab<Rc<RefCell<dyn ProxySession>>>`
（`lib/src/server.rs:170`），将每个 token 映射回拥有该注册的会话。这个 slab 同时也是
执行 `max_connections`（`lib/src/server.rs:188, 194`）并计量
`client.connections`、`client.connections_max`、`client.connections_percent`、
`slab.{entries,capacity,usage_percent,accept_threshold_percent}` 以及
`buffer.{in_use,capacity,usage_percent}` 的记账单元，这些都在每次运行循环迭代中
于 `Server::run`（`lib/src/server.rs`）采样一次。

一个会话在转发流量时通常会占据*两个* slab 条目：一个是前端 token（在客户端连接
被接受时注册），另一个是后端 token（在 `connect_to_backend` 成功后注册）。这是
新贡献者最大的心智模型调整：同一个会话可以通过两个不同的键访问到。

监听套接字本身作为 `ListenSession` 条目存储在同一 slab 中
（`lib/src/server.rs:1920`），这正是让同一个事件循环能够在数据事件之外复用
accept 事件的原因。

### 2.4 三个代理

一个 worker 承载三种代理类型，每种对应一个受支持的监听器协议：

- `HttpProxy`（`lib/src/http.rs:762`）
- `HttpsProxy`（`lib/src/https.rs:1319`）
- `TcpProxy`（`lib/src/tcp.rs`）

每个代理拥有自己的监听器、已知的前端和集群、每协议配置（TLS 材料、ALPN 列表、
H2 旋钮等），以及将会话从一层协议提升为下一层的升级路径。

## 3. 接受连接

### 3.1 监听器与 SO_REUSEPORT

监听套接字通过 `lib/src/socket.rs` 创建，启用了 `SO_REUSEPORT`
（`lib/src/socket.rs:1023`）；同一 Sōzu 进程中的多个 worker 共享每个监听器地址，
内核将 accept 事件分发到它们之间。每个监听器都注册到 mio，并通过一个 `ListenSession`
slab 条目跟踪。热重配置通过主到 worker 的通道在运行时添加和移除监听器
（`lib/src/server.rs:1255, 1286, 1313, 1477, 1524, 1565`）。

### 3.2 接受队列

当监听器变为可读时，代理在一次批处理中接受每一个待处理的连接，并把每个 `TcpStream`
停放在内部的 `accept_queue: VecDeque<…>`（`lib/src/server.rs:294`）上。会话
*不会*在 accept 循环内同步创建。队列稍后按最新优先的顺序排空，因此等待过久的连接
在被变成会话之前就会被丢弃。截止时间是 `accept_queue_timeout`（`lib/src/server.rs:287`）。

### 3.3 背压与 `max_connections`

如果 slab 已满（`SessionManager::can_accept` 为 `false`，`lib/src/server.rs:188`），
代理会停止排空接受队列，内核的监听积压会吸收多余的流量。在这种状态下
`accept_queue.backpressure` 计量翻转为 1（`lib/src/server.rs:196, 207`）；一个 1 Hz 的
定时器还会累加 `accept_queue.saturated_seconds`，以便仪表盘能绘制 worker 处于背压状态
的时长（`lib/src/server.rs:104-107, 682-699`）。系统在 `max_connections` 的 90% 处
解除背压，以避免抖动（`lib/src/server.rs:244-249`）。

### 3.4 僵尸检测

一个周期性的“僵尸检查器”遍历 slab，并强制关闭看起来卡住的会话 —— 通常是因为
别处的逻辑 bug。这是一个安全网，而非主要的生命周期机制。

## 4. TLS 握手（仅 HTTPS）

对于 `HttpsProxy` 会话，裸 TCP 之上的第一层协议是 TLS。Sōzu 使用
[rustls](https://docs.rs/rustls) 并为每个会话实例化一个 `rustls::ServerConnection`
（`lib/src/protocol/rustls.rs:12, 76, 94`）。握手本身由 `lib/src/protocol/rustls.rs`
驱动；监听器级别的配置（证书存储、ALPN 列表、SNI 绑定策略）位于 `lib/src/https.rs`
和 `lib/src/tls.rs`。

### 4.1 SNI / `:authority` 绑定

如果在监听器上启用了 `strict_sni_binding`（`command/src/config.rs:388`），Sōzu 会拒绝
任何其 `:authority`（H2）或 `Host`（H1）未被本 TLS 会话所提供证书的 SAN 覆盖的
HTTP 请求，并采用 RFC 6125 §6.4.3 的通配符处理。这与 Firefox / Chrome 的连接合并
语义（RFC 7540 §9.1.1 / RFC 9113 §9.1.1）一致 —— 浏览器对由所提供证书的
SubjectAlternativeName dNSName 条目覆盖的任何源复用单个 H2 连接（RFC 6125 §6.4.4：
当存在 SAN dNSName 时，忽略 CN）。未命中的请求以 421 Misdirected Request
（RFC 9110 §15.5.20）应答，两种浏览器都会通过在正确的 SNI 上打开一个新连接来处理。
SAN dNSName 快照在握手时一次性捕获（镜像浏览器的缓存语义），并作为 `tls_cert_names`
存储于 mux `Context` 上；即使运维在连接进行中更换底层证书，它也会在连接生命周期内
被冻结。明文监听器没有可比较的 SNI / 证书，会绕过该检查。这能保护多租户 HTTPS 部署，
防止攻击者通过为租户 A 建立的 TLS 会话到达租户 B，同时与浏览器在合法通配符证书上的
连接合并保持兼容。

### 4.2 ALPN 与 `disable_http11`

握手完成后，Sōzu 检查协商得到的 ALPN 协议（`lib/src/https.rs:321-322, 339`），并
决定实例化哪一种 mux：

- ALPN `h2` → HTTP/2 mux。
- ALPN `http/1.1` → HTTP/1.1 路径。
- 未选择 ALPN → 默认 HTTP/1.1。

监听器级别的 `disable_http11`（`command/src/config.rs:393`）允许运维按监听器强制
仅 H2。ALPN 拒绝用两个不同的键计数，以便仪表盘能按原因拆分拒绝：

- `https.alpn.rejected.unsupported` —— 对端提供了 Sōzu 未实现的 ALPN
  （例如 `h3`）（`lib/src/https.rs:359`）。
- `https.alpn.rejected.http11_disabled` —— 对端想要 `http/1.1`，但监听器设置了
  `disable_http11 = true`（`lib/src/https.rs:342, 372`）。

`command/src/config.rs:253-262` 处的启动期校验器会捕获那个明显的运维错误：
将 `disable_http11 = true` 与仍然包含 `"http/1.1"` 的 `alpn_protocols` 配对。

### 4.3 握手遥测

成功的握手以直方图形式报告 `tls.handshake_ms`
（`lib/src/protocol/rustls.rs:78, 119, 193, 254, 261`）。失败按每个 rustls
错误变体以常量键标记（`tls.handshake.failed.alert_received`、`tls.handshake.failed.no_alpn`…），
因此即使有行为不端的客户端猛攻握手，statsd 的基数也能保持有界
（`lib/src/protocol/rustls.rs:328-345, 503`）。

## 5. PROXY 协议预检

当一个前端被配置为期望一个 HAProxy PROXY 协议头（通常是因为 Sōzu 位于一个
四层负载均衡器之后）时，会话会从一个小型 `ExpectProxyProtocol` 状态开始
（`lib/src/http.rs:141`、`lib/src/protocol/proxy_protocol/expect.rs:117`）。该状态从
前端套接字读取 v1 / v2 头，提取真实的客户端地址，然后将会话转换为下游协议
（HTTP/1.1、HTTP/2 或裸 TCP 中继）。

三个子状态机（`expect`、`relay`、`send`）的完整生命周期记录在
[`lib/src/protocol/proxy_protocol/LIFECYCLE.md`](../lib/src/protocol/proxy_protocol/LIFECYCLE.md)；
在改动 `lib/src/protocol/proxy_protocol/` 中的任何内容之前请先阅读它。

## 6. 按协议的会话生命周期

一旦会话经历了任何 TLS 和 PROXY 协议预检，控制权就转移给三个协议状态机之一，
由它们接管会话的其余部分。

### 6.1 HTTP/1.1（由 Kawa 支撑）

HTTP/1.1 路径是 Sōzu 的历史核心，现在由 [Kawa](https://github.com/CleverCloud/kawa)
HTTP 解析器支撑。从概念上讲，生命周期是：

1. 在 `lib/src/protocol/kawa_h1/mod.rs` 中，使用 Kawa 从前端缓冲区**解析请求**。
2. 通过 `cluster_id_from_request`（`lib/src/protocol/kawa_h1/mod.rs:1340`）
   **将请求路由**到一个集群。
3. 通过 `backend_from_request`（`lib/src/protocol/kawa_h1/mod.rs:1397`）
   **挑选后端**，并通过 `connect_to_backend`（`lib/src/protocol/kawa_h1/mod.rs:1462`）
   **连接到它**。一个先前打开的 keep-alive 套接字可以在存活探测后复用
   （`check_backend_connection`，`lib/src/protocol/kawa_h1/mod.rs:1288`）。
4. 通过前端/后端 Kawa 缓冲区对**双向转发字节**，按需注册可写兴趣
   （`lib/src/protocol/kawa_h1/mod.rs:1545, 1566`）。
5. 响应完成时**关闭或重置**。如果请求和响应都指示 keep-alive，会话会被“重置”
   而非销毁，并在同一个前端套接字上等待下一个请求；后端套接字可能根据集群决策被
   释放或保留（`close_backend`，`lib/src/protocol/kawa_h1/mod.rs:1198`）。

完整的状态图（包括解析器背压规则、H1 → WebSocket 升级路径、H1 → H2 mux 转换，
以及 keep-alive 与 close 的归因）位于
[`lib/src/protocol/kawa_h1/LIFECYCLE.md`](../lib/src/protocol/kawa_h1/LIFECYCLE.md)。

### 6.2 HTTP/2（mux）

H2 复用器是 Sōzu 中最大的一块，位于 `lib/src/protocol/mux/` 下。高层数据模型：

- 每个 TCP 连接一个 `ConnectionH2<Front>`（`lib/src/protocol/mux/h2.rs`）拥有线状态：
  HPACK 编码器和解码器、连接级流窗口、GOAWAY 状态，以及每连接的 `H2FloodDetector`。
- 一个 `Context<L>`（`lib/src/protocol/mux/mod.rs`）拥有 `Vec<Stream>`，它支撑每个
  独立 H2 流的请求/响应缓冲区。两个对象通过一个 `GlobalStreamId = usize` 引用这些流。
- 每个 `Stream` 携带一个 `StreamState`（`lib/src/protocol/mux/stream.rs:35`），遍历
  生命周期 `Idle` → `Link` → `Linked(Token)` → `Unlinked` → `Recycle`。
  只有 `Idle` 和 `Recycle` 是“空闲”槽位；中间状态将流固定到一个后端连接上。

H2 mux 拥有几个容易被意外破坏的不变量：

- **流控。** 每流和每连接的窗口必须用 `WINDOW_UPDATE` 帧补足，否则对端会停滞。
- **HPACK 有状态编码。** 解码器和解码器状态必须与线上保持同步 —— 悄悄丢弃一个
  大小更新或跳过一次动态表驱逐，会让对端在整个连接剩余时间内失去同步。
- **RFC 9218 优先级。** 优先级从 `priority` 请求头和 `PRIORITY_UPDATE` 帧中提取
  （`lib/src/protocol/mux/pkawa.rs:498-520`），并喂给可写调度器，以便一个优先级 7
  的慢速下载无法饿死一个优先级 0 的交互式请求。
- **GOAWAY 与优雅排干。** 在 GOAWAY(NO_ERROR) 之后，连接进入排干模式
  （`lib/src/protocol/mux/h2.rs:1223-1226`）；必须拒绝新的对端流（RFC 9113 §6.8），
  并且已有流必须完成。优雅关闭截止时间由监听器配置驱动
  （`lib/src/https.rs:448-449, 458, 977-978`）。
- **洪水缓解。** `H2FloodDetector` 内联位于读取路径中，支撑已公开的针对
  CVE-2023-44487（Rapid Reset）、CVE-2024-27316（CONTINUATION flood）和
  CVE-2025-8671（MadeYouReset）的缓解措施，外加 PING / SETTINGS / WINDOW_UPDATE /
  glitch 洪水阈值。每一次触发都发出一个独立的 `h2.flood.violation.<kind>` 计数器
  （种类包括 `rst_stream_{lifetime,pre_response_lifetime,emitted_lifetime,window}`、
  `ping_{window,lifetime}`、`settings_{window,lifetime}`、`empty_data_window`、
  `continuation_per_block`、`window_update_stream0_window`、`header_size_per_block`、
  `glitch_window`；参见 `lib/src/protocol/mux/h2.rs:779-930, 3656`）。GOAWAY 和
  RST_STREAM 的发送/接收按错误码归因，通过 `h2.{goaway,rst_stream}.{sent,received}.<code>`
  （`lib/src/protocol/mux/h2.rs:3706`）。
- **边沿触发写入。** mux 是 §2.2 所述“字节已排队、无可写唤醒”卡顿最常见的肇事者；
  `arm_writable` 调用散布在 `mux::answers`、`mux::h1` 和 `mux::h2` 中，若没有等效的
  踢动就不得移除。

每个流的完整状态图和连接级处理程序目录位于
[`lib/src/protocol/mux/LIFECYCLE.md`](../lib/src/protocol/mux/LIFECYCLE.md)。

### 6.3 WebSocket 与 TCP 透传（pipe）

一旦一个 HTTP/1.1 会话成功协商了 WebSocket 升级（或者一旦一个 `TcpProxy` 接受了一个
纯字节流透传的连接），会话就提升为 `Pipe` 状态（`lib/src/protocol/pipe.rs:82, 118`）。
pipe 不持有任何协议解析器；它在前端和后端套接字之间穿梭字节，并依赖标准的
就绪泵送纪律。WebSocket 元数据（`WebSocketContext`，`lib/src/protocol/pipe.rs:71`）
在升级时从 H1 mux 继承，以便日志和指标保持其上下文。

## 7. 连接到后端集群

路由发生在请求头解析之后。路由器问“这个 `(host, path, method)` 匹配哪个集群？”，
并返回一个 `cluster_id`。由此负载均衡器挑选一个后端。

可用的算法位于 `lib/src/load_balancing.rs`：

- `RoundRobin`（`lib/src/load_balancing.rs:20-24`）
- `Random`
- `LeastLoaded`（`lib/src/load_balancing.rs:86`）
- `PowerOfTwo`（`lib/src/load_balancing.rs:127`）

粘性会话实现为一个可选的基于 cookie 的覆盖：当请求携带一个命名了仍然健康的后端的
粘性 cookie 时，负载均衡器跳过其正常选择，将请求固定到该后端。

后端健康在 `lib/src/backends.rs` 中跟踪。一个未能连上其第一个所选后端的请求会重试
最多三次（在同一集群内），之后 Sōzu 才提供一个默认的 503；如果根本没有集群匹配
该请求，Sōzu 提供一个默认的 404。

## 8. 双向转发字节

后端连接建立后，会话进入其稳态。H1 路径持有 Kawa 缓冲区对 `front`/`back`；H2 路径
持有由 mux 调度器驱动的每流对；pipe 路径逐字透传字节。在所有三种情况下，循环形态
都是相同的：

1. mio 在任一套接字上报告一个可读边沿。
2. 会话读取内核缓冲区所能容纳的尽可能多的数据。
3. 这些字节被处理（解析、调度或复制）并排入对端套接字。
4. 如果会话刚从可读代码路径产生了新输出，它会武装可写兴趣（§2.2）。
5. mio 在目标套接字上报告一个可写边沿。
6. 会话排空内核所能接受的尽可能多的数据并循环。

两个反复咬人的陷阱：

- **在从可读处理程序排入字节后，忘记调用 `arm_writable` / `signal_pending_write`。**
  会话看起来活着，但永远不会冲刷最后一个帧。
- **非对称的标量写入 vs 向量写入路径。** `socket_write` 和 `socket_write_vectored`
  必须在部分写入下以相同方式重试；此处过去的差异导致了 `feat/h2-mux` 上数兆字节
  响应截断的 bug。

每集群流量通过 `requests`、`bytes_in`、`bytes_out` 和 `backend_response_time`
观测（`lib/src/metrics/mod.rs:446-453`）。

## 9. 关闭会话

一个会话在以下情况结束：

- H1 响应完成且任一方关闭了连接，或者
- H2 流池在 GOAWAY 之后排空且连接被销毁，或者
- 协议错误或洪水违规强制硬关闭，或者
- 僵尸检查器判定该会话已卡死。

对于 TLS 前端，关闭路径在前端套接字上使用**只写关闭**
（`lib/src/https.rs:661-668`，在 `lib/src/http.rs:448-452` 中有对应实现）：

```rust
front_socket.shutdown(Shutdown::Write)
```

`Shutdown::Both` 在 TLS 前端上是被禁止的。它包含 `SHUT_RD`，会丢弃内核接收缓冲区中
任何未读的数据（客户端的 GOAWAY、ACK，或尾随的 TLS 记录）。在 Linux 上，随后的
`close()` 会发送 TCP RST 而非 FIN，销毁发送缓冲区中仍存在的任何数据 —— 包括排干
循环刚刚冲刷的 TLS 记录。`Shutdown::Write` 仅在发送缓冲区排空后才发送 FIN，从而保留
响应。明文 TCP 路径（`lib/src/tcp.rs:867-870, 1011-1016`）保留 `Shutdown::Both`，
因为它没有需要截断的加密发送缓冲区；注释标记了未来在 TCP 上做 TLS 升级时需要切换模式。

关闭之后，`state.close(...)` 关闭后端、冲刷任何 close-notify，并释放缓冲区；代理在
前端和后端两个 token 下从 slab 中移除会话，mio 注销套接字，slab 条目返回空闲列表。
半关闭的 H2 流以相同方式展开 —— `mux::mod` 和 `mux::router` 中的每流清理会递减
`backend.pool.size`（`lib/src/protocol/mux/mod.rs:1641-1650`、
`lib/src/protocol/mux/router.rs:388-394, 428`）。

## 10. 热重配置与升级

以上所有内容描述的都是一个转发实时流量的 worker。该数据路径与**控制平面**解耦：
主进程和 worker 通过一个 unix 命令通道通信，主进程校验传入的请求，变更通过
SCM_RIGHTS 传递的对分发给 worker。热重配置（添加一个前端、移除一个后端、替换证书）
流经该通道，不会触及实时会话。热**升级**路径还会通过 `execve` 交接监听器文件描述符
来重新 exec 主进程（`bin/src/upgrade.rs`），因此新二进制接管相同的监听套接字，而不会
丢弃已接受的连接。

详细的主/worker 生命周期、SoftStop / HardStop 动词（`lib/src/server.rs:788, 799`）
以及审计日志信封位于 [`bin/src/command/LIFECYCLE.md`](../bin/src/command/LIFECYCLE.md)。

**范围澄清。** 数据平面会话绝不发出审计日志行。审计日志绑定于通过 unix 命令套接字
进行的控制平面变更（前端、后端、证书、监听器配置）。要回答“这个 502 从哪来”，
请阅读每集群指标和协议日志宏 —— 而不是审计日志。

## 11. 在代码中该看哪里

当你想阅读源码时，把这张图作为入口。

| 关注点 | 文件 |
|---|---|
| mio 循环、slab、接受队列、max_connections、软/硬停止 | `lib/src/server.rs` |
| `SO_REUSEPORT`、套接字辅助函数 | `lib/src/socket.rs` |
| `HttpProxy`、H1 监听器、升级转换 | `lib/src/http.rs` |
| `HttpsProxy`、TLS 监听器、ALPN 分派、只写关闭 | `lib/src/https.rs`, `lib/src/tls.rs` |
| `TcpProxy`（明文字节中继） | `lib/src/tcp.rs` |
| TLS 握手（rustls 胶水）、握手指标 | `lib/src/protocol/rustls.rs` |
| HTTP/1.1 会话（解析器、编辑器、路由器、后端连接、keep-alive） | `lib/src/protocol/kawa_h1/` |
| HTTP/2 mux（连接、帧、HPACK、优先级、调度器、洪水检测器） | `lib/src/protocol/mux/` |
| 升级后的 WebSocket / TCP 透传 | `lib/src/protocol/pipe.rs` |
| PROXY 协议预检（expect / relay / send） | `lib/src/protocol/proxy_protocol/` |
| 路由与负载均衡 | `lib/src/router/`、`lib/src/load_balancing.rs`、`lib/src/backends.rs` |
| 指标发射 | `lib/src/metrics/mod.rs` |
| 主/worker 监管、命令套接字、热升级 | `bin/src/command/`、`bin/src/upgrade.rs` |
| 配置旋钮（buffer_size、ALPN、H2 超时、洪水阈值、粘性会话） | `command/src/config.rs` |
| 每协议日志宏（`MUX-H2`、`RUSTLS`、`KAWA-H1`、`PIPE`、`TCP`、`HTTPS`、…） | 各模块的 `log_context!` 系列 |

## 11.5 指标沿路径在何处触发

完整分类：`doc/configure.md` + `lib/src/metrics/`。从仪表盘读取一个会话生命所需的最小集合：

- `tls.handshake_ms`、`tls.handshake.failed.<reason>` —— 握手延迟 + 按 rustls 变体的
  失败归因（`lib/src/protocol/rustls.rs:193, 254, 261, 328-345`）。
- `https.alpn.rejected.{unsupported,http11_disabled}` —— ALPN 拒绝原因
  （`lib/src/https.rs:342, 359, 372`）。
- `client.connections`、`client.connections_max`、`client.connections_percent` —— 由
  slab 支撑的生命周期计量（`client.connections` 在每次 `SessionManager::incr/decr`
  时采样；`_max` 和 `_percent` 在与 `slab.*` 和 `buffer.*` 一起的运行循环中采样）。
- `accept_queue.backpressure`、`accept_queue.saturated_seconds` —— 二进制背压 +
  时间积分的饱和（`lib/src/server.rs:196, 207, 682-699`）。
- `backend.pool.size` —— 镜像开放后端连接的长生命周期计量
  （`lib/src/protocol/mux/mod.rs:1650`、`lib/src/protocol/mux/router.rs:394, 428`、
  `lib/src/protocol/mux/connection.rs:379`）。
- `requests`、`bytes_in`、`bytes_out`、`backend_response_time` —— 每集群 + 每后端
  计数器与计时（`lib/src/metrics/mod.rs:446-453`）。
- `h2.flood.violation.<kind>` —— H2 洪水检测器触发
  （`lib/src/protocol/mux/h2.rs:779-930`）。
- `h2.{goaway,rst_stream}.{sent,received}.<code>` —— H2 错误归因
  （`lib/src/protocol/mux/h2.rs:3706`）。
- `epoll_time` —— `Poll::poll` 的挂钟时间，有助于判断 worker 饱和度
  （`lib/src/server.rs:594`）。

## 12. 已移除与迁移的 API

本文档的早期修订（以及它们嵌入的 `e4e7488…` 永久链接）引用了两个在 `feat/h2-mux`
上已不再存在的模块：

- `lib/src/https_openssl.rs` —— 由 OpenSSL 支撑的 HTTPS 路径。Sōzu 多个版本以来
  已是纯 rustls；规范的替代是 `lib/src/https.rs`（代理 + 监听器）和
  `lib/src/protocol/rustls.rs`（每会话握手状态机）。
- `lib/src/protocol/http/mod.rs` —— 前 Kawa 的 HTTP/1.1 状态机；规范的替代是
  `lib/src/protocol/kawa_h1/`（及其姊妹篇
  [`LIFECYCLE.md`](../lib/src/protocol/kawa_h1/LIFECYCLE.md)）。

在 `doc/` 的其他地方若发现对这两个路径的陈旧引用，那是一个缺陷 —— 请对照当前源码
更新它，而非把过时的名称复制进新文档。
