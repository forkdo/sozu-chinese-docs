# 需要监控的关键指标

Sōzu 暴露以下监控指标：

| 指标 | 类型 | 描述 |
|--------|------|-------------|
| `sozu.http.requests` | counter | HTTP 请求总数 |
| `sozu.http.errors` | counter | 失败请求数（解析错误 + 4xx/5xx） |
| `sozu.client.connections` | gauge | 活动前端连接数 |
| `sozu.backend.connections` | gauge | 活动后端连接数 |
| `sozu.buffer.number` | gauge | 缓冲池中的活动缓冲区数 |
| `sozu.slab.entries` | gauge | Slab 分配器使用量（会话槽位） |
| `sozu.zombies` | gauge | 检测到的僵尸会话（表明存在 bug — 应为 0） |
| `health_check.success` | counter | 健康检查探测成功响应数（按集群，在带有标签发出时） |
| `health_check.failure` | counter | 健康检查探测失败数（连接错误、超时、状态码不匹配） |
| `health_check.up` | counter | 后端在连续成功达到 `healthy_threshold` 次后转为健康状态 |
| `health_check.down` | counter | 后端在连续失败达到 `unhealthy_threshold` 次后转为不健康状态 |
| `health_check.healthy_backends` | gauge | 每个集群的健康后端数量，在每次健康检查结果更新时发出（前提是该集群至少配置了一个后端）—— 当所有后端均不健康时，该值包含 `0`。可与 `backends.fail_open` 搭配使用，在仪表盘中检测全局宕机 / fail-open 路由情况。 |
| `backends.fail_open` | counter | 每次路由决策落入 fail-open 路径时递增，即当没有后端通过常规 `can_open()` 检查，且负载均衡器回退到状态为 `Normal` 且重试策略为 `OKAY` 的后端时。伴随的 `warn!` 日志仅在进入/退出该状态时触发，因此此计数器可作为操作员可见的每请求信号。 |

## 获取指标

```bash
sozu -c /etc/config.toml metrics get
```
