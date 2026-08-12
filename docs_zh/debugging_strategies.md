# 如何调试 sozu

Sozu 提供日志和指标，可以检测大多数生产问题。

## 收集信息

### 通过 sozu 命令行转储状态

在生产系统中收集有关配置状态的信息非常有用。
以下是一些可用于获取当前状态快照的命令：

```bash
sozu -c /etc/config.toml status"
sozu -c /etc/config.toml metrics get"
sozu -c /etc/config.toml clusters list"
sozu -c /etc/config.toml state save -f "sozu-state-$(date -Iseconds).txt"
```

### 日志记录

有三个与日志记录相关的配置选项：

* `log_level`: 设置日志记录详细程度
* `log_target`: 日志发送到哪里。它可以具有以下格式：
  * `stdout`
  * `udp://127.0.0.1:9876`
  * `tcp://127.0.0.1:9876`
  * `unix:///var/sozu/logs`
  * `file:///var/logs/sozu.log`
* `access_logs_target`: 如果激活，则将访问日志发送到单独的目的地

`log_level` 遵循 [env_logger 的级别指令](https://docs.rs/env_logger/0.5.13/env_logger/)。
此外，`RUST_LOG` 环境变量可用于覆盖日志级别。

如果 sozu 是在发布模式下构建的，则 `DEBUG` 和 `TRACE` 日志级别不会被编译进去，
除非您设置了编译功能 `logs-debug` 和 `logs-trace`。

### 指标

sozu 运行时会生成各种指标。可以通过两种方式访问它们：

* 通过 `sozu metrics get`，它将显示主进程和工作进程的指标。每次调用之间都会刷新计数器
* 通过 UDP，遵循 statsd 协议（可选地支持 InfluxDB 的标签）

以下是在配置文件中使用 statsd 设置指标的方法：

```toml
[metrics]
address = "127.0.0.1:8125"
# 使用 InfluxDB 的 statsd 协议风格添加标签（默认值：false）
tagged_metrics = true
# 指标键前缀（默认值：sozu）
# prefix = "sozu"
```

## 要关注的图表和指标

（假设我们将 `sozu` 设置为指标前缀）

### 跟踪有效流量

#### 访问日志

访问日志具有以下格式：

```txt
2018-09-21T14:01:51Z 821136800672570 71013 WRK-00 INFO  450b071a-53b8-4fd7-b2f2-1213f03ef032 MyCluster      127.0.0.1:52323 -> 127.0.0.1:1027       241ms 855μs 560 33084   200 OK lolcatho.st:8080 GET /
```

从左到右：

* ISO8601 格式的日期，UTC 时区
* 单调时钟（以防某些消息以错误的顺序出现）
* PID
* 工作进程名称（主进程为“MAIN”）
* 日志级别
* 请求 ID（UUID，为每个请求随机生成，如果在 keep-alive 中执行多个请求，则在同一连接上更改）
* 集群 ID
* 客户端的源 IP 和端口
* 后端服务器的目标 IP 和端口
* 响应时间（从客户端收到第一个字节到发送给客户端的最后一个字节）
* 服务时间（sozu 处理会话所花费的时间）
* 上传的字节数
* 下载的字节数

#### HTTP 状态指标

以下指标跟踪已正确发送到后端服务器的请求：

* `sozu.http.status.1xx`：计算状态为 100 到 199 的请求
* `sozu.http.status.2xx`：计算状态为 200 到 299 的请求
* `sozu.http.status.3xx`：计算状态为 300 到 399 的请求
* `sozu.http.status.4xx`：计算状态为 400 到 499 的请求
* `sozu.http.status.5xx`：计算状态为 500 到 599 的请求
* `sozu.http.status.<code>`：一份十八个状态码短列表的逐码计数器
  （`200/201/204`、`301/302/304`、`400/401/403/404/408/413/429`、
  `500/502/503/504/507`）；完整列表请参阅 `doc/configure.md`。列表之外的状态码
  只计入其所属区间，从而使指标键空间保持有界。
* `sozu.http.requests`：每个请求递增（上述计数器的总和）

#### 传输的数据

有全局的 `sozu.bytes_in` 和 `sozu.bytes_out` 指标，用于计算 sozu 的前端流量。
这些指标也可以具有后端 ID 和集群 ID。然后它们将指示
从后端服务器的角度来看的输入和输出字节。

#### 响应时间

?

#### 协议

客户端会话可以处于其网络协议的各种状态。例如，一个连接
可以从“期望代理协议”（假设前面有一个 TCP 代理）到 TLS 握手，
到 HTTPS，再到 WSS（基于 TLS 的 websocket）。

您可以跟踪以下仪表，以指示当前的协议使用情况：

* `sozu.protocol.proxy.expect`
* `sozu.protocol.proxy.send`
* `sozu.protocol.proxy.relay`
* `sozu.protocol.tcp`
* `sozu.protocol.tls.handshake`
* `sozu.protocol.http`
* `sozu.protocol.https`
* `sozu.protocol.ws`
* `sozu.protocol.wss`

### 跟踪失败的请求

Sozu 有一种以最少的资源使用来响应无效流量的方法，即发送预定义的答案。
它对无效流量（不符合标准）和路由问题（未知主机和/或路径，
无响应的后端服务器）执行此操作。

`sozu.http.errors` 计数器是失败请求的总和。它包含以下内容：

* `sozu.http.frontend_parse_errors`: sozu 收到了一些无效的流量
* `sozu.http.400.errors`: 无法解析主机名
* `sozu.http.404.errors`: 未知主机名和/或路径
* `sozu.http.413.errors`: 请求过大
* `sozu.http.503.errors`: 无法连接到后端服务器，或者相应集群没有可用的后端服务器

更进一步，后端连接问题由以下指标跟踪：

* `sozu.backend.connections.error`: 无法连接到后端服务器
* `sozu.backend.down`: 重试策略已触发并将后端服务器标记为关闭

在请求发回 503 错误后，`sozu.http.503.errors` 指标会递增，并且在断路器触发后（我们等待 3 次到后端服务器的失败连接），会发送 503 错误。

后端连接错误将导致以下日志消息：

```txt
2018-09-21T14:36:08Z 823194694977734 71501 WRK-00 ERROR 839f592b-a194-4c3b-848b-8ef024129969    MyCluster    error connecting to backend, trying again
```

断路器触发会将此写入日志：

```txt
2018-09-21T14:36:57Z 823243245414405 71524 WRK-00 ERROR 7029d66e-57a8-406e-ae61-e4bf9ff7b6b8    MyCluster    max connection attempt reached
```

将后端服务器标记为关闭的重试策略将写入以下日志消息：

```txt
2018-09-21T14:37:31Z 823277868708804 71524 WRK-00 ERROR no more available backends for cluster MyCluster
```

### 可伸缩性

Sozu 精细地处理其资源使用，并对请求数量
或内存使用设置硬性限制。

要跟踪连接，请遵循以下仪表：

* `sozu.client.connections` 用于前端连接
* `sozu.backend.connections` 用于后端连接
* `sozu.http.active_requests` 用于当前活动连接（等待
下一个请求的 keep-alive 连接被标记为不活动）

客户端连接应始终高于后端连接，而后端连接应高于
活动请求（非活动会话可以保持后端连接）。

这些指标与资源使用密切相关，资源使用由以下各项跟踪：

* `sozu.slab.entries`: slab 分配器中使用的插槽数。通常，每个侦听器套接字有一个插槽，
一个用于连接到主进程，一个用于指标套接字，然后每个前端连接一个，
每个后端连接一个。因此，连接数应始终接近（但低于）slab 计数。
* `sozu.buffer.in_use`（由 `sozu.buffer.number` 重命名）：缓冲池中使用的缓冲区数。非活动会话和我们发送
默认答案（400、404、413、503 HTTP 错误）的请求不使用缓冲区。活动 HTTP 会话使用一个缓冲区（流水线模式除外），
WebSocket 会话使用两个缓冲区。因此，缓冲区数应始终低于
slab 计数，并且低于连接数。
* `sozu.zombies`: sozu 集成了一个僵尸会话检查器。如果某个会话一段时间内没有任何操作，
则事件循环或协议实现中可能存在错误，因此会记录其内部状态。对于每个被删除的僵尸会话，此计数器都会递增。

新连接被放入队列中，并等待直到创建会话（如果我们有可用资源），
或直到配置的超时已过。以下指标观察接受队列的使用情况：

* `sozu.accept_queue.connections`: 接受队列中的套接字数
* `sozu.accept_queue.timeout`: 每当套接字在队列中停留时间过长并被关闭时递增
* `sozu.accept_queue.wait_time`: 每当创建会话时，此指标记录套接字在接受队列中必须等待多长时间

### TLS 特定信息

TLS 版本计数器：

* `sozu.tls.version.SSLv2`
* `sozu.tls.version.SSLv3`
* `sozu.tls.version.TLSv1_0`
* `sozu.tls.version.TLSv1_1`
* `sozu.tls.version.TLSv1_2`
* `sozu.tls.version.TLSv1_3`
* `sozu.tls.version.Unknown`

Rustls 特定，协商的密码套件：

* `sozu.tls.cipher.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256`
* `sozu.tls.cipher.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256`
* `sozu.tls.cipher.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`
* `sozu.tls.cipher.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`
* `sozu.tls.cipher.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`
* `sozu.tls.cipher.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`
* `sozu.tls.cipher.TLS13_CHACHA20_POLY1305_SHA256`
* `sozu.tls.cipher.TLS13_AES_256_GCM_SHA384`
* `sozu.tls.cipher.TLS13_AES_128_GCM_SHA256`
* `sozu.tls.cipher.Unsupported`

## 典型错误场景

### 路由问题

正常流量（`sozu.http.requests`）下降，而 404（`sozu.http.404.errors`）和
503（`sozu.http.503.errors`）增加，这意味着 sozu 的配置可能无效。
使用以下命令检查配置状态：

```bash
sozu -c /etc/config.toml clusters list
```

并且，对于特定集群 ID 的完整配置：

```bash
sozu -c /etc/config.toml clusters list -i cluster_id
```

### 后端服务器不可用

`sozu.http.503.errors` 增加，大量的 `sozu.backend.connections.error` 和
`sozu.backend.down` 记录：后端服务器已关闭。
检查日志中是否有 `error connecting to backend, trying again` 和 `no more available backends for cluster <cluster_id>`
以找出受影响的集群

### 僵尸

如果 `sozu.zombies` 指标触发，这意味着存在事件循环或协议实现
错误。日志应包含被终止的会话的内部状态。请复制这些
日志并向 sozu 提交问题。

它通常伴随着 `sozu.slab.entries` 增加，而连接数或活动请求数保持
不变。当僵尸检查器激活时，slab 计数将下降。

### 无效的会话关闭

如果 slab 计数和活动请求保持不变，但 `sozu.client.connections` 和/或 `sozu.backend.connections`
正在增加，这意味着会话没有被 sozu 正确关闭，请为此提交一个问题。
（如果 slab 计数保持不变，套接字仍应正确关闭）

### 接受队列正在填满

如果 `sozu.accept_queue.connections` 正在增加，这意味着接受队列正在填满，因为 sozu 处于
高负载下（在健康负载下，此队列几乎总是空的）。`sozu.accept_queue.wait_time` 也应该增加。
如果 `sozu.accept_queue.timeout` 大于零，sozu 无法足够快地接受会话并且
正在拒绝流量。

## 开发期间

在 config.toml 文件中：

- 如果错误只影响其中一个协议（HTTP、HTTPS 或 TCP），请停用其他协议
- 将 `worker_count` 设置为 1 以避免日志中出现重复
- 调试紧急情况：
  - 使用 `RUST_BACKTRACE=1` 启动 sozu
  - 将 `worker_automatic_restart` 设置为 false（以便 sozu 可以立即停止）

### 跟踪指标

[grad metrics tool](https://github.com/geal/grad) 的开发旨在轻松聚合 statsd
指标并显示它们。
