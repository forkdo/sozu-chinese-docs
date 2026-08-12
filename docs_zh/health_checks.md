# 健康检查

Sōzu 支持对后端服务器进行主动 HTTP 健康检查。在集群上配置后，
Sōzu 会定期向每个后端发送 HTTP 请求并跟踪其是否成功响应。
连续检查失败的后端会被标记为不健康并排除出负载均衡。
一旦它们再次开始响应，则标记为健康，流量恢复。

## 工作原理

健康检查在主 mio 事件循环内运行，使用非阻塞 TCP 连接。
没有单独的线程或进程 —— 检查与正常请求处理交错进行。

对于每个配置了健康检查的集群，Sōzu 在每个检查周期执行以下操作：

1. 向集群中每个后端打开非阻塞 TCP 连接
2. 发送探测请求，其 wire 格式遵循集群的 `http2` 标志：
   - 当 `cluster.http2 = false`（默认）时，发送 HTTP/1.1
     (`GET <uri> HTTP/1.1` with `Connection: close`)
   - 当 `cluster.http2 = true` 时，发送 HTTP/2 prior-knowledge
     （连接 preface + 空 SETTINGS + 携带 `GET <uri>` 的
     stream 1 上的 HEADERS 帧）
3. 读取响应：默认路径为 HTTP/1.1 状态行，
   或 h2c 路径等待 HEADERS 帧在 stream 1 上产生 `:status`
4. 将 HTTP 状态码与期望值比较
5. 根据成功或失败更新后端的健康状态

### 健康状态机

每个后端维护一个 `HealthState`，包含连续成功和失败计数器：

- **健康 → 不健康**：在 `unhealthy_threshold` 次连续失败检查后，
  后端被标记为 DOWN。Sōzu 记录错误日志，递增
  `health_check.down` 指标，并发出 `HealthCheckUnhealthy` 事件。
- **不健康 → 健康**：在 `healthy_threshold` 次连续成功检查后，
  后端被标记为 UP。Sōzu 记录信息日志，递增
  `health_check.up` 指标，并发出 `HealthCheckHealthy` 事件。

当 HTTP 响应状态码匹配 `expected_status` 时，
检查视为成功。如果 `expected_status` 为 `0`（默认），
任何 2xx 状态码（200–299）均被接受。

检查失败的情况：
- TCP 连接无法建立
- 请求超时（在 `timeout` 秒内无响应）
- 响应状态码与期望值不匹配

### 对负载均衡的影响

不健康的后端在后端选择时被跳过。它们仍保留在集群注册表中 ——
Sōzu 继续对其健康检查，并在它们恢复后自动重新引入池中。

## 配置

### 配置文件（TOML）

向任何集群定义中添加 `health_check` 节：

```toml
[clusters.my-cluster]
protocol = "http"
frontends = [
    { address = "0.0.0.0:8080", hostname = "example.com" }
]
backends = [
    { address = "127.0.0.1:3000" },
    { address = "127.0.0.1:3001" },
]

[clusters.my-cluster.health_check]
uri = "/health"
interval = 10
timeout = 5
healthy_threshold = 3
unhealthy_threshold = 3
expected_status = 0
```

### 配置参数

| 参数                   | 类型   | 默认值 | 说明                                                                      |
| --------------------- | ------ | ------- | --------------------------------------------------------------------------- |
| `uri`                 | string | —       | **必填。** HTTP 请求路径（如 `/health`、`/ready`、`/ping`）。          |
| `interval`            | u32    | `10`    | 此集群的检查周期间隔（秒）。                                                |
| `timeout`             | u32    | `5`     | 标记检查失败前等待响应的秒数。                                              |
| `healthy_threshold`   | u32    | `3`     | 从不健康过渡到健康所需的连续成功次数。                                      |
| `unhealthy_threshold` | u32    | `3`     | 从健康过渡到不健康所需的连续失败次数。                                      |
| `expected_status`     | u32    | `0`     | 期望的 HTTP 状态码。`0` 表示接受任何 2xx。                                  |

探测 wire 格式遵循集群的 `http2` 标志。设置
`[clusters.<id>] http2 = true` 同时切换数据平面后端连接
和健康检查探测到 HTTP/2 prior-knowledge，
因此 h2c-only 后端永远不会被 HTTP/1.1 探测（反之亦然）。

### 命令行

健康检查可以使用 `sozu cluster health-check` 在运行时管理：

#### 设置或更新健康检查

```bash
sozu cluster health-check set \
    --id my-cluster \
    --uri /health \
    --interval 10 \
    --timeout 5 \
    --healthy-threshold 3 \
    --unhealthy-threshold 3 \
    --expected-status 0
```

为指定集群创建或替换健康检查配置。只有 `--id` 和 `--uri` 是必填的 ——
其他标志有合理的默认值（如上所示）。

| 标志                      | 必填 | 默认值 | 说明                                   |
| ----------------------- | -------- | ------- | -------------------------------------------- |
| `--id`, `-i`            | 是       | —       | 要配置的集群 ID。                          |
| `--uri`, `-u`           | 是       | —       | HTTP 请求路径（如 `/health`）。            |
| `--interval`            | 否       | `10`    | 检查周期间隔（秒）。                       |
| `--timeout`             | 否       | `5`     | 检查被视为失败前的秒数。                   |
| `--healthy-threshold`   | 否       | `3`     | 标记后端 UP 所需的连续成功次数。           |
| `--unhealthy-threshold` | 否       | `3`     | 标记后端 DOWN 所需的连续失败次数。         |
| `--expected-status`     | 否       | `0`     | 期望的 HTTP 状态码（`0` = 任何 2xx）。     |

#### 列出健康检查配置

```bash
# 列出所有配置的健康检查
sozu cluster health-check list

# 按集群 ID 筛选
sozu cluster health-check list --id my-cluster
```

示例输出：

```
┌────────────┬─────────┬──────────┬─────────┬───────────────────┬─────────────────────┬─────────────────┐
│ cluster    │ uri     │ interval │ timeout │ healthy threshold │ unhealthy threshold │ expected status │
├────────────┼─────────┼──────────┼─────────┼───────────────────┼─────────────────────┼─────────────────┤
│ my-cluster │ /health │ 10s      │ 5s      │ 3                 │ 3                   │ any 2xx         │
│ api        │ /ready  │ 5s       │ 3s      │ 2                 │ 5                   │ 200             │
└────────────┴─────────┴──────────┴─────────┴───────────────────┴─────────────────────┴─────────────────┘
```

提供 `--id` 时，只显示该集群的健康检查。省略时，
列出所有配置了健康检查的集群。未配置健康检查的集群不出现。

使用 `sozu --json cluster health-check list` 时，
输出也可用 JSON 格式。

#### 删除健康检查

```bash
sozu cluster health-check remove --id my-cluster
```

停止指定集群的健康检查。集群中的所有后端重置为健康状态，
立即恢复接收流量。

## 指标

Sōzu 暴露以下健康检查指标：

| 指标                            | 类型    | 说明                                                                                                                                                                                                                                                                                                                                         |
| ------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `health_check.success`          | counter | 成功健康检查响应的总数。                                                                                                                                                                                                                                                                                                  |
| `health_check.failure`          | counter | 失败健康检查尝试的总数。                                                                                                                                                                                                                                                                                                       |
| `health_check.up`               | counter | 健康转换次数（不健康 → 健康）。                                                                                                                                                                                                                                                                                                |
| `health_check.down`             | counter | 不健康转换次数（健康 → 不健康）。                                                                                                                                                                                                                                                                                              |
| `health_check.healthy_backends` | gauge   | 每个集群的健康后端数 —— 带 `cluster_id` 标签。在每个探针结果更新后更新，适用于至少有一个配置后端的集群（包括全部不健康时为 `0`，以便仪表盘检测全局中断 / fail-open）。此标签在早期版本中缺失，各集群值会相互覆盖。 |

跨集群可用性故事（`cluster.available_backends`、
`cluster.total_backends`、`cluster.no_available_backends`、
`cluster.available_recovered`、`backend.available`）位于
[`configure.md` § Cluster availability](configure.md#cluster-availability)，
因为这些信号并非完全由健康检查驱动 —— 它们还纳入
数据路径上观察到的重试策略状态。因此 `cluster.*` 表面和
每后端 `backend.available` gauge 在没有配置健康检查时也能工作：
数据路径上的每次 TCP 连接失败都会触发
`Backend::retry_policy`，一旦所有后端达到
`retry_policy.is_down()`，下次路由调用会将集群翻转为
`AllDown` 并发出匹配事件 + 日志行。在此基础上添加主动健康检查，
适用于集群空闲时（无请求意味着无被动观察），
但对表面正常工作不是必需的。

## 事件

健康状态转换发出可由订阅者消费的事件（通过
`sozu events subscribe`）：

- `HealthCheckHealthy` —— 后端 transition 到健康
- `HealthCheckUnhealthy` —— 后端 transition 到不健康
- `NoAvailableBackends` —— 集群 transition 到 `Available → AllDown`
  （每个后端都不满足可用性谓词；不限于健康检查失败 ——
  重试策略退避也计入）
- `ClusterRecovered` —— 集群 transition 回 `AllDown → Available`
  （proto tag 29）。与 `NoAvailableBackends` 配对，
  以便订阅者跟踪全下和恢复而不轮询

前两个事件包含 `cluster_id`、`backend_id` 和后端 `address`。
集群可用性事件只携带 `cluster_id`（后端身份无关紧要 ——
事件是关于集群整体的）。

## 设计考量

- **非阻塞**：健康检查与正常代理操作共享 mio 事件循环。
  没有额外线程，检查从不阻塞请求处理。
- **每集群配置**：每个集群可以有自己独立的健康检查 URI、
  间隔、阈值和期望状态。没有 `health_check` 节的集群不被检查。
- **全部后端不健康时的 fail-open 路由**：当集群中每个后端
  都被阈值状态机标记为 DOWN 时，Sōzu 回退到跨所有
  `Normal` 后端路由，而非返回 503 ——
  参见 `lib/src/load_balancing.rs::BackendList::healthy`。
  Amazon 健康检查论文的理由（返回 503 在健康检查信号本身
  可能错误时很少是正确答案）驱动了此行为。
  fail-open 触发时记录 `warn!("fail-open: ...")`，
  且 `health_check.healthy_backends` gauge 降至 0。
  使用保守阈值和 `health_check.down` 计数器对持续故障告警。
- **Wire 格式遵循 `cluster.http2`**：当
  `cluster.http2 = false`（默认）时，探测发送纯文本
  HTTP/1.1 请求。当 `cluster.http2 = true` 时，
  探测发送 HTTP/2 连接 preface、空客户端 SETTINGS 帧、
  和 stream 1 上携带 `GET <uri>` 的单个 HEADERS 帧。
  响应解析器遍历 H2 帧寻找 stream 1 上的 HEADERS 帧，
  解码 `:status` 伪头来确定探测结果；
  连接上的 GOAWAY 帧视为探测失败。
  探测和数据平面后端连接共享同一个
  `cluster.http2` 开关，因此不会发散。
  HTTPS 探测（TLS 之上的 h2）尚未实现；
  仅接受 TLS 连接的后端需要要么有共位的
  HTTP/1.1 健康端点，要么当前不配置 `health_check`。
- **无持久状态**：健康检查状态保存在内存中。
  worker 重启后，所有后端从健康开始，
  必须经过足够多的失败检查才会被标记为不健康。
