# 通过命令行配置 sozu

sozu 可执行文件可用于启动代理并对其进行配置：添加新的后端服务器、读取指标等。
它通过 unix 套接字与当前正在运行的代理进行通信。

您可以通过将以下内容添加到您的 `config.toml` 来指定其路径：

```toml
command_socket = "path/to/your/command_folder/sock"
```

## 添加具有 http 和 https 前端的集群

首先，您需要创建一个具有 id 和负载平衡策略（roundrobin 或 random）的新集群：

```bash
sozu --config /etc/sozu/config.toml cluster add --id <my_cluster_id> --load-balancing-policy roundrobin
```

要创建启用 HTTP/2 后端连接的集群：

```bash
sozu --config /etc/sozu/config.toml cluster add --id <my_cluster_id> --load-balancing-policy roundrobin --http2
```

它不会显示任何内容，但您可以通过查询 sozu 来验证集群是否已成功添加：

```bash
sozu --config /etc/sozu/config.toml query clusters
```

然后你需要添加一个后端：

```bash
sozu --config /etc/sozu/config.toml backend add --address 127.0.0.1:3000 --backend-id <my_backend_id> --id <my_cluster_id>
```

### 添加 http 前端

和一个 http 监听器：

```bash
sozu --config /etc/sozu/config.toml listener http add --address 0.0.0.0:80 --tls-versions TLSv1.2 --tls-cipher-list ECDHE-ECDSA-AES256-GCM-SHA384 --tls-cipher-suites TLS_AES_256_GCM_SHA384 --tls-signature-algorithms ECDSA+SHA512 --tls-groups-list x25519 --expect-proxy
```

最后，您必须创建一个前端以允许 sozu 将流量从侦听器发送到您的后端：

```bash
sozu --config /etc/sozu/config.toml frontend http add --address 0.0.0.0:80 --hostname <my_cluster_hostname> id <my_cluster_id>
```

要将某个主机名下仅子路径的流量路由到该集群，请添加 `--path-prefix`
（其他匹配模式请使用 `--path-regex` 或 `--path-equals` —— 详见
`doc/configure.md` 中的 “前端内的路径匹配优先级”）：

```bash
sozu --config /etc/sozu/config.toml frontend http add --address 0.0.0.0:80 --hostname <my_cluster_hostname> --path-prefix /api id <my_cluster_id>
```

### 添加 https 前端

和一个 https 监听器：

```bash
sozu --config /etc/sozu/config.toml listener https add --address 0.0.0.0:443
```

最后，您必须创建一个前端以允许 sozu 将流量从侦听器发送到您的后端：

```bash
sozu --config /etc/sozu/config.toml frontend https add --address 0.0.0.0:443 --hostname <my_cluster_hostname> id <my_cluster_id>
```

## 为后端连接启用或禁用 HTTP/2

您可以在运行时对现有集群切换后端连接的 HTTP/2：

```bash
sozu --config /etc/sozu/config.toml cluster h2 enable --id <my_cluster_id>
sozu --config /etc/sozu/config.toml cluster h2 disable --id <my_cluster_id>
```

这会查询当前集群配置，更新 `http2` 标志，并重新应用到所有 worker，而不影响其他集群设置。

## 检查 sozu 的状态

它显示了一个工作进程列表并显示有关其状态的信息。

```bash
sozu --config /etc/sozu/config.toml status
```

## 获取指标和统计信息

它将显示有关 sozu、工作进程和集群指标的全局统计信息。

```bash
sozu --config /etc/sozu/config.toml query metrics
```

## 转储和恢复状态

如果 sozu 配置（集群、前端和后端）未写入配置文件，您可以保存 sozu 状态以便稍后恢复。

```bash
sozu --config /etc/sozu/config.toml state save --file state.json
```

然后正常关闭 sozu：

```bash
sozu --config /etc/sozu/config.toml shutdown
```

重新启动 sozu 并恢复其状态：

```bash
sozu --config /etc/sozu/config.toml state load --file state.json
```

您应该能够像关闭前一样请求您的集群。

### 使用事件监控后端状态

此 CLI 命令：

```bash
sozu --config /path/to/config.toml events
```

侦听 Sōzu 工作进程在后端关闭、再次启动或没有可用后端时发送的事件。

## 实时运维 TUI（`sozu top`）

`top` 子命令是一个类似 btop/htop 的实时仪表盘。需使用可选的 `tui` Cargo 特性进行构建
（`cargo build -p sozu --features tui --release`）；当该子命令被链接进来时，
`sozu --version` 会显示 `+tui`。完整的运维指南（面板、按键绑定、皮肤格式、阈值调优）
请参阅 [`doc/sozu-top.md`](sozu-top.md)。

```bash
sozu --config /path/to/config.toml top
```

常用参数：

| 参数 | 效果 |
|------|--------|
| `--refresh-ms <N>` | 数据轮询间隔（毫秒，默认 `1000`）。 |
| `--detail <DETAIL>` | 基数租约级别（`process|frontend|cluster|backend`，默认 `backend`）。 |
| `--lease-ttl-seconds <N>` | 租约 TTL；在 TTL 过半时自动续期（默认 `60`，服务端上限 `300`）。 |
| `--skin <NAME>` | 解析 `$XDG_CONFIG_HOME/sozu/skins/<NAME>.toml`（`SOZU_TOP_SKIN` 环境变量优先）。 |
| `--glyphs <MODE>` | 强制某种字形模式（`braille|block|tty`）；默认自动检测。 |
| `--no-mouse` | 禁用 SGR 鼠标捕获（有助于修复在复用器中鼠标事件被错误路由的问题）。 |
| `--snapshot <N>`、`--tick-once` | 渲染 N 帧 / 单次 tick 后退出（测试用途）。 |

按键绑定（运维速查；完整列表见 `doc/sozu-top.md`）：

- `1`-`7` 跳转到 OVERVIEW · CLUSTERS · BACKENDS · LISTENERS · CERTS · H2 · EVENTS。
- `Tab` / `Shift-Tab` 前后切换标签页。
- `s` / `S` 在 CLUSTERS 和 BACKENDS 上循环 / 反向循环排序列。
- `q` / `Q` / `Ctrl-C` / `F10` 退出，`?` / `F1` 切换帮助。
