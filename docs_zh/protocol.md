# Sōzu Unix 套接字协议

本文档描述了 Sōzu 主进程与其 CLI 客户端之间通过主 TOML 中配置的 `command_socket` Unix 域套接字进行通信时使用的线路格式。参考客户端是处于 client 模式下的 `sozu` 二进制本身；第三方客户端可使用任何支持 `prost` 兼容代码生成器的语言，依据 protobuf 模式编写。

该文档涉及 [#1155](https://github.com/sozu-proxy/sozu/issues/1155)。

> **状态**：结构参考。`command/src/command.proto` 中的 protobuf 模式是权威来源；本文档涵盖了模式未直接捕获的帧格式、生命周期和认证规范。线路级的字段编号和消息结构最好直接从 [`command/src/command.proto`](../command/src/command.proto) 中阅读。

## 概览

- **传输层**：Unix 域流式套接字（`AF_UNIX`，`SOCK_STREAM`），默认权限模式为 `0o600`。
- **认证**：在 `accept(2)` 时进行 `SO_PEERCRED` UID 检查（以及可选的 `command_allowed_uids` 白名单）。套接字文件权限本身是一个粗粒度的门控；通过内核级访问控制的 UID 仍会面临白名单检查。
- **帧格式**：8 字节小端长度前缀，后跟 protobuf 消息。长度值包含前缀本身。
- **消息类型**：`Request`（客户端 → 主进程）和 `Response`（主进程 → 客户端），二者均在 [`command/src/command.proto`](../command/src/command.proto) 中定义为 `oneof` 类型。
- **文件描述符传递**：独立的边带通道使用 `SCM_RIGHTS`（参见 `command/src/scm_socket.rs`）在热升级期间传递监听器文件描述符。常规 CLI 流量不使用 SCM。

## 线路帧格式

线路上的每一帧为：

```
+--------------------------+----------------------+
| length: u64 little-endian| protobuf payload     |
| (8 bytes)                | (length − 8 bytes)   |
+--------------------------+----------------------+
```

- `length` 占 `sizeof(usize)` 个字节 —— 在所有受支持平台上均为 8 字节（`x86_64-unknown-linux-gnu`、`aarch64-unknown-linux-gnu`、`x86_64-unknown-freebsd`）。
- `length` 是**包括**前缀本身的**总**帧长度。一个 100 字节的 protobuf 正文对应 `length = 108`。
- 接收方通过 `max_buffer_size`（默认 2 MiB，可通过全局 TOML 键 `max_command_buffer_size` 配置）限制 `length`，以防止分配压力攻击。声明长度超出上限的帧将被拒绝并返回 `MessageTooLarge`，同时关闭通道。

参考 Rust 实现位于 [`command/src/channel.rs`](../command/src/channel.rs)；辅助函数 `Channel::write_message`、`Channel::read_message` 以及常量 `delimiter_size()` 是入口点。

## 消息类型

### 客户端 → 主进程（`Request`）

```
message Request {
  oneof request_type {
    AddCluster                add_cluster                = 1;
    RemoveCluster             remove_cluster             = 2;
    AddBackend                add_backend                = 3;
    AddCertificate            add_certificate            = 16;
    ReplaceCertificate        replace_certificate        = 17;
    RemoveCertificate         remove_certificate         = 18;
    AddHttpListener           add_http_listener          = 32;
    AddHttpsListener          add_https_listener         = 33;
    UpdateHttpListenerConfig  update_http_listener       = 34;
    AddHttpFrontend           add_http_frontend          = 36;
    SubscribeEvents           subscribe_events           = 41;
    SetMaxConnectionsPerIp    set_max_connections_per_ip = 50;
    SetHealthCheck            set_health_check           = 52;
    // … 完整列表请参见 command/src/command.proto
  }
  string id = 99;  // 请求关联 ID（在 Response 中原样回显）
}
```

`id` 字段由操作者提供（通常建议使用 UUIDv4）。主进程会在每条与此请求关联的响应中回显该 ID。

### 主进程 → 客户端（`Response`）

```markdown
message Response {
  string id            = 1;  // 回显自 Request.id
  ResponseStatus status = 2; // OK, FAILURE, PROCESSING
  string message       = 3;  // 自由格式的诊断信息
  ResponseContent content = 4;  // oneof — 参见 command.proto
}
```

当请求扇出到所有工作节点，且主节点等待每个工作节点的回复时，会发送 `ResponseStatus::PROCESSING`。最终的响应为 `OK` 或 `FAILURE`。

## 生命周期

### 连接

```
client                                      master
  | --- connect(unix:/var/lib/sozu.sock) ----> |
  | <-- accept (内核 SO_PEERCRED 捕获 UID)      |
  | <-- master 应用 command_allowed_uids 规则    |
```

如果连接方的 UID 不在 `command_allowed_uids` 中（当该配置被设置时），主节点会立即关闭套接字。

### 请求 / 响应

```
client                                      master
  | --- Request{id="...", oneof=AddCluster}  -> |
  | <-- Response{id="...", status=PROCESSING}   |
  | <-- Response{id="...", status=OK}            |
```

某些动词会扇出到 N 个工作节点。主节点为每个工作节点的回复发送一个 `status=PROCESSING`，并在聚合完成后发送一个最终的 `OK` / `FAILURE`。

### 订阅事件（服务器推送）

```
client                                      master
  | --- Request{id="X", oneof=SubscribeEvents} -> |
  | <-- Response{id="X", status=OK}                |
  | <-- Response{id="evt-N", content=Event{...}}   |
  | <-- Response{id="evt-N+1", content=Event{...}} |
  | … 无限事件流                                   |
```

事件投递使用相同的帧格式。审计日志系列发出的 22 种 `EventKind` 变体（`CLUSTER_ADDED`、`FRONTEND_REMOVED`、`HEALTH_CHECK_HEALTHY`、`MAIN_UPGRADED` 等）在 [`doc/observability.md`](observability.md) 中描述。

### 断开连接

任意一方均可关闭底层套接字。客户端放弃的正在处理中的（PROCESSING）扇出请求仍会在主节点侧完成（工作节点的扇出无法中途取消），但响应会被丢弃。

## 自动生成参考（计划中）

后续提交可以针对 `command/src/command.proto` 运行 `protoc-gen-doc`，以便将自动生成的 `command/src/proto/command.rs` 与一份全新的线路层参考文档配对使用。

在此之前，规范的线路层参考是 `command/src/command.proto` 本身；本文档涵盖了模式中不可见的帧格式、生命周期和认证信息。

## 示例

### 伪代码（Python）

```python
import socket
import struct
from sozu_command_pb2 import Request, AddCluster, Cluster, Response

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect("/var/lib/sozu.sock")

req = Request(
    id="my-request-1",
    add_cluster=AddCluster(cluster=Cluster(cluster_id="example", protocol="HTTP")),
)
body = req.SerializeToString()
length = 8 + len(body)                    # 分隔符为 8 字节
s.sendall(struct.pack("<Q", length) + body)  # 小端序 u64 前缀

# 接收响应直到达到终止状态
while True:
    prefix = s.recv(8)
    (length,) = struct.unpack("<Q", prefix)
    body = b""
    while len(body) < length - 8:
        body += s.recv(length - 8 - len(body))
    resp = Response()
    resp.ParseFromString(body)
    print(resp)
    if resp.status in (Response.OK, Response.FAILURE):
        break
```

`sozu_command_pb2` 模块通过 `protoc --python_out=...` 从 `command.proto` 生成；请将模式固定到特定的 Sōzu 版本，以避免升级过程中的不匹配。

### Rust

可以直接在 `sozu-command-lib`（二进制程序使用的同一个 crate）之上构建类型化的 Rust 客户端。对于外部项目，模式为：依赖 `sozu-command-lib`，在 `UnixStream` 上构建 `Channel<Request, Response>`，调用 `write_message` / `read_message`。该 crate 已暴露 `Channel::generate(buffer_size, max_buffer_size)` 以及 prost 生成的 `Request` / `Response` 类型。

## 加固 / 可观测性

- **分配压力**：`max_command_buffer_size`（默认 2 MiB）限制每个通道的缓冲区大小。
- **UID 白名单**：`command_allowed_uids: Vec<u32>` 在套接字边界拒绝不在白名单中的 UID。
- **审计日志 v2** 记录每个特权变更，带有操作者属性（通过 `SO_PEERCRED` + `/proc/<pid>/stat` 获取 UID/GID/PID/comm）以及用于重放关联的 16 位十六进制 SHA-256 指纹。参见 [`doc/observability.md`](observability.md) 中的控制平面审计日志部分。
- **套接字文件上的模式 0o600** 在内核级别阻止跨 UID 访问。当多个守护进程以同一 UID 运行时，与 `command_allowed_uids` 结合使用以实现纵深防御。

## 相关

- [`command/src/command.proto`](../command/src/command.proto) — 模式源头
- [`command/src/channel.rs`](../command/src/channel.rs) — Rust 帧实现
- [`command/src/scm_socket.rs`](../command/src/scm_socket.rs) — 用于热升级的 SCM_RIGHTS 文件描述符传递
- [`bin/src/command/server.rs`](../bin/src/command/server.rs) — 主控端命令服务器
- [`bin/src/command/LIFECYCLE.md`](../bin/src/command/LIFECYCLE.md) — 监督者生命周期、审计日志信封
- [`doc/observability.md`](observability.md) — 审计日志模式 + 保留策略
- [`doc/upgrade/1.x-to-2.0.md`](upgrade/1.x-to-2.0.md) — v1.1.x → v2.0.0 迁移指南