---
title: 配置 (Configure)
category: 概念 (Concept)
order: 1
---
# 配置

Sōzu 的配置完全基于 **TOML** 格式，这允许您在一个文件中描述完整的代理配置。

Sōzu 可以热加载其配置——这意味着无需重启代理即可使其接受新的监听器、路由、集群、后端服务器和所有其他配置参数。

Sōzu 的配置通过其 HTTP API 加载，通过 PUT `/config` 端点，该端点接收完整的配置文件作为请求体。

```bash
curl -X PUT http://127.0.0.1:7575/config --data-binary @/etc/sozu/configuration.toml
```

配置文件使用 **TOML** 格式编写。TOML 是一个简单的配置文件格式，易于阅读，并且与 Python、Ruby、Go 等许多编程语言的配置格式兼容。

## 全局参数

以下是所有可以在 Sōzu 配置文件中设置的参数：

### `id`

代理的唯一标识符。如果未指定，则使用主机名。

**必填**

```toml
id = "production-001"
```

### `host`

用于控制接口的地址。

```toml
host = "127.0.0.1"
```

### `port`

控制接口的端口。

```toml
port = 7575
```

### `certificate`

控制接口使用的证书。

如果未指定，则使用默认控制接口证书。如果配置了 `certificate_file` 和 `key_file`，则使用这些文件。

```toml
certificate = "control"
```

### `certificate_file`

控制接口使用的证书文件路径。

```toml
certificate_file = "/etc/sozu/certificates/control.pem"
```

### `key_file`

控制接口使用的私钥文件路径。

```toml
key_file = "/etc/sozu/certificates/control.key"
```

### `tls_versions`

控制接口使用的 TLS 版本。默认值为 `[TLS12, TLS13]`。

```toml
tls_versions = ["TLS12", "TLS13"]
```

### `default_front`

没有前端匹配时使用的默认集群。

```toml
default_front = "default"
```

### `shutdown_timeout`

在关闭期间，等待请求完成的时间（以秒为单位）。默认值为 10 秒。

```toml
shutdown_timeout = 30
```

### `sni_preread_timeout`

TCP SNI 预读取的超时时间（以秒为单位）。默认值为 5 秒。

```toml
sni_preread_timeout = 10
```

### `sni_preread_max_bytes`

TCP SNI 预读取阶段在路由决策前允许的最大字节数。

```toml
sni_preread_max_bytes = 16384
```

### `udp_max_datagram_size`

UDP 数据报的最大大小（以字节为单位）。默认值为 65535。

```toml
udp_max_datagram_size = 8192
```

### `udp_max_flows`

代理可以跟踪的最大活动 UDP 流数。默认值为 10000。

```toml
udp_max_flows = 100000
```

### `udp_health_delay`

UDP 健康检查的间隔（以秒为单位）。默认值为 30 秒。

```toml
udp_health_delay = 60
```

### `udp_max_retries`

在将 UDP 后端标记为不健康之前允许的最大重试次数。默认值为 3。

```toml
udp_max_retries = 5
```

### `udp_max_responses`

在关闭之前 UDP 流可以返回的最大响应数。默认值为 100。

```toml
udp_max_responses = 1000
```

### `udp_max_requests`

在关闭之前 UDP 流可以处理的最大请求数。默认值为 100。

```toml
udp_max_requests = 1000
```

### `udp_idle_timeout`

UDP 流在因空闲被关闭之前的超时时间（以秒为单位）。默认值为 30 秒。

```toml
udp_idle_timeout = 60
```

### `udp_flow_reuse`

是否允许在同一个 UDP 流中复用后端。默认值为 `true`。

```toml
udp_flow_reuse = true
```

### `request_buffer_size`

每个 HTTP 请求的请求缓冲区大小（以字节为单位）。默认值为 16384。

```toml
request_buffer_size = 32768
```

### `response_buffer_size`

每个 HTTP 响应缓冲区的大小（以字节为单位）。默认值为 16384。

```toml
response_buffer_size = 32768
```

### `header_buffer_size`

每个 HTTP 请求标头的缓冲区大小（以字节为单位）。默认值为 8192。

```toml
header_buffer_size = 16384
```

### `proxy_buffer_size`

用于 PROXY 协议的缓冲区大小（以字节为单位）。默认值为 1024。

```toml
proxy_buffer_size = 4096
```

### `max_concurrent_streams`

每个连接允许的最大并发 HTTP/2 流数。默认值为 100。

```toml
max_concurrent_streams = 200
```

### `max_header_list_size`

允许的 HTTP/2 标头列表的最大大小（以字节为单位）。默认值为 16384。

```toml
max_header_list_size = 32768
```

### `max_frame_size`

HTTP/2 帧的最大大小（以字节为单位）。默认值为 16384。

```toml
max_frame_size = 32768
```

### `initial_window_size`

HTTP/2 初始流量控制窗口大小（以字节为单位）。默认值为 65535。

```toml
initial_window_size = 131072
```

### `initial_connection_window_size`

HTTP/2 初始连接级流量控制窗口大小（以字节为单位）。默认值为 65535。

```toml
initial_connection_window_size = 1048576
```

### `max_header_fields`

每个 HTTP/2 请求允许的最大标头字段数。默认值为 100。

```toml
max_header_fields = 200
```

### `access_log_buffer_size`

每个代理的访问日志缓冲区大小（以字节为单位）。默认值为 131072。

```toml
access_log_buffer_size = 262144
```

### `access_log_max_items`

在刷新到磁盘之前每个代理的最大访问日志条目数。默认值为 100。

```toml
access_log_max_items = 200
```

### `access_log`

是否启用访问日志记录。默认值为 `false`。

```toml
access_log = false
```

### `access_log_path`

访问日志文件的路径。默认值为 `/var/log/sozu/access.log`。

```toml
access_log_path = "/var/log/sozu/access.log"
```

### `metrics_buffer_size`

每个代理的指标缓冲区大小（以字节为单位）。默认值为 32768。

```toml
metrics_buffer_size = 65536
```

### `metrics_max_items`

在刷新到统计服务之前每个代理的最大指标条目数。默认值为 1000。

```toml
metrics_max_items = 2000
```

### `metrics`

是否启用指标导出。默认值为 `false`。

```toml
metrics = false
```

### `statsd_host`

StatsD 指标导出器的主机。

```toml
statsd_host = "127.0.0.1"
```

### `statsd_port`

StatsD 指标导出器的端口。

```toml
statsd_port = 8125
```

### `statsd_prefix`

StatsD 指标的前缀。

```toml
statsd_prefix = "sozu"
```

### `statsd_tags`

添加到所有 StatsD 指标的全局标签。

```toml
statsd_tags = ["env:production", "region:us-east-1"]
```

### `statsd_tags_separator`

用于在指标名称和标签之间分隔的字符。默认值为 `.`。

```toml
statsd_tags_separator = "."
```

### `statsd_tags_key_separator`

用于在标签键和标签值之间分隔的字符。默认值为 `:`。

```toml
statsd_tags_key_separator = ":"
```

### `statsd_tags_multi_separator`

用于在多个标签值之间分隔的字符。默认值为 `|`。

```toml
statsd_tags_multi_separator = "|"
```

### `statsd_sample_rate`

指标采样的比率。默认值为 1.0（即无采样）。

```toml
statsd_sample_rate = 0.1
```

### `statsd_udp_buffer_size`

StatsD 指标的 UDP 缓冲区大小（以字节为单位）。默认值为 4096。

```toml
statsd_udp_buffer_size = 8192
```

### `statsd_udp_buffer_items`

在刷新到 StatsD 服务器之前的最大指标条目数。默认值为 100。

```toml
statsd_udp_buffer_items = 200
```

### `statsd_flush_interval`

刷新到 StatsD 服务器的间隔（以秒为单位）。默认值为 10 秒。

```toml
statsd_flush_interval = 5
```

### `health_check_delay`

后端健康检查的间隔（以秒为单位）。默认值为 5 秒。

```toml
health_check_delay = 10
```

### `health_check_timeout`

健康检查请求的超时时间（以秒为单位）。默认值为 5 秒。

```toml
health_check_timeout = 10
```

### `health_check_max_retries`

在将后端标记为不健康之前允许的最大重试次数。默认值为 5。

```toml
health_check_max_retries = 5
```

### `h2_max_initial_header_list_size`

HTTP/2 初始 `SETTINGS_MAX_HEADER_LIST_SIZE` 值。

```toml
h2_max_initial_header_list_size = 262144
```

### `h2_max_max_header_list_size`

Sōzu 将接受的 `SETTINGS_MAX_HEADER_LIST_SIZE` 的最大值。

```toml
h2_max_max_header_list_size = 1048576
```

### `h2_header_list_size`

当前允许的标头列表大小（以字节为单位），由 `SETTINGS_MAX_HEADER_LIST_SIZE` 控制。

```toml
h2_header_list_size = 262144
```

### `h2_max_initial_header_table_size`

HTTP/2 初始 `SETTINGS_HEADER_TABLE_SIZE` 值。

```toml
h2_max_initial_header_table_size = 4096
```

### `h2_max_max_header_table_size`

Sōzu 将接受的 `SETTINGS_HEADER_TABLE_SIZE` 的最大值。

```toml
h2_max_max_header_table_size = 65536
```

### `h2_header_table_size`

当前 HPACK 标头压缩表大小（以字节为单位），由 `SETTINGS_HEADER_TABLE_SIZE` 控制。

```toml
h2_header_table_size = 4096
```

### `h2_max_header_fields`

HTTP/2 标头块中允许的最大标头字段数。

```toml
h2_max_header_fields = 100
```

### `h2_initial_window_size`

HTTP/2 初始流量控制窗口大小。

```toml
h2_initial_window_size = 65535
```

### `h2_max_initial_window_size`

Sōzu 将接受的 `SETTINGS_INITIAL_WINDOW_SIZE` 的最大值。

```toml
h2_max_initial_window_size = 1048576
```

### `h2_initial_connection_window_size`

HTTP/2 初始连接级流量控制窗口大小。

```toml
h2_initial_connection_window_size = 1048576
```

### `h2_max_initial_connection_window_size`

Sōzu 将接受的连接级 `SETTINGS_INITIAL_WINDOW_SIZE` 的最大值。

```toml
h2_max_initial_connection_window_size = 4294967295
```

### `h2_max_concurrent_streams`

每个 HTTP/2 连接允许的最大并发流数。

```toml
h2_max_concurrent_streams = 100
```

### `h2_max_max_concurrent_streams`

Sōzu 将接受的 `SETTINGS_MAX_CONCURRENT_STREAMS` 的最大值。

```toml
h2_max_max_concurrent_streams = 100000
```

### `h2_max_frame_size`

HTTP/2 帧的最大大小（以字节为单位）。

```toml
h2_max_frame_size = 16384
```

### `h2_max_max_frame_size`

Sōzu 将接受的 `SETTINGS_MAX_FRAME_SIZE` 的最大值。

```toml
h2_max_max_frame_size = 16777215
```

### `h2_max_header_block_size`

HTTP/2 标头块的最大大小（以字节为单位）。

```toml
h2_max_header_block_size = 1048576
```

### `h2_max_header_block_frames`

单个标头块可以跨越的 CONTINUATION 帧的最大数量。

```toml
h2_max_header_block_frames = 100
```

### `h2_max_header_block_continuations`

单个标头块允许的最大 CONTINUATION 帧数。

```toml
h2_max_header_block_continuations = 100
```

### `h2_initial_flow_control_window`

HTTP/2 初始流量控制窗口大小（以字节为单位）。

```toml
h2_initial_flow_control_window = 65535
```

### `h2_max_flow_control_window`

流量控制窗口的最大值（以字节为单位）。

```toml
h2_max_flow_control_window = 4294967295
```

### `h2_connection_window_increment`

每个 WINDOW_UPDATE 帧的连接级窗口增量。

```toml
h2_connection_window_increment = 1048576
```

### `h2_stream_window_increment`

每个 WINDOW_UPDATE 帧的流级窗口增量。

```toml
h2_stream_window_increment = 131072
```

### `h2_rst_stream_rate_per_second`

每秒发送的 RST_STREAM 帧的最大数量。

```toml
h2_rst_stream_rate_per_second = 100
```

### `h2_rst_stream_burst`

在每秒速率限制之前允许的 RST_STREAM 突发大小。

```toml
h2_rst_stream_burst = 200
```

### `h2_rst_stream_window_count`

滑动窗口内的 RST_STREAM 计数。

```toml
h2_rst_stream_window_count = 100
```

### `h2_rst_stream_window_duration`

RST_STREAM 计数的滑动窗口持续时间（以秒为单位）。

```toml
h2_rst_stream_window_duration = 10
```

### `h2_rst_stream_lifetime_count`

从连接建立开始计算的生命周期 RST_STREAM 计数。

```toml
h2_rst_stream_lifetime_count = 10000
```

### `h2_rst_stream_pre_response_lifetime_count`

在响应发送之前计算的生命周期 RST_STREAM 计数。

```toml
h2_rst_stream_pre_response_lifetime_count = 1000
```

### `h2_rst_stream_emitted_lifetime_count`

从连接建立开始计算的生命周期发出的 RST_STREAM 计数。

```toml
h2_rst_stream_emitted_lifetime_count = 10000
```

### `h2_ping_rate_per_second`

每秒发送的 PING 帧的最大数量。

```toml
h2_ping_rate_per_second = 10
```

### `h2_ping_burst`

在每秒速率限制之前允许的 PING 突发大小。

```toml
h2_ping_burst = 20
```

### `h2_settings_rate_per_second`

每秒发送的 SETTINGS 帧的最大数量。

```toml
h2_settings_rate_per_second = 1
```

### `h2_settings_burst`

在每秒速率限制之前允许的 SETTINGS 突发大小。

```toml
h2_settings_burst = 3
```

### `h2_empty_data_rate_per_second`

每秒发送的空 DATA 帧的最大数量。

```toml
h2_empty_data_rate_per_second = 10
```

### `h2_empty_data_burst`

在每秒速率限制之前允许的空 DATA 突发大小。

```toml
h2_empty_data_burst = 20
```

### `h2_glitch_rate_per_second`

每秒允许的协议异常的最大数量。

```toml
h2_glitch_rate_per_second = 10
```

### `h2_glitch_burst`

在每秒速率限制之前允许的协议异常突发大小。

```toml
h2_glitch_burst = 20
```

### `h2_max_goaway_rate_per_second`

每秒发送的 GOAWAY 帧的最大数量。

```toml
h2_max_goaway_rate_per_second = 1
```

### `h2_max_goaway_burst`

在每秒速率限制之前允许的 GOAWAY 突发大小。

```toml
h2_max_goaway_burst = 3
```

### `http2_enable_push`

是否启用 HTTP/2 服务器推送。

```toml
http2_enable_push = false
```

### `http2_allow_h2c`

是否允许 HTTP/2 明文（h2c）升级。

```toml
http2_allow_h2c = true
```

### `http2_max_push_promises`

每个连接允许的最大 HTTP/2 推送承诺数量。

```toml
http2_max_push_promises = 10
```

### `http2_max_push_streams`

每个连接允许的最大 HTTP/2 推送流数量。

```toml
http2_max_push_streams = 10
```

### `http2_push_stream_window_size`

HTTP/2 推送流的窗口大小（以字节为单位）。

```toml
http2_push_stream_window_size = 1048576
```

### `http2_connection_window_size`

HTTP/2 连接窗口大小（以字节为单位）。

```toml
http2_connection_window_size = 1048576
```

### `http2_stream_window_size`

HTTP/2 流窗口大小（以字节为单位）。

```toml
http2_stream_window_size = 1048576
```

### `http2_initial_window_size`

HTTP/2 初始窗口大小（以字节为单位）。

```toml
http2_initial_window_size = 65535
```

### `http2_max_concurrent_streams`

每个连接允许的最大 HTTP/2 并发流数量。

```toml
http2_max_concurrent_streams = 100
```

### `http2_max_header_list_size`

HTTP/2 标头列表的最大大小（以字节为单位）。

```toml
http2_max_header_list_size = 16384
```

### `http2_max_header_table_size`

HTTP/2 HPACK 标头表的最大大小（以字节为单位）。

```toml
http2_max_header_table_size = 4096
```

### `http2_max_frame_size`

HTTP/2 帧的最大大小（以字节为单位）。

```toml
http2_max_frame_size = 16384
```

### `http2_header_table_size`

HTTP/2 HPACK 标头表大小（以字节为单位）。

```toml
http2_header_table_size = 4096
```

### `http2_initial_header_list_size`

HTTP/2 初始标头列表大小（以字节为单位）。

```toml
http2_initial_header_list_size = 16384
```

### `http2_initial_header_table_size`

HTTP/2 初始 HPACK 标头表大小（以字节为单位）。

```toml
http2_initial_header_table_size = 4096
```

### `http2_max_header_fields`

每个 HTTP/2 标头块允许的最大标头字段数量。

```toml
http2_max_header_fields = 100
```

### `http2_max_header_block_size`

HTTP/2 标头块的最大大小（以字节为单位）。

```toml
http2_max_header_block_size = 1048576
```

### `http2_max_header_block_frames`

单个 HTTP/2 标头块可以跨越的 CONTINUATION 帧的最大数量。

```toml
http2_max_header_block_frames = 100
```

### `http2_max_header_block_continuations`

单个 HTTP/2 标头块允许的最大 CONTINUATION 帧数。

```toml
http2_max_header_block_continuations = 100
```

### `http2_initial_flow_control_window`

HTTP/2 初始流量控制窗口大小（以字节为单位）。

```toml
http2_initial_flow_control_window = 65535
```

### `http2_max_flow_control_window`

HTTP/2 流量控制窗口的最大值（以字节为单位）。

```toml
http2_max_flow_control_window = 4294967295
```

### `http2_connection_window_increment`

每个 WINDOW_UPDATE 帧的 HTTP/2 连接级窗口增量。

```toml
http2_connection_window_increment = 1048576
```

### `http2_stream_window_increment`

每个 WINDOW_UPDATE 帧的 HTTP/2 流级窗口增量。

```toml
http2_stream_window_increment = 131072
```

### `http2_rst_stream_rate_per_second`

每秒发送的 HTTP/2 RST_STREAM 帧的最大数量。

```toml
http2_rst_stream_rate_per_second = 100
```

### `http2_rst_stream_burst`

在每秒速率限制之前允许的 HTTP/2 RST_STREAM 突发大小。

```toml
http2_rst_stream_burst = 200
```

### `http2_rst_stream_window_count`

滑动窗口内的 HTTP/2 RST_STREAM 计数。

```toml
http2_rst_stream_window_count = 100
```

### `http2_rst_stream_window_duration`

HTTP/2 RST_STREAM 计数的滑动窗口持续时间（以秒为单位）。

```toml
http2_rst_stream_window_duration = 10
```

### `http2_rst_stream_lifetime_count`

从连接建立开始计算的 HTTP/2 生命周期 RST_STREAM 计数。

```toml
http2_rst_stream_lifetime_count = 10000
```

### `http2_rst_stream_pre_response_lifetime_count`

在响应发送之前计算的 HTTP/2 生命周期 RST_STREAM 计数。

```toml
http2_rst_stream_pre_response_lifetime_count = 1000
```

### `http2_rst_stream_emitted_lifetime_count`

从连接建立开始计算的 HTTP/2 生命周期发出的 RST_STREAM 计数。

```toml
http2_rst_stream_emitted_lifetime_count = 10000
```

### `http2_ping_rate_per_second`

每秒发送的 HTTP/2 PING 帧的最大数量。

```toml
http2_ping_rate_per_second = 10
```

### `http2_ping_burst`

在每秒速率限制之前允许的 HTTP/2 PING 突发大小。

```toml
http2_ping_burst = 20
```

### `http2_settings_rate_per_second`

每秒发送的 HTTP/2 SETTINGS 帧的最大数量。

```toml
http2_settings_rate_per_second = 1
```

### `http2_settings_burst`

在每秒速率限制之前允许的 HTTP/2 SETTINGS 突发大小。

```toml
http2_settings_burst = 3
```

### `http2_empty_data_rate_per_second`

每秒发送的 HTTP/2 空 DATA 帧的最大数量。

```toml
http2_empty_data_rate_per_second = 10
```

### `http2_empty_data_burst`

在每秒速率限制之前允许的 HTTP/2 空 DATA 突发大小。

```toml
http2_empty_data_burst = 20
```

### `http2_glitch_rate_per_second`

每秒允许的 HTTP/2 协议异常的最大数量。

```toml
http2_glitch_rate_per_second = 10
```

### `http2_glitch_burst`

在每秒速率限制之前允许的 HTTP/2 协议异常突发大小。

```toml
http2_glitch_burst = 20
```

### `http2_max_goaway_rate_per_second`

每秒发送的 HTTP/2 GOAWAY 帧的最大数量。

```toml
http2_max_goaway_rate_per_second = 1
```

### `http2_max_goaway_burst`

在每秒速率限制之前允许的 HTTP/2 GOAWAY 突发大小。

```toml
http2_max_goaway_burst = 3
```

### `tls_versions`

代理将支持的 TLS 版本。

```toml
tls_versions = ["TLSv1_2", "TLSv1_3"]
```

### `certificate_manager`

cert-manager 配置。用于自动轮换证书。

```toml
certificate_manager = "sozu-cm"
```

### `certificate_manager_address`

cert-manager 服务地址。

```toml
certificate_manager_address = "127.0.0.1:8080"
```

### `certificate_manager_timeout`

cert-manager 请求超时时间（以秒为单位）。

```toml
certificate_manager_timeout = 10
```

### `certificate_manager_retry`

cert-manager 请求重试次数。

```toml
certificate_manager_retry = 3
```

### `certificate_manager_retry_delay`

cert-manager 请求重试延迟（以秒为单位）。

```toml
certificate_manager_retry_delay = 5
```

### `access_log_fields`

访问日志中将包含的字段。默认值为所有字段。

```toml
access_log_fields = ["timestamp", "method", "path", "status", "duration"]
```

### `access_log_format`

访问日志格式。支持 `json` 和 `text`。

```toml
access_log_format = "json"
```

### `access_log_destination`

访问日志输出目标。支持 `file`、`stdout` 和 `stderr`。

```toml
access_log_destination = "file"
```

### `metrics_backend`

指标后端。支持 `statsd` 和 `prometheus`。

```toml
metrics_backend = "statsd"
```

### `prometheus_address`

Prometheus 指标端点地址。

```toml
prometheus_address = "127.0.0.1:9100"
```

### `prometheus_path`

Prometheus 指标端点路径。

```toml
prometheus_path = "/metrics"
```

### `prometheus_bearer_token`

Prometheus 指标端点的 Bearer Token。

```toml
prometheus_bearer_token = "<token>"
```

## 监听器

Sōzu 使用监听器来定义代理应该监听的地址和端口，以及如何处理收到的连接。

监听器的配置使用 `[listeners]` 表头，后面跟着一系列 `[[listener]]` 定义。

### 监听器基本配置

```toml
[[listener]]
address = "0.0.0.0:80"
protocol = "http"
```

或者使用 `[listeners]` 表头：

```toml
[listeners]
[listeners.http]
address = "0.0.0.0:80"
protocol = "http"
```

### 监听器参数

以下是所有可以在监听器上设置的参数：

#### `address`

监听器将要监听的地址和端口。

**必填**

```toml
address = "0.0.0.0:80"
```

#### `protocol`

监听器将使用的协议。支持 `http`、`https`、`tcp` 和 `udp`。

**必填**

```toml
protocol = "http"
```

#### `name`

监听器的名称。如果未指定，则使用地址作为名称。

```toml
name = "http-listener"
```

#### `certificates`

监听器将使用的证书列表。仅适用于 HTTPS 监听器。

```toml
certificates = ["example-com.pem"]
```

#### `certificate_file`

监听器将使用的证书文件路径。仅适用于 HTTPS 监听器。

```toml
certificate_file = "/etc/sozu/certificates/example-com.pem"
```

#### `key_file`

监听器将使用的私钥文件路径。仅适用于 HTTPS 监听器。

```toml
key_file = "/etc/sozu/certificates/example-com.key"
```

#### `tls_versions`

监听器将支持的 TLS 版本。仅适用于 HTTPS 监听器。

```toml
tls_versions = ["TLSv1_2", "TLSv1_3"]
```

#### `alpn`

监听器将支持的 ALPN 协议列表。仅适用于 HTTPS 监听器。

```toml
alpn = ["h2", "http/1.1"]
```

#### `tls_ciphers`

监听器将支持的 TLS 密码套件列表。仅适用于 HTTPS 监听器。

```toml
tls_ciphers = ["ECDHE-RSA-AES128-GCM-SHA256", "ECDHE-RSA-AES256-GCM-SHA384"]
```

#### `tls_curves`

监听器将支持的 TLS 椭圆曲线列表。仅适用于 HTTPS 监听器。

```toml
tls_curves = ["X25519", "P-256", "P-384"]
```

#### `expect_proxy`

监听器是否应该期望接收 PROXY 协议头。

```toml
expect_proxy = true
```

#### `send_proxy`

监听器是否应该发送 PROXY 协议头。

```toml
send_proxy = true
```

#### `hsts`

是否启用 HTTP 严格传输安全（HSTS）。仅适用于 HTTPS 监听器。

```toml
hsts = true
```

#### `hsts_max_age`

HSTS 的最大年龄（以秒为单位）。

```toml
hsts_max_age = 31536000
```

#### `hsts_include_subdomains`

HSTS 是否应该包括子域。

```toml
hsts_include_subdomains = true
```

#### `hsts_preload`

HSTS 是否应该被标记为预加载。

```toml
hsts_preload = false
```

#### `proxy`

监听器是否应该使用 PROXY 协议。

```toml
proxy = true
```

#### `proxy_protocol_version`

PROXY 协议版本。支持 `1` 和 `2`。

```toml
proxy_protocol_version = 2
```

#### `proxy_timeout`

PROXY 协议头的读取超时时间（以秒为单位）。

```toml
proxy_timeout = 5
```

#### `frontend`

与监听器关联的前端。

```toml
frontend = "frontend-name"
```

#### `frontends`

与监听器关联的前端列表。

```toml
frontends = ["frontend-1", "frontend-2"]
```

#### `cluster`

与监听器关联的集群。

```toml
cluster = "cluster-name"
```

#### `clusters`

与监听器关联的集群列表。

```toml
clusters = ["cluster-1", "cluster-2"]
```

#### `default_front`

没有前端匹配时使用的默认集群。

```toml
default_front = "default-cluster"
```

#### `max_connections`

监听器允许的最大并发连接数。默认值为 10000。

```toml
max_connections = 100000
```

#### `backlog`

监听器 TCP 监听队列的积压大小。默认值为 1024。

```toml
backlog = 2048
```

#### `idle_timeout`

连接在因空闲被关闭之前的超时时间（以秒为单位）。

```toml
idle_timeout = 60
```

#### `keepalive_timeout`

HTTP 长连接的保持活动超时时间（以秒为单位）。

```toml
keepalive_timeout = 30
```

#### `keepalive_requests`

在因长连接被关闭之前每个 HTTP 连接允许的最大请求数。

```toml
keepalive_requests = 100
```

#### `client_max_body_size`

客户端请求体的最大大小（以字节为单位）。

```toml
client_max_body_size = 1048576
```

#### `client_body_timeout`

客户端请求体读取超时时间（以秒为单位）。

```toml
client_body_timeout = 60
```

#### `client_header_timeout`

客户端请求头读取超时时间（以秒为单位）。

```toml
client_header_timeout = 30
```

#### `send_timeout`

发送到后端的超时时间（以秒为单位）。

```toml
send_timeout = 60
```

#### `read_timeout`

从后端读取的超时时间（以秒为单位）。

```toml
read_timeout = 60
```

#### `connection_timeout`

建立到后端的连接的超时时间（以秒为单位）。

```toml
connection_timeout = 5
```

#### `request_buffer_size`

请求缓冲区大小（以字节为单位）。

```toml
request_buffer_size = 16384
```

#### `response_buffer_size`

响应缓冲区大小（以字节为单位）。

```toml
response_buffer_size = 16384
```

#### `header_buffer_size`

标头缓冲区大小（以字节为单位）。

```toml
header_buffer_size = 8192
```

#### `access_log`

是否启用访问日志记录。

```toml
access_log = true
```

#### `access_log_path`

访问日志文件的路径。

```toml
access_log_path = "/var/log/sozu/access.log"
```

#### `metrics`

是否启用指标导出。

```toml
metrics = true
```

#### `statsd_host`

StatsD 指标导出器的主机。

```toml
statsd_host = "127.0.0.1"
```

#### `statsd_port`

StatsD 指标导出器的端口。

```toml
statsd_port = 8125
```

#### `statsd_prefix`

StatsD 指标的前缀。

```toml
statsd_prefix = "sozu"
```

#### `statsd_tags`

添加到所有 StatsD 指标的全局标签。

```toml
statsd_tags = ["env:production", "region:us-east-1"]
```

#### `statsd_tags_separator`

用于在指标名称和标签之间分隔的字符。默认值为 `.`。

```toml
statsd_tags_separator = "."
```

#### `statsd_tags_key_separator`

用于在标签键和标签值之间分隔的字符。默认值为 `:`。

```toml
statsd_tags_key_separator = ":"
```

#### `statsd_tags_multi_separator`

用于在多个标签值之间分隔的字符。默认值为 `|`。

```toml
statsd_tags_multi_separator = "|"
```

#### `statsd_sample_rate`

指标采样的比率。默认值为 1.0（即无采样）。

```toml
statsd_sample_rate = 0.1
```

#### `statsd_udp_buffer_size`

StatsD 指标的 UDP 缓冲区大小（以字节为单位）。

```toml
statsd_udp_buffer_size = 4096
```

#### `statsd_udp_buffer_items`

在刷新到 StatsD 服务器之前的最大指标条目数。

```toml
statsd_udp_buffer_items = 100
```

#### `statsd_flush_interval`

刷新到 StatsD 服务器的间隔（以秒为单位）。

```toml
statsd_flush_interval = 10
```

#### `health_check_delay`

健康检查的间隔（以秒为单位）。

```toml
health_check_delay = 5
```

#### `health_check_timeout`

健康检查请求的超时时间（以秒为单位）。

```toml
health_check_timeout = 5
```

#### `health_check_max_retries`

在将后端标记为不健康之前允许的最大重试次数。

```toml
health_check_max_retries = 5
```

#### `h2_max_initial_header_list_size`

HTTP/2 初始 `SETTINGS_MAX_HEADER_LIST_SIZE` 值。

```toml
h2_max_initial_header_list_size = 262144
```

#### `h2_max_max_header_list_size`

Sōzu 将接受的 `SETTINGS_MAX_HEADER_LIST_SIZE` 的最大值。

```toml
h2_max_max_header_list_size = 1048576
```

#### `h2_header_list_size`

当前允许的标头列表大小（以字节为单位），由 `SETTINGS_MAX_HEADER_LIST_SIZE` 控制。

```toml
h2_header_list_size = 262144
```

#### `h2_max_initial_header_table_size`

HTTP/2 初始 `SETTINGS_HEADER_TABLE_SIZE` 值。

```toml
h2_max_initial_header_table_size = 4096
```

#### `h2_max_max_header_table_size`

Sōzu 将接受的 `SETTINGS_HEADER_TABLE_SIZE` 的最大值。

```toml
h2_max_max_header_table_size = 65536
```

#### `h2_header_table_size`

当前 HPACK 标头压缩表大小（以字节为单位），由 `SETTINGS_HEADER_TABLE_SIZE` 控制。

```toml
h2_header_table_size = 4096
```

#### `h2_max_header_fields`

每个 HTTP/2 标头块允许的最大标头字段数。

```toml
h2_max_header_fields = 100
```

#### `h2_initial_window_size`

HTTP/2 初始流量控制窗口大小。

```toml
h2_initial_window_size = 65535
```

#### `h2_max_initial_window_size`

Sōzu 将接受的 `SETTINGS_INITIAL_WINDOW_SIZE` 的最大值。

```toml
h2_max_initial_window_size = 1048576
```

#### `h2_initial_connection_window_size`

HTTP/2 初始连接级流量控制窗口大小。

```toml
h2_initial_connection_window_size = 1048576
```

#### `h2_max_initial_connection_window_size`

Sōzu 将接受的连接级 `SETTINGS_INITIAL_WINDOW_SIZE` 的最大值。

```toml
h2_max_initial_connection_window_size = 4294967295
```

#### `h2_max_concurrent_streams`

每个 HTTP/2 连接允许的最大并发流数。

```toml
h2_max_concurrent_streams = 100
```

#### `h2_max_max_concurrent_streams`

Sōzu 将接受的 `SETTINGS_MAX_CONCURRENT_STREAMS` 的最大值。

```toml
h2_max_max_concurrent_streams = 100000
```

#### `h2_max_frame_size`

HTTP/2 帧的最大大小（以字节为单位）。

```toml
h2_max_frame_size = 16384
```

#### `h2_max_max_frame_size`

Sōzu 将接受的 `SETTINGS_MAX_FRAME_SIZE` 的最大值。

```toml
h2_max_max_frame_size = 16777215
```

#### `h2_max_header_block_size`

HTTP/2 标头块的最大大小（以字节为单位）。

```toml
h2_max_header_block_size = 1048576
```

#### `h2_max_header_block_frames`

单个标头块可以跨越的 CONTINUATION 帧的最大数量。

```toml
h2_max_header_block_frames = 100
```

#### `h2_max_header_block_continuations`

单个标头块允许的最大 CONTINUATION 帧数。

```toml
h2_max_header_block_continuations = 100
```

#### `h2_initial_flow_control_window`

HTTP/2 初始流量控制窗口大小（以字节为单位）。

```toml
h2_initial_flow_control_window = 65535
```

#### `h2_max_flow_control_window`

流量控制窗口的最大值（以字节为单位）。

```toml
h2_max_flow_control_window = 4294967295
```

#### `h2_connection_window_increment`

每个 WINDOW_UPDATE 帧的连接级窗口增量。

```toml
h2_connection_window_increment = 1048576
```

#### `h2_stream_window_increment`

每个 WINDOW_UPDATE 帧的流级窗口增量。

```toml
h2_stream_window_increment = 131072
```

#### `h2_rst_stream_rate_per_second`

每秒发送的 RST_STREAM 帧的最大数量。

```toml
h2_rst_stream_rate_per_second = 100
```

#### `h2_rst_stream_burst`

在每秒速率限制之前允许的 RST_STREAM 突发大小。

```toml
h2_rst_stream_burst = 200
```

#### `h2_rst_stream_window_count`

滑动窗口内的 RST_STREAM 计数。

```toml
h2_rst_stream_window_count = 100
```

#### `h2_rst_stream_window_duration`

RST_STREAM 计数的滑动窗口持续时间（以秒为单位）。

```toml
h2_rst_stream_window_duration = 10
```

#### `h2_rst_stream_lifetime_count`

从连接建立开始计算的生命周期 RST_STREAM 计数。

```toml
h2_rst_stream_lifetime_count = 10000
```

#### `h2_rst_stream_pre_response_lifetime_count`

在响应发送之前计算的生命周期 RST_STREAM 计数。

```toml
h2_rst_stream_pre_response_lifetime_count = 1000
```

#### `h2_rst_stream_emitted_lifetime_count`

从连接建立开始计算的生命周期发出的 RST_STREAM 计数。

```toml
h2_rst_stream_emitted_lifetime_count = 10000
```

#### `h2_ping_rate_per_second`

每秒发送的 PING 帧的最大数量。

```toml
h2_ping_rate_per_second = 10
```

#### `h2_ping_burst`

在每秒速率限制之前允许的 PING 突发大小。

```toml
h2_ping_burst = 20
```

#### `h2_settings_rate_per_second`

每秒发送的 SETTINGS 帧的最大数量。

```toml
h2_settings_rate_per_second = 1
```

#### `h2_settings_burst`

在每秒速率限制之前允许的 SETTINGS 突发大小。

```toml
h2_settings_burst = 3
```

#### `h2_empty_data_rate_per_second`

每秒发送的空 DATA 帧的最大数量。

```toml
h2_empty_data_rate_per_second = 10
```

#### `h2_empty_data_burst`

在每秒速率限制之前允许的空 DATA 突发大小。

```toml
h2_empty_data_burst = 20
```

#### `h2_glitch_rate_per_second`

每秒允许的协议异常的最大数量。

```toml
h2_glitch_rate_per_second = 10
```

#### `h2_glitch_burst`

在每秒速率限制之前允许的协议异常突发大小。

```toml
h2_glitch_burst = 20
```

#### `h2_max_goaway_rate_per_second`

每秒发送的 GOAWAY 帧的最大数量。

```toml
h2_max_goaway_rate_per_second = 1
```

#### `h2_max_goaway_burst`

在每秒速率限制之前允许的 GOAWAY 突发大小。

```toml
h2_max_goaway_burst = 3
```

#### `http2_enable_push`

是否启用 HTTP/2 服务器推送。

```toml
http2_enable_push = false
```

#### `http2_allow_h2c`

是否允许 HTTP/2 明文（h2c）升级。

```toml
http2_allow_h2c = true
```

#### `http2_max_push_promises`

每个连接允许的最大 HTTP/2 推送承诺数量。

```toml
http2_max_push_promises = 10
```

#### `http2_max_push_streams`

每个连接允许的最大 HTTP/2 推送流数量。

```toml
http2_max_push_streams = 10
```

#### `http2_push_stream_window_size`

HTTP/2 推送流的窗口大小（以字节为单位）。

```toml
http2_push_stream_window_size = 1048576
```

#### `http2_connection_window_size`

HTTP/2 连接窗口大小（以字节为单位）。

```toml
http2_connection_window_size = 1048576
```

#### `http2_stream_window_size`

HTTP/2 流窗口大小（以字节为单位）。

```toml
http2_stream_window_size = 1048576
```

#### `http2_initial_window_size`

HTTP/2 初始窗口大小（以字节为单位）。

```toml
http2_initial_window_size = 65535
```

#### `http2_max_concurrent_streams`

每个连接允许的最大 HTTP/2 并发流数量。

```toml
http2_max_concurrent_streams = 100
```

#### `http2_max_header_list_size`

HTTP/2 标头列表的最大大小（以字节为单位）。

```toml
http2_max_header_list_size = 16384
```

#### `http2_max_header_table_size`

HTTP/2 HPACK 标头表的最大大小（以字节为单位）。

```toml
http2_max_header_table_size = 4096
```

#### `http2_max_frame_size`

HTTP/2 帧的最大大小（以字节为单位）。

```toml
http2_max_frame_size = 16384
```

#### `http2_header_table_size`

HTTP/2 HPACK 标头表大小（以字节为单位）。

```toml
http2_header_table_size = 4096
```

#### `http2_initial_header_list_size`

HTTP/2 初始标头列表大小（以字节为单位）。

```toml
http2_initial_header_list_size = 16384
```

#### `http2_initial_header_table_size`

HTTP/2 初始 HPACK 标头表大小（以字节为单位）。

```toml
http2_initial_header_table_size = 4096
```

#### `http2_max_header_fields`

每个 HTTP/2 标头块允许的最大标头字段数量。

```toml
http2_max_header_fields = 100
```

#### `http2_max_header_block_size`

HTTP/2 标头块的最大大小（以字节为单位）。

```toml
http2_max_header_block_size = 1048576
```

#### `http2_max_header_block_frames`

单个 HTTP/2 标头块可以跨越的 CONTINUATION 帧的最大数量。

```toml
http2_max_header_block_frames = 100
```

#### `http2_max_header_block_continuations`

单个 HTTP/2 标头块允许的最大 CONTINUATION 帧数。

```toml
http2_max_header_block_continuations = 100
```

#### `http2_initial_flow_control_window`

HTTP/2 初始流量控制窗口大小（以字节为单位）。

```toml
http2_initial_flow_control_window = 65535
```

#### `http2_max_flow_control_window`

HTTP/2 流量控制窗口的最大值（以字节为单位）。

```toml
http2_max_flow_control_window = 4294967295
```

#### `http2_connection_window_increment`

每个 WINDOW_UPDATE 帧的 HTTP/2 连接级窗口增量。

```toml
http2_connection_window_increment = 1048576
```

#### `http2_stream_window_increment`

每个 WINDOW_UPDATE 帧的 HTTP/2 流级窗口增量。

```toml
http2_stream_window_increment = 131072
```

#### `http2_rst_stream_rate_per_second`

每秒发送的 HTTP/2 RST_STREAM 帧的最大数量。

```toml
http2_rst_stream_rate_per_second = 100
```

#### `http2_rst_stream_burst`

在每秒速率限制之前允许的 HTTP/2 RST_STREAM 突发大小。

```toml
http2_rst_stream_burst = 200
```

#### `http2_rst_stream_window_count`

滑动窗口内的 HTTP/2 RST_STREAM 计数。

```toml
http2_rst_stream_window_count = 100
```

#### `http2_rst_stream_window_duration`

HTTP/2 RST_STREAM 计数的滑动窗口持续时间（以秒为单位）。

```toml
http2_rst_stream_window_duration = 10
```

#### `http2_rst_stream_lifetime_count`

从连接建立开始计算的 HTTP/2 生命周期 RST_STREAM 计数。

```toml
http2_rst_stream_lifetime_count = 10000
```

#### `http2_rst_stream_pre_response_lifetime_count`

在响应发送之前计算的 HTTP/2 生命周期 RST_STREAM 计数。

```toml
http2_rst_stream_pre_response_lifetime_count = 1000
```

#### `http2_rst_stream_emitted_lifetime_count`

从连接建立开始计算的 HTTP/2 生命周期发出的 RST_STREAM 计数。

```toml
http2_rst_stream_emitted_lifetime_count = 10000
```

#### `http2_ping_rate_per_second`

每秒发送的 HTTP/2 PING 帧的最大数量。

```toml
http2_ping_rate_per_second = 10
```

#### `http2_ping_burst`

在每秒速率限制之前允许的 HTTP/2 PING 突发大小。

```toml
http2_ping_burst = 20
```

#### `http2_settings_rate_per_second`

每秒发送的 HTTP/2 SETTINGS 帧的最大数量。

```toml
http2_settings_rate_per_second = 1
```

#### `http2_settings_burst`

在每秒速率限制之前允许的 HTTP/2 SETTINGS 突发大小。

```toml
http2_settings_burst = 3
```

#### `http2_empty_data_rate_per_second`

每秒发送的 HTTP/2 空 DATA 帧的最大数量。

```toml
http2_empty_data_rate_per_second = 10
```

#### `http2_empty_data_burst`

在每秒速率限制之前允许的 HTTP/2 空 DATA 突发大小。

```toml
http2_empty_data_burst = 20
```

#### `http2_glitch_rate_per_second`

每秒允许的 HTTP/2 协议异常的最大数量。

```toml
http2_glitch_rate_per_second = 10
```

#### `http2_glitch_burst`

在每秒速率限制之前允许的 HTTP/2 协议异常突发大小。

```toml
http2_glitch_burst = 20
```

#### `http2_max_goaway_rate_per_second`

每秒发送的 HTTP/2 GOAWAY 帧的最大数量。

```toml
http2_max_goaway_rate_per_second = 1
```

#### `http2_max_goaway_burst`

在每秒速率限制之前允许的 HTTP/2 GOAWAY 突发大小。

```toml
http2_max_goaway_burst = 3
```

## HSTS

HTTP 严格传输安全 (HSTS) 是一种 Web 安全策略机制，可防止攻击者劫持用户与网站之间的连接。通过发送 HSTS 标头，网站可以告诉浏览器仅通过 HTTPS 连接来访问它，即使用户尝试输入 http:// URL。

Sōzu 支持在监听器级别配置 HSTS。启用 HSTS 后，所有通过该监听器服务的响应都会自动包含 `Strict-Transport-Security` 标头。

```toml
[[listener]]
address = "0.0.0.0:443"
protocol = "https"
hsts = true
hsts_max_age = 31536000
hsts_include_subdomains = true
hsts_preload = false
```

- `hsts`：是否启用 HSTS。默认值为 `false`。
- `hsts_max_age`：HSTS 策略的最大年龄，以秒为单位。默认值为 31536000（一年）。
- `hsts_include_subdomains`：是否将 HSTS 策略应用于所有子域。默认值为 `false`。
- `hsts_preload`：是否将网站标记为预加载。默认值为 `false`。

当 `hsts_include_subdomains` 设置为 `true` 时，`Strict-Transport-Security` 标头将包含 `includeSubDomains` 指令。

当 `hsts_preload` 设置为 `true` 时，`Strict-Transport-Security` 标头将包含 `preload` 指令。

## TCP 监听器（SNI/ALPN 路由）

TCP 监听器支持基于 SNI（服务器名称指示）和 ALPN（应用层协议协商）的路由。这允许在没有 TLS 终止的情况下根据客户端请求的主机名将流量路由到不同的后端。

```toml
[[listener]]
address = "0.0.0.0:8443"
protocol = "tcp"

[listener.sni_routing]
enabled = true
timeout = 5000
max_bytes = 8192

[listener.sni_routing.rules]
[listener.sni_routing.rules.0]
hostname = "example.com"
class = "tcp-cluster-1"

[listener.sni_routing.rules.1]
hostname = "example.org"
class = "tcp-cluster-2"
```

- `listener.sni_routing.enabled`：是否启用 SNI 路由。默认值为 `false`。
- `listener.sni_routing.timeout`：等待 TLS ClientHello 的超时时间，以毫秒为单位。默认值为 5000。
- `listener.sni_routing.max_bytes`：从客户端读取的最大字节数。默认值为 8192。
- `listener.sni_routing.rules`：SNI 路由规则列表。
- `listener.sni_routing.rules[i].hostname`：要匹配的主机名。支持通配符匹配（例如 `*.example.com`）。
- `listener.sni_routing.rules[i].class`：要路由到的 TCP 集群。

当 SNI 路由启用时，监听器将在不完成 TLS 握手的 情况下读取 TLS ClientHello，从其中提取 SNI 扩展，然后根据匹配的规则将流量路由到相应的 TCP 集群。

如果 `hostname` 包含通配符（例如 `*.example.com`），它将匹配 `example.com` 和任何子域（例如 `www.example.com`、`api.example.com`）。

当 `protocol` 为 `tcp` 时，监听器仅转发 TCP 流量，不进行任何协议级别的解析或转换。

## UDP 监听器

UDP 监听器用于处理 UDP 流量，例如 DNS 查询。Sōzu 支持基于 UDP 数据报内容的路由。

```toml
[[listener]]
address = "0.0.0.0:53"
protocol = "udp"

[listener.udp_routing]
enabled = true
max_datagram_size = 4096
timeout = 5000

[listener.udp_routing.rules]
[listener.udp_routing.rules.0]
pattern = "dns-query"
cluster = "dns-cluster"
```

- `listener.udp_routing.enabled`：是否启用 UDP 路由。默认值为 `false`。
- `listener.udp_routing.max_datagram_size`：最大数据报大小，以字节为单位。默认值为 4096。
- `listener.udp_routing.timeout`：等待响应的超时时间，以毫秒为单位。默认值为 5000。
- `listener.udp_routing.rules`：UDP 路由规则列表。
- `listener.udp_routing.rules[i].pattern`：匹配模式。支持 `dns-query`、`http-query` 等模式。
- `listener.udp_routing.rules[i].cluster`：要路由到的 UDP 集群。

当 UDP 路由启用时，监听器将读取传入的 UDP 数据报，根据匹配的模式将流量路由到相应的 UDP 集群，并将响应返回给客户端。

UDP 监听器不维护连接状态。每个数据报都是独立处理的，没有连接跟踪或会话管理。

## 前端匹配

Sōzu 使用前端来匹配传入的 HTTP 请求并将其路由到适当的集群。前端的匹配基于请求的各种属性，如主机名、路径、方法等。

### 前端基本配置

```toml
[[frontend]]
name = "api-frontend"
address = "0.0.0.0:80"

[frontend.matching]
hostname = "api.example.com"
path_prefix = "/api/"
method = "GET"

[frontend.backend]
cluster = "api-cluster"
```

### 前端参数

#### `name`

前端的名称。用于在日志和指标中识别前端。

```toml
name = "api-frontend"
```

#### `address`

前端将监听的网络地址。格式为 `host:port`。

```toml
address = "0.0.0.0:80"
```

#### `matching`

定义如何匹配传入的请求。支持以下匹配类型：

- `hostname`：基于主机名匹配。
- `path_prefix`：基于路径前缀匹配。
- `path_regex`：基于正则表达式匹配路径。
- `method`：基于 HTTP 方法匹配。
- `header`：基于请求头匹配。
- `query`：基于查询参数匹配。
- `body`：基于请求体匹配。

```toml
[frontend.matching]
hostname = "api.example.com"
path_prefix = "/api/"
method = "GET"
```

#### `backend`

定义匹配请求后将路由到的后端。

```toml
[frontend.backend]
cluster = "api-cluster"
```

#### `rewrite`

定义如何重写匹配请求的路径。

```toml
[frontend.rewrite]
path = "/api/v1/{anything}"
replace = "/{anything}"
```

#### `redirect`

定义如何将匹配请求重定向到其他 URL。

```toml
[frontend.redirect]
url = "https://www.example.com/{anything}"
status_code = 301
```

#### `rate_limit`

定义如何限制匹配请求的速率。

```toml
[frontend.rate_limit]
rate = 100
burst = 200
window = 60
```

#### `access_log`

是否启用访问日志记录。

```toml
access_log = true
```

#### `access_log_path`

访问日志文件的路径。

```toml
access_log_path = "/var/log/sozu/api-access.log"
```

#### `metrics`

是否启用指标导出。

```toml
metrics = true
```

#### `metrics_prefix`

指标前缀。

```toml
metrics_prefix = "sozu.api"
```

#### `metrics_tags`

添加到指标的全局标签。

```toml
metrics_tags = ["env:production", "service:api"]
```

#### `metrics_sample_rate`

指标采样率。默认值为 1.0（即无采样）。

```toml
metrics_sample_rate = 0.1
```

#### `metrics_udp_buffer_size`

UDP 缓冲区大小（以字节为单位）。

```toml
metrics_udp_buffer_size = 4096
```

#### `metrics_udp_buffer_items`

在刷新到统计服务器之前的最大指标条目数。

```toml
metrics_udp_buffer_items = 100
```

#### `metrics_flush_interval`

刷新到统计服务器的间隔（以秒为单位）。

```toml
metrics_flush_interval = 10
```

#### `health_check_delay`

健康检查的间隔（以秒为单位）。

```toml
health_check_delay = 5
```

#### `health_check_timeout`

健康检查请求的超时时间（以秒为单位）。

```toml
health_check_timeout = 5
```

#### `health_check_max_retries`

在将后端标记为不健康之前允许的最大重试次数。

```toml
health_check_max_retries = 5
```

#### `h2_max_initial_header_list_size`

HTTP/2 初始 `SETTINGS_MAX_HEADER_LIST_SIZE` 值。

```toml
h2_max_initial_header_list_size = 262144
```

#### `h2_max_max_header_list_size`

Sōzu 将接受的 `SETTINGS_MAX_HEADER_LIST_SIZE` 的最大值。

```toml
h2_max_max_header_list_size = 1048576
```

#### `h2_header_list_size`

当前允许的标头列表大小（以字节为单位），由 `SETTINGS_MAX_HEADER_LIST_SIZE` 控制。

```toml
h2_header_list_size = 262144
```

#### `h2_max_initial_header_table_size`

HTTP/2 初始 `SETTINGS_HEADER_TABLE_SIZE` 值。

```toml
h2_max_initial_header_table_size = 4096
```

#### `h2_max_max_header_table_size`

Sōzu 将接受的 `SETTINGS_HEADER_TABLE_SIZE` 的最大值。

```toml
h2_max_max_header_table_size = 65536
```

#### `h2_header_table_size`

当前 HPACK 标头压缩表大小（以字节为单位），由 `SETTINGS_HEADER_TABLE_SIZE` 控制。

```toml
h2_header_table_size = 4096
```

#### `h2_max_header_fields`

每个 HTTP/2 标头块允许的最大标头字段数。

```toml
h2_max_header_fields = 100
```

#### `h2_initial_window_size`

HTTP/2 初始流量控制窗口大小。

```toml
h2_initial_window_size = 65535
```

#### `h2_max_initial_window_size`

Sōzu 将接受的 `SETTINGS_INITIAL_WINDOW_SIZE` 的最大值。

```toml
h2_max_initial_window_size = 1048576
```

#### `h2_initial_connection_window_size`

HTTP/2 初始连接级流量控制窗口大小。

```toml
h2_initial_connection_window_size = 1048576
```

#### `h2_max_initial_connection_window_size`

Sōzu 将接受的连接级 `SETTINGS_INITIAL_WINDOW_SIZE` 的最大值。

```toml
h2_max_initial_connection_window_size = 4294967295
```

#### `h2_max_concurrent_streams`

每个 HTTP/2 连接允许的最大并发流数。

```toml
h2_max_concurrent_streams = 100
```

#### `h2_max_max_concurrent_streams`

Sōzu 将接受的 `SETTINGS_MAX_CONCURRENT_STREAMS` 的最大值。

```toml
h2_max_max_concurrent_streams = 100000
```

#### `h2_max_frame_size`

HTTP/2 帧的最大大小（以字节为单位）。

```toml
h2_max_frame_size = 16384
```

#### `h2_max_max_frame_size`

Sōzu 将接受的 `SETTINGS_MAX_FRAME_SIZE` 的最大值。

```toml
h2_max_max_frame_size = 16777215
```

#### `h2_max_header_block_size`

HTTP/2 标头块的最大大小（以字节为单位）。

```toml
h2_max_header_block_size = 1048576
```

#### `h2_max_header_block_frames`

单个标头块可以跨越的 CONTINUATION 帧的最大数量。

```toml
h2_max_header_block_frames = 100
```

#### `h2_max_header_block_continuations`

单个标头块允许的最大 CONTINUATION 帧数。

```toml
h2_max_header_block_continuations = 100
```

#### `h2_initial_flow_control_window`

HTTP/2 初始流量控制窗口大小（以字节为单位）。

```toml
h2_initial_flow_control_window = 65535
```

#### `h2_max_flow_control_window`

流量控制窗口的最大值（以字节为单位）。

```toml
h2_max_flow_control_window = 4294967295
```

#### `h2_connection_window_increment`

每个 WINDOW_UPDATE 帧的连接级窗口增量。

```toml
h2_connection_window_increment = 1048576
```

#### `h2_stream_window_increment`

每个 WINDOW_UPDATE 帧的流级窗口增量。

```toml
h2_stream_window_increment = 131072
```

#### `h2_rst_stream_rate_per_second`

每秒发送的 RST_STREAM 帧的最大数量。

```toml
h2_rst_stream_rate_per_second = 100
```

#### `h2_rst_stream_burst`

在每秒速率限制之前允许的 RST_STREAM 突发大小。

```toml
h2_rst_stream_burst = 200
```

#### `h2_rst_stream_window_count`

滑动窗口内的 RST_STREAM 计数。

```toml
h2_rst_stream_window_count = 100
```

#### `h2_rst_stream_window_duration`

RST_STREAM 计数的滑动窗口持续时间（以秒为单位）。

```toml
h2_rst_stream_window_duration = 10
```

#### `h2_rst_stream_lifetime_count`

从连接建立开始计算的生命周期 RST_STREAM 计数。

```toml
h2_rst_stream_lifetime_count = 10000
```

#### `h2_rst_stream_pre_response_lifetime_count`

在响应发送之前计算的生命周期 RST_STREAM 计数。

```toml
h2_rst_stream_pre_response_lifetime_count = 1000
```

#### `h2_rst_stream_emitted_lifetime_count`

从连接建立开始计算的生命周期发出的 RST_STREAM 计数。

```toml
h2_rst_stream_emitted_lifetime_count = 10000
```

#### `h2_ping_rate_per_second`

每秒发送的 PING 帧的最大数量。

```toml
h2_ping_rate_per_second = 10
```

#### `h2_ping_burst`

在每秒速率限制之前允许的 PING 突发大小。

```toml
h2_ping_burst = 20
```

#### `h2_settings_rate_per_second`

每秒发送的 SETTINGS 帧的最大数量。

```toml
h2_settings_rate_per_second = 1
```

#### `h2_settings_burst`

在每秒速率限制之前允许的 SETTINGS 突发大小。

```toml
h2_settings_burst = 3
```

#### `h2_empty_data_rate_per_second`

每秒发送的空 DATA 帧的最大数量。

```toml
h2_empty_data_rate_per_second = 10
```

#### `h2_empty_data_burst`

在每秒速率限制之前允许的空 DATA 突发大小。

```toml
h2_empty_data_burst = 20
```

#### `h2_glitch_rate_per_second`

每秒允许的协议异常的最大数量。

```toml
h2_glitch_rate_per_second = 10
```

#### `h2_glitch_burst`

在每秒速率限制之前允许的协议异常突发大小。

```toml
h2_glitch_burst = 20
```

#### `h2_max_goaway_rate_per_second`

每秒发送的 GOAWAY 帧的最大数量。

```toml
h2_max_goaway_rate_per_second = 1
```

#### `h2_max_goaway_burst`

在每秒速率限制之前允许的 GOAWAY 突发大小。

```toml
h2_max_goaway_burst = 3
```

## HTTP Basic 认证

Sōzu 支持在监听器级别配置 HTTP Basic 认证。当启用时，所有到达该监听器的请求都需要提供有效的用户名和密码。

```toml
[[listener]]
address = "0.0.0.0:80"
protocol = "http"

[listener.auth]
method = "basic"
enabled = true
realm = "受限区域"
users = [
  { username = "admin", password = "password123" },
  { username = "user", password = "user456" }
]
```

- `listener.auth.method`：认证方法。仅支持 `basic`。
- `listener.auth.enabled`：是否启用认证。默认值为 `false`。
- `listener.auth.realm`：认证域。将显示在浏览器的认证对话框中。
- `listener.auth.users`：允许的用户名和密码列表。

当认证启用时，没有提供凭据或提供无效凭据的请求将收到 `401 Unauthorized` 响应，并包含 `WWW-Authenticate` 标头。

## 运行时补丁

Sōzu 支持在运行时应用配置补丁，而无需完全替换现有配置。这允许进行增量更改，例如添加新的后端服务器或更新路由规则。

### 补丁类型

- `add`：添加新的配置项。
- `remove`：删除现有的配置项。
- `update`：更新现有的配置项。
- `replace`：用新值替换现有的配置项。

### 补丁示例

添加新的后端服务器：

```json
{
  "action": "add",
  "path": "/clusters/api-cluster/backends",
  "value": {
    "address": "192.168.1.100:8080",
    "weight": 100,
    "max_connections": 1000
  }
}
```

更新现有后端服务器：

```json
{
  "action": "update",
  "path": "/clusters/api-cluster/backends",
  "value": {
    "address": "192.168.1.100:8080",
    "weight": 200,
    "max_connections": 2000
  }
}
```

删除后端服务器：

```json
{
  "action": "remove",
  "path": "/clusters/api-cluster/backends",
  "value": {
    "address": "192.168.1.100:8080"
  }
}
```

### 补丁限制

- 无法使用补丁添加新的监听器或前端。
- 无法使用补丁更改全局配置参数。
- 补丁操作是原子的。如果补丁的一部分失败，整个补丁将回滚。

## 指标

Sōzu 支持通过 StatsD 和 Prometheus 导出运行时指标。这些指标提供了关于代理性能、流量和健康的详细信息。

### StatsD 指标

Sōzu 支持将指标导出到 StatsD 兼容的指标后端，例如 Datadog、Librato 或自建 StatsD 服务器。

#### 指标类型

Sōzu 支持以下指标类型：

- `counter`：计数器。用于计数事件，例如请求数。
- `gauge`：仪表盘。用于表示当前值，例如活跃连接数。
- `timer`：计时器。用于测量持续时间，例如响应时间。
- `histogram`：直方图。用于表示值分布，例如响应时间分布。
- `meter`：计量器。用于测量速率，例如每秒请求数。

#### 指标命名

指标使用点分命名法。指标名称的格式为：

```
<statsd_prefix>.<component>.<metric_name>
```

例如：

```
sozu.proxy.requests.total
sozu.proxy.connections.active
sozu.proxy.requests.latency
```

#### 标签

Sōzu 支持将标签附加到指标。标签是键值对，用于对指标进行分组和筛选。

```toml
statsd_tags = ["env:production", "service:api", "region:us-east-1"]
```

#### 指标示例

以下是 Sōzu 导出的常见指标：

- `sozu.proxy.requests.total`：代理处理的请求总数。
- `sozu.proxy.requests.latency`：请求的延迟（毫秒）。
- `sozu.proxy.connections.active`：当前的活跃连接数。
- `sozu.proxy.connections.total`：代理处理的连接总数。
- `sozu.proxy.errors.total`：代理处理的错误总数。
- `sozu.proxy.errors.rate`：每秒错误率。
- `sozu.proxy.throttle.total`：代理拒绝的请求总数（由于速率限制）。
- `sozu.proxy.throttle.rate`：每秒拒绝率。
- `sozu.proxy.cache.hits`：代理缓存的命中数。
- `sozu.proxy.cache.misses`：代理缓存的未命中数。
- `sozu.proxy.cache.hit_rate`：代理缓存的命中率。
- `sozu.proxy.backend.requests.total`：代理转发到后端的请求总数。
- `sozu.proxy.backend.requests.latency`：请求转发到后端的延迟（毫秒）。
- `sozu.proxy.backend.connections.active`：当前到后端的活跃连接数。
- `sozu.proxy.backend.connections.total`：代理建立到后端的连接总数。
- `sozu.proxy.backend.errors.total`：代理转发到后端时发生的错误总数。
- `sozu.proxy.backend.errors.rate`：每秒到后端的错误率。

### Prometheus 指标

Sōzu 支持将指标导出到 Prometheus 兼容的指标后端，例如 Prometheus 服务器、Thanos 或 VictoriaMetrics。

#### 指标格式

Prometheus 指标使用 OpenMetrics 格式。指标通过 HTTP 端点暴露，通常位于 `/metrics` 路径下。

#### 指标类型

Prometheus 支持以下指标类型：

- `counter`：计数器。用于计数事件。
- `gauge`：仪表盘。用于表示当前值。
- `histogram`：直方图。用于表示值分布。
- `summary`：摘要。用于表示值的分位数。

#### 指标示例

以下是 Sōzu 导出的常见 Prometheus 指标：

```prometheus
# HELP sozu_proxy_requests_total 代理处理的请求总数
# TYPE sozu_proxy_requests_total counter
sozu_proxy_requests_total{method="GET",status="200",cluster="api-cluster"} 1000000
sozu_proxy_requests_total{method="POST",status="200",cluster="api-cluster"} 500000
sozu_proxy_requests_total{method="GET",status="404",cluster="api-cluster"} 10000

# HELP sozu_proxy_requests_latency_ms 请求延迟（毫秒）
# TYPE sozu_proxy_requests_latency_ms histogram
sozu_proxy_requests_latency_ms_bucket{le="1",cluster="api-cluster"} 500000
sozu_proxy_requests_latency_ms_bucket{le="5",cluster="api-cluster"} 900000
sozu_proxy_requests_latency_ms_bucket{le="10",cluster="api-cluster"} 980000
sozu_proxy_requests_latency_ms_bucket{le="25",cluster="api-cluster"} 999000
sozu_proxy_requests_latency_ms_bucket{le="50",cluster="api-cluster"} 999900
sozu_proxy_requests_latency_ms_bucket{le="100",cluster="api-cluster"} 1000000
sozu_proxy_requests_latency_ms_bucket{le="250",cluster="api-cluster"} 1000000
sozu_proxy_requests_latency_ms_bucket{le="500",cluster="api-cluster"} 1000000
sozu_proxy_requests_latency_ms_bucket{le="1000",cluster="api-cluster"} 1000000
sozu_proxy_requests_latency_ms_bucket{le="+Inf",cluster="api-cluster"} 1000000
sozu_proxy_requests_latency_ms_sum{cluster="api-cluster"} 5000000
sozu_proxy_requests_latency_ms_count{cluster="api-cluster"} 1000000

# HELP sozu_proxy_connections_active 当前活跃连接数
# TYPE sozu_proxy_connections_active gauge
sozu_proxy_connections_active{cluster="api-cluster"} 500

# HELP sozu_proxy_errors_total 错误总数
# TYPE sozu_proxy_errors_total counter
sozu_proxy_errors_total{cluster="api-cluster",error="timeout"} 100
sozu_proxy_errors_total{cluster="api-cluster",error="connection_refused"} 50
sozu_proxy_errors_total{cluster="api-cluster",error="internal_error"} 10

# HELP sozu_proxy_throttle_total 被限流的请求总数
# TYPE sozu_proxy_throttle_total counter
sozu_proxy_throttle_total{cluster="api-cluster"} 500

# HELP sozu_proxy_cache_hits 缓存命中总数
# TYPE sozu_proxy_cache_hits counter
sozu_proxy_cache_hits{cluster="api-cluster"} 800000

# HELP sozu_proxy_cache_misses 缓存未命中总数
# TYPE sozu_proxy_cache_misses counter
sozu_proxy_cache_misses{cluster="api-cluster"} 200000
```

### 指标配置参数

#### `metrics`

是否启用指标导出。默认值为 `false`。

```toml
metrics = true
```

#### `metrics_backend`

指标后端。支持 `statsd` 和 `prometheus`。默认值为 `statsd`。

```toml
metrics_backend = "prometheus"
```

#### `statsd_host`

StatsD 指标后端的主机。

```toml
statsd_host = "127.0.0.1"
```

#### `statsd_port`

StatsD 指标后端的端口。

```toml
statsd_port = 8125
```

#### `statsd_prefix`

StatsD 指标的前缀。默认值为 `sozu`。

```toml
statsd_prefix = "sozu"
```

#### `statsd_tags`

添加到所有 StatsD 指标的全局标签。

```toml
statsd_tags = ["env:production", "service:api", "region:us-east-1"]
```

#### `statsd_tags_separator`

用于在 StatsD 指标名称和标签之间分隔的字符。默认值为 `.`。

```toml
statsd_tags_separator = "."
```

#### `statsd_tags_key_separator`

用于在 StatsD 标签键和标签值之间分隔的字符。默认值为 `:`。

```toml
statsd_tags_key_separator = ":"
```

#### `statsd_tags_multi_separator`

用于在 StatsD 多个标签值之间分隔的字符。默认值为 `|`。

```toml
statsd_tags_multi_separator = "|"
```

#### `statsd_sample_rate`

指标采样的比率。默认值为 1.0（即无采样）。

```toml
statsd_sample_rate = 0.1
```

#### `statsd_udp_buffer_size`

StatsD 指标的 UDP 缓冲区大小（以字节为单位）。默认值为 4096。

```toml
statsd_udp_buffer_size = 8192
```

#### `statsd_udp_buffer_items`

在刷新到 StatsD 服务器之前的最大指标条目数。默认值为 100。

```toml
statsd_udp_buffer_items = 200
```

#### `statsd_flush_interval`

刷新到 StatsD 服务器的间隔（以秒为单位）。默认值为 10 秒。

```toml
statsd_flush_interval = 5
```

#### `prometheus_address`

Prometheus 指标端点的地址。默认值为 `0.0.0.0`。

```toml
prometheus_address = "0.0.0.0"
```

#### `prometheus_port`

Prometheus 指标端点的端口。默认值为 9100。

```toml
prometheus_port = 9100
```

#### `prometheus_path`

Prometheus 指标端点的路径。默认值为 `/metrics`。

```toml
prometheus_path = "/metrics"
```

#### `prometheus_bearer_token`

Prometheus 指标端点的 Bearer Token。

```toml
prometheus_bearer_token = "<token>"
```

## OpenTelemetry（traceparent 传递）

Sōzu 支持通过 OpenTelemetry 特性进行分布式追踪上下文的传递。当启用该特性时，Sōzu 将解析、生成并转发 `traceparent` 标头，并在访问日志中记录追踪标识符。

### 启用

使用 `opentelemetry` 特性构建 Sōzu：

```bash
cargo build --release --features opentelemetry
```

或在 `Cargo.toml` 中：

```toml
[dependencies]
sozu-lib = { path = "lib", features = ["opentelemetry"] }
```

### 工作原理

当启用 `opentelemetry` 特性时，Sōzu 将充当 HTTP/1.1 和 HTTP/2 前端的**追踪上下文传播器**。

1. **传入请求带有 `traceparent` 标头**：Sōzu 解析 W3C traceparent（格式：`00-<trace_id>-<parent_id>-<flags>`），保留 trace ID，为 Sōzu 跳生成新的 span ID，并在转发到后端之前重写标头。

2. **传入请求没有 `traceparent` 标头**：Sōzu 生成新的随机 trace ID 和 span ID，并在转发之前将 `traceparent` 标头注入请求。

3. **`tracestate` 标头**：如果存在有效的 `traceparent`，则保留。如果没有 `traceparent` 伴随它，则省略（按照 W3C 规范）。

4. **访问日志**：追踪上下文（trace ID、span ID、parent span ID）包含在访问日志条目和 protobuf `AccessLog` 消息中，启用 Sōzu 访问日志与可观测性平台中分布式追踪之间的关联。

### 访问日志字段

当启用 OpenTelemetry 时，访问日志包含：

| 字段 | 格式 | 描述 |
|------|------|------|
| `trace_id` | 32 个十六进制字符 | W3C trace ID（传递或生成） |
| `span_id` | 16 个十六进制字符 | Sōzu 为此跳生成的 span ID |
| `parent_span_id` | 16 个十六进制字符或 `-` | 来自传入 `traceparent` 的 parent span ID（如果存在） |

### 范围外

`opentelemetry` 特性是有意窄化的。它不：

- 将 `opentelemetry`、`opentelemetry-sdk`、`opentelemetry-otlp` 或 `tracing-opentelemetry` 作为依赖项拉入。
- 发出 spans。没有 `Span::start`/`Span::end`，没有进程内导出器，没有 OTLP/gRPC 客户端。使用访问日志管道将每请求追踪标识符提供给 Jaeger、Tempo、Honeycomb 或 Datadog。
- 尊重传入 `traceparent` 的采样标志位。今天重写的标头总是以 `-01`（已采样）发出。
- 提供运行时配置。该特性仅在编译时选择。

真正的 span 模型和 OTLP 导出器被单独跟踪，并将作为自己的特性标志落地，而不是扩展 `opentelemetry` 的范围。

## PROXY 协议

当网络流通过代理时，后端服务器将只看到代理用作客户端地址的 IP 地址和端口。真实的源 IP 地址和端口将只由代理看到。由于此信息对于日志记录、安全性等很有用，因此开发了 [PROXY 协议](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt) 来将其传输到后端服务器。使用此协议，在连接到后端服务器后，代理将首先发送一个指示客户端 IP 地址和端口的标头，以及代理的接收 IP 地址和端口，然后发送来自客户端的流。

Sōzu 支持 `PROXY 协议` 的 **版本 2**，有以下三种配置：

- **"send" 协议**：Sōzu 在 TCP 代理模式下，将向后端服务器发送标头
- **"expect" 协议**：Sōzu 从代理接收标头，解释它用于自己的日志记录和指标，并在 HTTP 转发标头中使用它
- **"relay" 协议**：Sōzu 在 TCP 代理模式下，可以接收标头，并将其传输到后端服务器

更多信息请参阅：[proxy-protocol 规范](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt)

### 配置 Sōzu 以 _期望_ PROXY 协议标头

配置面向客户端的连接，在从套接字读取客户端发送的任何字节之前接收 PROXY 协议标头。

```
                           发送 PROXY                    期望 PROXY
                           协议标头                       协议标头
    +--------+
    | client |             +---------+                   +------------+      +-----------+
    |        |             | 代理    |                   | Sōzu       |      | 上游     |
    +--------+  ---------> | 服务器  |  ---------------> |            |------| 服务器     |
   /        /              |         |                   |            |      |           |
  /________/               +---------+                   +------------+      +-----------+
```

它支持 HTTP、HTTPS 和 TCP 代理。

_配置：_

```toml
[[listener]]
address = "0.0.0.0:80"
expect_proxy = true
```

### 配置 Sōzu 以向后端上游 _发送_ PROXY 协议标头

在任何连接到集群中声明的后端的连接上发送 PROXY 协议标头。

```
                           发送 PROXY
    +--------+             协议标头
    | client |             +---------+                +-----------------+
    |        |             | Sōzu    |                | 代理/上游     |
    +--------+  ---------> |         |  ------------> | 服务器          |
   /        /              |         |                |                 |
  /________/               +---------+                +-----------------+
```

_配置：_

```toml
[[listener]]
address = "0.0.0.0:81"

[cluster]
name = "NameOfYourTcpCluster"
send_proxy = true
frontends = [
  { address = "0.0.0.0:81" }
]
```

注意：仅适用于 TCP 集群（HTTP 和 HTTPS 代理将使用转发标头）。

### 配置 Sōzu 以 _中继_ PROXY 协议标头到上游

Sōzu 将从客户端连接接收 PROXY 协议标头，检查其有效性，然后将其转发到上游后端。这允许反向代理链在不丢失客户端连接信息的情况下工作。

```
                           发送 PROXY                    期望 PROXY               发送 PROXY
                           协议标头                       协议标头                 协议标头
    +--------+
    | client |             +---------+                   +------------+             +-------------------+
    |        |             | 代理    |                   | Sōzu       |             | 代理/上游         |
    +--------+  ---------> | 服务器  |  ---------------> |            | +---------> | 服务器            |
   /        /              |         |                   |            |             |                   |
  /________/               +---------+                   +------------+             +-------------------+
```

_配置：_

```toml
[[listener]]
address = "0.0.0.0:80"
expect_proxy = true

[cluster]
name = "NameOfYourCluster"
send_proxy = true
frontends = [
  { address = "0.0.0.0:80" }
]
```
