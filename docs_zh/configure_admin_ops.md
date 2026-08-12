# Sōzu — 运维重新配置指南

本文档介绍操作员在故障排除和维护期间使用的运行时调整参数，
以 `sozu` CLI 的操作示例展开。它是 [`configure.md`](configure.md) 的运维 counterpart：
该文件是逐字段参考；本文档按操作员的实际运行顺序来讲解各命令动词，
包括随 `Update*Listener` 动词引入的"省略时保留"的逐字段语义。

数据平面内部实现参见
[`../lib/src/protocol/mux/LIFECYCLE.md`](../lib/src/protocol/mux/LIFECYCLE.md)；
管控面参见
[`../bin/src/command/LIFECYCLE.md`](../bin/src/command/LIFECYCLE.md)。

---

## 1. 可补丁的监听器字段

每次 `sozu listener {http,https,tcp} update` 调用都会生成一个
`Update*Listener` 请求类型
（`UpdateHttpListenerConfig` / `UpdateHttpsListenerConfig` /
`UpdateTcpListenerConfig` —— 参见
`bin/src/command/requests.rs:33` 的导入）。其语义是
**省略时保留**：您没有传递的每个 CLI 标志都会在 worker 端保持当前值，
因此更新是一个真正的补丁，而非完整替换。

简表如下 —— 完整字段参考（含默认值、可变性类别和指标影响）
请参见 [`configure.md`](configure.md)：

| 字段                                   | 监听器类型        | 省略时保留 | 说明                                                              |
|----------------------------------------|------------------|-----------|--------------------------------------------------------------------|
| `front_timeout` / `back_timeout`       | http, https, tcp | 是         | 秒；仅影响补丁后的新会话                                             |
| `connect_timeout`                      | http, https, tcp | 是         | 秒                                                                 |
| `request_timeout`                      | http, https      | 是         |                                                                    |
| `disable_http11`                       | https            | 是         | 仅影响新握手                                                         |
| `alpn_protocols`                       | https            | 是         | 使用 `--reset-alpn` 恢复默认值 `["h2", "http/1.1"]`                |
| `strict_sni_binding`                   | https            | 是         | `:authority` 被证书 SAN 覆盖（CWE-346 / CWE-444）                   |
| `sozu_id_header`                       | http, https      | 是         | 重新命名每个请求的关联头                                             |
| H2 洪水阈值 (`h2_max_*`)               | https            | 是         | 每次连接设置；仅对新建连接生效                                        |
| `h2_stream_idle_timeout_seconds`       | https            | 是         | 防范慢速多路复用 Slowloris                                          |
| `h2_max_header_table_size`             | https            | 是         | HPACK 动态表上限                                                    |
| `h2_stream_shrink_ratio`               | https            | 是         | 每次连接的 scratch-Vec 收缩阈值                                      |
| `expect_proxy`                         | tcp              | 是         | PROXY-v2 入口                                                      |

CLI 标志到字段的映射位于
`bin/src/cli.rs` 和 `bin/src/ctl/request_builder.rs`。

---

## 2. 操作示例 —— 遭受攻击时收紧 H2 洪水阈值

当 Rapid Reset（CVE-2023-44487）特征出现在监控仪表盘中时，
在不停止任何 worker 的情况下将每窗口的 RST_STREAM 上限减半，
并降低寿命期的滥用上限：

```bash
# 先查看各监听器的当前阈值。
sozu listener list

# 将 HTTPS 监听器的 Rapid Reset 预算减半。
sozu listener https update -a 0.0.0.0:8443 \
    --h2-max-rst-stream-per-window 50 \
    --h2-max-rst-stream-abusive-lifetime 25

# 确认补丁已生效。
sozu listener list
```

已有 H2 连接保持它们被接受时的阈值 —— 洪水检测器在连接建立时接入，
不会重新读取。补丁后新建的连接会看到更严格的限制。

CONTINUATION 洪水阈值（CVE-2024-27316）和服务端发出的
RST_STREAM 阈值（CVE-2025-8671）遵循相同模式，
各自有 `--h2-max-continuation-frames` 和
`--h2-max-rst-stream-emitted-lifetime` 标志。
详见 `configure.md:560-567`。

接收端的关注计数器是
`h2.flood.violation.<kind>`（每个 CVE 一个）以及
`h2.{goaway,rst_stream}.{sent,received}.<code>`（用于
GOAWAY / RST_STREAM 错误归因）。

---

## 3. 操作示例 —— 按监听器切换 `disable_http11`

`disable_http11` 是每个监听器上的 HTTP/1.1 连接禁用开关。
当为 `true` 时，rustls 握手会拒绝任何 ALPN 提议中不含 `h2`
（或完全省略 ALPN）的客户端。拒绝路径上触发的指标见下方 §5。

```bash
# 强制每个新客户端在 HTTPS 监听器上协商 h2。
sozu listener https update -a 0.0.0.0:8443 --disable-http11

# 恢复 —— 允许 HTTP/1.1 回退。
sozu listener https update -a 0.0.0.0:8443 --enable-http11
```

进行中的 HTTPS 握手按其启动时的 rustls 配置完成；
新策略仅适用于新握手。此监听器上的现有 HTTP/1.1 会话
会继续直到关闭。

---

## 4. 操作示例 —— `cluster h2 enable|disable`

`sozu cluster h2 enable | disable` 命令用于切换
`Cluster::http2`，这是一个驱动"代理是否应尝试对该集群后端使用 H2"
的后端能力提示。在 `feat/h2-mux` 上 Sōzu 仍然对后端使用 H1，
因此此开关是面向未来的 —— 它不控制前端 H2，
前端 H2 完全由 TLS ALPN 驱动。

```bash
# 在标记集群为后端 H2 可用。
sozu cluster h2 enable --id my-cluster

# 恢复。
sozu cluster h2 disable --id my-cluster
```

行为上这是一个**查询后重新提交**的舞步，而非部分补丁。
参见 `bin/src/ctl/request_builder.rs:214-238`：

1. CLI 发出 `QueryClusterById(my-cluster)` 请求，同步等待
   master 响应（`request_builder.rs:220-221`）。
2. 在响应中找到匹配的 `ClusterInformation`，
   提取当前 `ClusterConfiguration`（`request_builder.rs:222-240`）。
3. 重写提取配置上的 `http2` 字段，并以完整 `AddCluster(updated)`
   重新提交（`request_builder.rs:242-247`）。监管器将
   `AddCluster` 视为 upsert，因此这充当了针对性编辑，
   即使没有专用的"补丁集群"动词。

对操作员的影响：一个并非通过查询-重提交舞步产生的
`AddCluster` 配置（例如从状态文件加载的）会完全替换集群。
在不编写自定义客户端的情况下应用部分集群变更，
请遵循相同的两步查询-重提交模式。

---

## 5. `feat/h2-mux` 分支引入的行为

以下项目是在 `feat/h2-mux` 分支引入的，
此处作为**运维机制**文档 —— 做什么、何时触发、如何监控 ——
而非重复 `configure.md` 中已有的逐字段参考。

### 5.1 每次连接的 H2 stream-Vec 收缩

提交：`e478cf8b`。参考：`doc/configure.md:442, 458, 570`。

每个 `ConnectionH2` 在 mux `Context` 中维护一个
`Vec<Stream>` 的每个流槽位。回收的槽位在连接生命周期内累积；
如果没有有界的收缩，即使负载下降到寥寥几个并发流，
Vec 也会保持在峰值水位。

`h2_stream_shrink_ratio`（默认 `2`，最小 `2`）控制
收缩阈值：当 `total_slots > active_streams * ratio` 时收缩 Vec。
在内存压力调查时收紧比值；在突发性拓扑上放宽比值，
以保持槽位预热。

关注点：Vec 的有效大小尚未作为公开指标 ——
症状是长生命周期连接上的 RSS 增长与峰值流并发度成正比。
如果操作员怀疑收缩设置不当，捕获一次 RSS 样本，
强制降低客户端并发度，一秒后重新采样。

### 5.2 Channel `message_len` 上限

提交：`18c251f1`。参考：`command/src/channel.rs`。

监管器 ↔ worker `Channel` 帧携带 `usize` 前缀的消息长度。
新的上限拒绝任何超过配置 `command_buffer_size` 的 peer 发送长度，
这样畸形的 worker 无法诱使监管器分配数 GB 读取缓冲区。
默认 `command_buffer_size = 16384` 对于 Sōzu 当前使用的动词来说很宽裕；
如果您引入的动词载荷确实超出上限，请成对（两端同步）提高它。

超出上限时，监管器记录日志并丢弃出问题的 peer 会话；
worker 通过其 channel 上的 EOF 观察到丢弃，
并由监管器的标准 worker 重生路径重启（当
`worker_automatic_restart` 启用时）。

### 5.3 Unix 命令 socket 注册失败时丢弃

提交：`b8c8fc61`。参考：
[`../bin/src/command/LIFECYCLE.md`](../bin/src/command/LIFECYCLE.md) §2.5。

如果 `mio::Registry::register` 对刚接受的命令 socket
客户端失败（slab 耗尽、FD 无效），监管器现在将其视为终止：
记录 token + 错误，丢弃 `UnixStream`，向 peer 发送 RST/EOF。
此前该失败被吞掉，未连接的会话卡在 client map 中直到手动清理，
每次发生都泄漏一个 slab token。

关注点：监管器日志中"register failure"警告突然增多，
通常表示 slab 耗尽（提高 slab 预算）或其他地方 FD 泄漏；
丢弃的客户端现在可以在 peer 端观察到 RST 关闭事件。

### 5.4 SNI 尾部点规范化

提交：`c5fe3655`。

TLS 握手路径在匹配配置的证书地图之前，
对客户提供的 SNI 尾部的点号进行规范化。
没有此修复时，发送 `SNI = host.example.com.`
（完全限定 DNS 形式）的客户端会错过
`host.example.com` 证书，触发 ALPN 或证书不匹配，
导致握手关闭。修复在匹配前剥离单个尾部点。

新的计数器 `https.alpn.rejected.unsupported`
（见下方 §5.5）使原先未跟踪的"未知 ALPN 协议"拒绝路径可观测；
此处文档化以便操作员的"ALPN 拒绝"速率条匹配带标签桶的总和。

### 5.5 `https.alpn.rejected.unsupported` 计数器

来源：`lib/src/https.rs:359`。文档见 `doc/configure.md:933`。

在 rustls 接受路径上，当协商的 ALPN 协议
不是显式处理的值（`h2`、`http/1.1` 或缺失）时触发。
此分支之前是静默的 —— 任何绘制
`https.alpn.rejected.*` 的操作员仪表板都错过了
未知协议拒绝（例如 `h3` 错误通过某种配置错误渗出）。
将此计数器添加到与
`https.alpn.rejected.http11_disabled` 相同的告警桶中。

### 5.6 `ensure_frame_size!` 宏

来源：`lib/src/protocol/mux/parser.rs`。

内部加固说明：H2 帧解析器之前在每个固定大小帧处
手写"is this fixed-size frame the right length?"检查。
宏将检查合并，使未来的固定大小帧添加无法因长度混淆类
CVE 而退化。操作员看不到行为变化；
实际效果是
[`fuzz_frame_parser`](../fuzz/README.md#21-fuzz_frame_parser)
只有一个阻塞点可以断言。

---

## 6. 交叉引用

- [`configure.md`](configure.md) —— 每个可配置旋钮的逐字段参考
  （默认值、可变性、验证器、指标影响）。
- [`../lib/src/protocol/mux/LIFECYCLE.md`](../lib/src/protocol/mux/LIFECYCLE.md)
  —— H2 会话和流生命周期内部。
- [`../bin/src/command/LIFECYCLE.md`](../bin/src/command/LIFECYCLE.md)
  —— 监管器 / 命令 socket 生命周期。
- [`observability.md`](observability.md) —— 日志信封、审计日志
  字段、指标参考。
- [`../fuzz/README.md`](../fuzz/README.md) —— H2 帧 + HPACK
  模糊测试套件。
