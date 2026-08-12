# 速率限制设计

**状态：** 已在 2.0.0 中交付 —— 关闭 [#890](https://github.com/sozu-proxy/sozu/issues/890)
（通用速率限制）和 [#1057](https://github.com/sozu-proxy/sozu/issues/1057)
（每源 IP DoS 防护）。

本文档描述在 PR [#1193](https://github.com/sozu-proxy/sozu/pull/1193)
中交付的速率限制机制及选择形状的合理性。早期设计草案提出了
两层机制（L7 令牌桶请求速率 + L4 每 IP TCP 上限）；团队
收敛于单一机制 —— **每 (集群, 源 IP) 并发连接上限 + 429 响应** ——
以更小配置 + 代码表面覆盖两个滥用向量。
令牌桶请求速率选项在 §6 中记录为延后未来工作。

## 1. 问题陈述

两个不同滥用向量需要缓解：

1. **每租户嘈杂邻居 ([#890](https://github.com/sozu-proxy/sozu/issues/890))。**
   多租户监听器上的单个租户可以通过连接突袭来饱和集群，
   饿死同一监听器上的其他租户。
2. **每源 IP DoS ([#1057](https://github.com/sozu-proxy/sozu/issues/1057))。**
   来自单一源 IP 的大量连接尝试早在
   `max_connections` 触发前就饱和了接受队列。

交付的机制同时解决**两个**向量：单个计数器跟踪
`(cluster_id, source_ip) → 并发连接数`，
操作员设置全局默认（集群隔离，解决 #890）和可选每集群覆盖
（每租户调优，解决 #1057 的嘈杂邻居模式）。

## 2. 非目标

- 不是上游 WAF（Cloudflare、ModSecurity）的替代品。
  Sōzu 的每 IP 上限是纵深防御底线，而非策略引擎。
- 无跨 worker / 跨进程状态。每个 worker 独立执行自己的计数器。
  4 worker 部署与 cap=`100` 实际上允许每 (集群, IP) 400 并发连接。
  记录的权衡；跨 worker 同步延后（§6）。
- 不是请求速率限制。上限计算**并发连接**，而非每秒请求。
  令牌桶请求速率限制是独立功能（§6）。
- 不是路径/方法作用域限制。路径/方法限制属于路由器中间件，
  而非监听器。
- 不触碰 H2 洪水检测器
  （`H2FloodDetector` in `lib/src/protocol/mux/h2.rs`）。
  协议层滥用保持独立。

## 3. 机制 —— 每 (集群, 源 IP) 并发连接上限

### 3.1 数据模型

两个配置旋钮，在全局 → 每集群间叠加：

```protobuf
// command/src/command.proto
message Config {
  // 全局默认。0 = 禁用（无上限）。
  optional uint64 max_connections_per_ip = 23 [default = 0];
}

message Cluster {
  // 每集群覆盖。None = 继承全局；Some(0) = 此集群显式无限；
  // Some(n) = 覆盖。
  optional uint64 max_connections_per_ip = 13;
  // 429 上发出的可选 Retry-After 提示（秒）。0 / 未设置
  // 省略标头 —— `Retry-After: 0` 邀请立即重试，
  // 违背上限。
  optional uint32 retry_after            = 14;
}
```

集群级覆盖优先；`None` 回退到全局默认。
`Some(0)` 是显式"无限"哨兵 —— 操作员在特定集群上禁用
上限同时保持其他的全局默认。

### 3.2 计数器纪律

`SessionManager`（在 `lib/src/` 中）保持每 token 的
`(cluster_id, source_ip)` 对集合。在会话接受 + 集群解析后：

1. 解析源 IP：存在 PROXY-protocol 头时从其中解析
   （`ExpectHeader` 和 `RelayHeader` 模式都在 pipe
   阶段保留解析的源），否则 `peer_addr`。
2. 查找 `(cluster_id, source_ip)` 的 `count`。
3. 与
   `cluster.max_connections_per_ip.unwrap_or(global)` 比较。
4. 如果 `count >= cap`，拒绝；否则递增并继续。
5. 会话关闭时递减。空条目被丢弃。

计数器位于 SessionManager 而非全局 hashmap，
是因为 H2 多路复用：H2 会话在一个前端连接上多路复用
许多流，因此每 token 集合保持来自同一源的多个流
到同一集群消耗**单个**连接槽位。
这匹配操作员设置
`max_connections_per_ip = 1` 时期望的每连接语义。

### 3.3 执行点

上限在**集群解析后、后端连接前**检查，
因此 401 / 421 / 重定向 / 答案模板前端从不被门控。
两个执行点：

- **统一 H1+H2 mux**
  （`lib/src/protocol/mux/router.rs`）—— 触及上限的
  HTTP 和 HTTPS 客户端收到
  `429 Too Many Requests` 带可选 `Retry-After` 头。
- **原始 TCP**（`lib/src/tcp.rs`）—— TCP 客户端在
  任何后端连接前看到优雅 FIN —— 无 SO_LINGER 技巧，
  无 RST。

### 3.4 拒绝行为（HTTP / HTTPS）

- 状态：`429 Too Many Requests`（RFC 6585）。
- 头：如果 `Some(n > 0)` 则
  `Retry-After: <cluster.retry_after>`；否则省略。
- 身体：统一模板引擎中的 `Answer429` 变体，
  与现有 `Answer4xx` / `Answer5xx` 并列。
  操作员可通过
  `CustomHttpAnswers.answer_429`（proto tag 12）
  每集群覆盖。
- 计数器
  `connections.rejected_per_cluster_ip`（集群标签）
  每次拒绝递增。

`Answer429` 模板支持 `%RETRY_AFTER` 替换。
监听器默认发出单行响应带 `Connection: close`；
自定义模板可选择通过省略 `Connection: close`
头启用 keep-alive。

### 3.5 拒绝行为（TCP）

- 优雅 FIN —— 无 `SO_LINGER` 重置技巧，无 `TCP RST`。
  客户端在任何后端连接尝试前看到正常关闭。
- 相同计数器
  `connections.rejected_per_cluster_ip` 递增。

### 3.6 源 IP 选择

| PROXY-protocol 模式 | 使用的源 IP                                       |
| ------------------- | ---------------------------------------------------- |
| `ExpectHeader`      | 从 PP-v2 解析                                       |
| `RelayHeader`       | 从 PP-v2 解析（在 pipe 阶段保留）                   |
| 无 PROXY-protocol   | `peer_addr`（TCP 级）                               |

ExpectHeader / RelayHeader 路径在本 PR 中更新为
地址感知 —— 两种模式现在将解析的源 IP 携带到
SessionManager。没有此，sōzu 在另一个启用了
PP-v2 的 L4 LB 后运行时将按 LB IP 而非按真实客户端
速率限制。

### 3.7 配置表面

```toml
# 全局默认 —— 适用于每个集群除非集群覆盖。
# `0`（默认）禁用上限。
max_connections_per_ip = 100

[clusters."api-strict"]
# 每集群覆盖（proto tag 13）。`Some(0)` = 显式无限；
# 省略则继承全局默认。
max_connections_per_ip = 20
# 发出的 429 上 Retry-After 提示（proto tag 14）。`0` 省略。
retry_after = 5

[clusters."api-internal"]
# 内部集群 —— 选择不受全局上限约束。
max_connections_per_ip = 0
```

### 3.8 CLI / 运行时 API

`sozu connection-limit` 上的三个动词：

| 动词   | Proto 请求                    | Proto 响应                  |
| -------- | -------------------------------- | ------------------------------- |
| `set`    | `SetMaxConnectionsPerIp` (50)    | —                               |
| `show`   | `QueryMaxConnectionsPerIp` (51)  | `MaxConnectionsPerIpLimit` (14) |
| `remove` | `SetMaxConnectionsPerIp(0)` (50) | —                               |

setter 是**非粘性的** —— 它补丁 worker 的运行时值但不写入
TOML。操作员必须在配置中镜像变更以保持重启后持久。

## 4. 指标

| 键                                    | 类型    | 含义                                                   |
| ------------------------------------- | ------- | --------------------------------------------------------- |
| `connections.rejected_per_cluster_ip` | counter | 每集群拒绝计数（集群标签）                               |
| `client.connect.per_source.bucket_*`  | counter | 每 IP 接受队列准入直方图（已交付）                       |

单个计数器
`connections.rejected_per_cluster_ip`（带
`cluster_id` 标签）是耐用信号。想要每 IP
归因的操作员应将其与现有
`client.connect.per_source.bucket_*` 系列配对。

## 5. 测试覆盖

`e2e/src/tests/cluster_ip_limit_tests.rs` 中的端到端测试：

- **HTTP/1.1 全局上限发出 429**：全局
  `max_connections_per_ip = 1` 拒绝来自同一源 IP 的
  第二个并发连接带 `429` + `Retry-After`。
  确认答案引擎路径、`Answer429` 模板变体、
  `connections.rejected_per_cluster_ip` 计数器和
  SessionManager 侧核算（关闭时
  `untrack_all_cluster_ip` 释放槽位供后续请求）。
- **HTTP/1.1 + 每集群覆盖**：无限集群
  （`Some(0)`）与有上限集群（`Some(1)`）共存。
  对无限集群的两个并发连接 MUST 都成功；
  相同模式对有上限集群 MUST 429。
- **HTTP/1.1 + `Retry-After: 0` 语义**：当解析的
  `retry_after` 为 `0` 时，响应 MUST 省略头。
- **TCP**：`max_connections_per_ip = 1` 的 TCP
  监听器接受第一个连接但优雅关闭第二个
  （FIN，无 RST）不拨号后端。

H2 前端单元格不在此测试文件中 ——
它们在 `e2e/src/tests/protocol_pair_matrix.rs` 下跟踪
为延后矩阵回填（见 `e2e/COVERAGE.md`）。
维持 TLS + HTTP/2 连接的同时第二个连接竞争
所需的连接钉扎助手在当前 Hyper 客户端池里不存在。

## 6. 延后未来工作

### 6.1 令牌桶请求速率限制

请求速率限制（如"每租户每秒 100 请求"带
令牌桶和补充速率）**不在** 2.0.0 中。连接上限
覆盖主导滥用案例（一个客户端对单一集群打开
许多连接）而无需为单个请求单独计数器。
如果请求速率限制变得必要，自然形状是：

- 叠加在连接上限**之上**：通过已接受连接的
  请求喂养每 (集群, tenant_key) 桶。
- 租户键解析：可配置顺序 —— peer IP、
  解析的 `X-Forwarded-For`
  （仅在监听器上设置
  `trust_forwarded_for = true` 时）或
  操作员配置的稳定头
  （`X-Tenant-Id`）。
- 拒绝行为：相同 `429` + `Retry-After`，无单独代码路径 ——
  答案引擎已处理。
- 存储：`HashMap<(rule_name, tenant_key), TokenBucket>`
  带 LRU 淘汰在每 worker ~10k 条目，补充速率由
  `Instant::now()` 驱动（sōzu 其他地方已使用）。

权衡：配置两个互补机制（连接
- 请求）比一个更费力给操作员。
覆盖 80% 滥用模式的单一机制先交付；
第二个机制当操作员遇到连接上限未覆盖的真实世界案例时交付。

### 6.2 跨 worker / 跨进程同步

当前每个 worker 计数器独立 ——
`max_connections_per_ip = 100` 的 4 worker 部署
允许每 (集群, IP) 400 连接。想要精确全局上限的操作员需要：

- 或共享状态后端（Redis、memcached）worker 每次接受时咨询 ——
  高延迟成本、单点故障。
- 或 master 通过命令 socket 广播每 IP 计数 ——
  每次接受的单消息乘以 N workers ——
  也是非平凡的热路径开销。

记录为已知限制；如果真实世界部署遇到它，
选择的机制（Redis vs 命令 socket 广播）
成为单独的设计传递。

### 6.3 自适应配额

基于后端健康自动缩放
`max_connections_per_ip`（如"当后端
`503` 速率超过 1% 时减半上限"）超出范围。
操作员应基于观察到的负载静态调优。

### 6.4 黑名单集成

与外部黑名单 API（abuseipdb、内部允许 /
拒绝列表）的集成是后续。上限检查点是自然插入点：
在上限后检查黑名单，黑名单拒绝产生不同日志行 + 计数器。

### 6.5 每源 IP TCP 级上限（前置 TLS）

原始 L4 设计
（[#1057](https://github.com/sozu-proxy/sozu/issues/1057)）
提议在接受时全局 TCP-RST 上限，前置 TLS 握手。
此未单独实现 —— 交付的每 (集群, IP) 上限
在集群解析后覆盖相同滥用向量（HTTPS 后置 TLS）。
对于前置 TLS 拒绝重要的部署
（攻击者的 SSL 握手 CPU 成本），
TCP 级前置握手上限是可能的后续。
`accept_queue.saturated_seconds` 和
`client.connect.per_source.bucket_*` 指标已交付
表面饱和条件；前置 TLS 上限建立于此上。

## 7. 操作员指南

### 7.1 设置全局默认

```toml
# 面向公众监听器服务异构流量的推荐起点。
# 调优经验法则：
#   max_connections_per_ip << max_connections   （典型比例 1:100）
max_connections        = 10_000
max_connections_per_ip = 100
```

源 IP 可对每个集群持有最多 100 并发连接，
但监听器整体 admit 最多 10 000 ——
因此单一攻击者饱和一个集群但不饿死
同一监听器服务的其他集群。

### 7.2 每集群覆盖

- 内部管理 API：`max_connections_per_ip = 0`（无限）。
- 面向公众严格集群：`max_connections_per_ip = 20`。
- 默认：继承全局值。

### 7.3 NAT 或共享出口后

如果真实世界租户通过单一 NAT IP 前面流量
（企业在网络中典型），所有流量共享单一
`(cluster_id, source_ip)` 计数器。
此情况下的操作员应提高上限、将其作用域到
为预期 NAT 形状调优的每集群值、或通过
上游 LB 从 PROXY-protocol v2 喂养 sōzu
真实客户端 IP 使上限按真实客户端运行。

### 7.4 另一个 L4 负载均衡器后

如果 sōzu 在另一个 L4 LB（HAProxy、AWS NLB）下游，
在上游 LB 上启用 PROXY-protocol v2 并配置
sōzu 监听器期望它
（`expect_proxy = true`）。PP-v2 头中
解析的源 IP 是上限使用的 —— 没有 PP-v2，
sōzu 看到上游 LB 的 IP 作为源并按 LB IP
而非按真实客户端速率限制。

## 8. 交叉引用

- [`doc/configure.md`](configure.md) —— 操作员Facing TOML 参考。
- [`doc/upgrade/1.x-to-2.0.md`](upgrade/1.x-to-2.0.md) ——
  `New TOML keys` 节记录操作员从 1.1.x 升级的
  `max_connections_per_ip`。
- [`CHANGELOG.md`](../CHANGELOG.md) ——
  `Per-(cluster, source-IP) connection limit (#1193)` 条目
  在 `🌟 Added` 下。
- `lib/src/protocol/mux/router.rs::route_from_request` —— H1+H2 执行点。
- `lib/src/tcp.rs` —— TCP 执行点。
- `e2e/src/tests/cluster_ip_limit_tests.rs` —— 端到端覆盖。
