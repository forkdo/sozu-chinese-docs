# 入门

## 设置 Rust

确保安装了最新稳定版的 `Rust`。
我们建议为此使用 [rustup][ru]。

完成此操作后，`Rust` 应该已完全安装。

## 设置 Sōzu

### 安装

`sozu` 发布在 [crates.io][cr] 上。

要安装它们，您只需执行 `cargo install sozu`。

它们将被构建并放在 `~/.cargo/bin` 文件夹中。

### 从源代码构建

构建 sozu 可执行文件和命令行：

`cd bin && cargo build --release --locked`

> `--release` 参数通知 cargo 在编译 sozu 时打开优化。
> 仅使用 `--release` 制作生产版本。
>
> `--locked` 标志告诉 cargo 坚持使用 `Cargo.lock` 中指定的依赖项版本
> 从而防止依赖项中断。

### 在 NixOS 上运行

Sōzu 已打包进 [nixpkgs][nx]；最新版本位于 `nixos-unstable` 频道。

无需安装即可试用：

```bash
nix-shell -p sozu --run "sozu --version"
```

安装到用户 profile：

```bash
nix profile install nixpkgs#sozu
```

或将其添加到 NixOS 系统配置中：

```nix
environment.systemPackages = [ pkgs.sozu ];
```

> 上游 derivation 目前在 `x86_64` 之外的平台上被标记为 `broken`。
> 请在 x86_64 的 NixOS 主机上运行 Sōzu，或从源码构建。
>
> 该 derivation 不随附 `services.sozu` NixOS 模块。若要将
> Sōzu 作为守护进程运行，请编写一个指向您的
> `config.toml` 的 `systemd.services.sozu` 单元；参见[配置参考](./configure.md)。

### Cargo 特性

工作区发布的 Cargo 特性用于调整行为并选择 TLS 加密提供方。加密提供方的选择
详见下文的[选择加密提供方](#choosing-a-crypto-provider)；四个提供方
（`crypto-ring`、`crypto-aws-lc-rs`、`crypto-openssl`、`fips`）在运行时通过
`lib/src/crypto.rs::default_provider()` 中的优先级链互斥。

| 特性 | Crate(s) | 效果 |
|---------|----------|--------|
| `tolerant-http1-parser` | `lib`、`bin` | 通过 `kawa/tolerant-parsing` 放宽 H1 解析。 |
| `simd` | `lib`、`bin` | 启用 `kawa/simd` SIMD 加速。 |
| `splice` | `lib`、`bin` | 仅限 Linux，通过 `splice(2)` 进行零拷贝 TCP 转发。默认每个会话每个方向 64 KiB 内核管道；可通过 `splice_pipe_capacity_bytes` 调整（上限为 `/proc/sys/fs/pipe-max-size`）。仅适用于 `Protocol::TCP` 监听器。 |
| `opentelemetry` | `lib`、`bin` | 编译进 OpenTelemetry 导出。 |
| `logs-debug` | 全部 | 编译进 `DEBUG` 日志（否则 release 会剥离它们）。 |
| `logs-trace` | 全部 | 编译进 `TRACE` 日志（否则 release 会剥离它们）。 |
| `e2e-hooks` | `lib` | 测试注入 API —— 切勿在生产构建中启用。 |

每个 crate 的权威列表记录在各自的 `Cargo.toml` 中
（`lib/Cargo.toml`、`bin/Cargo.toml`、`command/Cargo.toml`）；目前 `cargo build
--all-features --locked` 在整个工作区中可以成功构建。

## HTTP/2 支持

Sōzu 开箱即用地支持 HTTP/2，大多数用例无需额外配置。

**前端（客户端 → Sōzu）：** 所有 HTTPS 监听器上自动可用 HTTP/2。
客户端在 TLS 握手期间通过 ALPN 协商协议。要在特定监听器上禁用 HTTP/2，
请设置 `alpn_protocols = ["http/1.1"]`。

**后端（Sōzu → 服务器）：** 默认情况下，Sōzu 与后端使用 HTTP/1.1 通信。要对后端连接
使用明文 HTTP/2（h2c），请在集群上设置 `http2 = true`：

```toml
[clusters.MyCluster]
protocol = "http"
http2 = true
frontends = [
  { address = "0.0.0.0:8443", hostname = "app.example.com", certificate = "cert.pem", key = "key.pem", certificate_chain = "chain.pem" }
]
backends = [
  { address = "127.0.0.1:8080" }
]
```

请确保全局配置段中的 `buffer_size` 至少为 **16393**（16384 最大 H2 帧 + 9 字节头）。

您也可以使用 CLI 在运行时切换 HTTP/2：

```bash
sozu cluster h2 enable --id MyCluster
sozu cluster h2 disable --id MyCluster
```

**安全性：** Sōzu 内置了针对 HTTP/2 连接的洪水检测，可防御 Rapid Reset
（CVE-2023-44487）、CONTINUATION flood（CVE-2024-27316）以及其他协议滥用向量。
阈值可按监听器配置 —— 详见[配置参考](./configure.md#h2-flood-detection-thresholds)。

**优先级：** Sōzu 实现了 RFC 9218 可扩展优先级。带有 `priority` 头（`u=N, i` 格式）的
流按紧急程度调度，确保高优先级响应优先发送。

所有 HTTP/2 选项请参阅[配置参考](./configure.md)，开发者视角的实现细节请参阅
[H2 多路复用内部机制](./h2_mux_internals.md)。

### Choosing a crypto provider（选择加密提供方）

Sōzu 使用 [Rustls](https://github.com/rustls/rustls) 进行 TLS，并支持多种加密后端，
在编译时通过特性标志选择。一次只能启用一个加密提供方。

| 特性 | 后端 | 说明 |
|---------|---------|-------|
| `crypto-ring`（默认） | [ring](https://github.com/briansmith/ring) | 无需额外系统依赖 |
| `crypto-aws-lc-rs` | [AWS-LC](https://github.com/aws/aws-lc-rs) | 支持后量子密钥交换。需要 `cmake` |
| `crypto-openssl` | [OpenSSL](https://www.openssl.org/)（通过 rustls-openssl） | 使用系统 OpenSSL。需要 `cmake` 和 OpenSSL 开发头文件 |
| `fips` | FIPS 模式下的 AWS-LC | 符合 FIPS 140-3。需要 `cmake` |

```bash
# 默认构建（ring）
cd bin && cargo build --release --locked

# 带后量子支持的 AWS-LC
cd bin && cargo build --release --locked --no-default-features --features crypto-aws-lc-rs

# OpenSSL 后端
cd bin && cargo build --release --locked --no-default-features --features crypto-openssl

# FIPS 140-3 合规（FIPS 模式下的 aws-lc-rs）
cd bin && cargo build --release --locked --no-default-features --features fips
```

> 当使用 `--no-default-features` 时，`jemallocator` 分配器也会被禁用。
> 如需重新启用，请显式添加：`--features jemallocator,crypto-aws-lc-rs`。
>
> 在 FreeBSD 和 NetBSD 上，即便使用默认特性集也绝不会链接内置的 jemalloc：
> 在这些目标平台上，`jemallocator` Cargo 依赖会在清单层面被过滤掉，因为 libc 已将
> jemalloc 作为系统 `malloc(3)` 提供（FreeBSD 7.0+、NetBSD 5.0+）。Sōzu 在这些平台上
> 使用系统分配器，`--version` 横幅会显示 `-jemallocator` 以反映实际的链接图。
>
> 通过标准的 `MALLOC_CONF` 环境变量调优 libc 的 jemalloc。几个与反向代理相关的实例：
>
> ```sh
> # 加固：清零已释放区域，OOM 时中止，错误配置时快速失败。
> MALLOC_CONF="junk:true,abort_conf:true,confirm_conf:true,xmalloc:true"
>
> # 后台清理线程 + 与 worker 数量匹配的 arena 数量。
> MALLOC_CONF="background_thread:true,narenas:4"
>
> # 在内存紧张的主机上更快地清理 dirty/muzzy 页（默认 10 秒 = 10000 毫秒）。
> MALLOC_CONF="dirty_decay_ms:1000,muzzy_decay_ms:1000"
>
> # 选择启用堆分析，在 SIGPROF 或 `mallctl prof.dump` 时转储。
> # 需要 libc jemalloc 以 `--enable-prof` 构建（FreeBSD/NetBSD 默认开启；
> # 参见 `man malloc.conf(5)` / `man jemalloc(3)`）。
> MALLOC_CONF="prof:true,prof_active:false,prof_prefix:/tmp/jeprof,lg_prof_sample:19"
>
> # 退出时打印统计信息（仅调试 —— 开销较高）。
> MALLOC_CONF="stats_print:true"
> ```
>
> NetBSD 与 FreeBSD 使用相同的选项名；两者都遵循上游 jemalloc 5.x 语法
> （FreeBSD 上 `man malloc.conf(5)`，NetBSD 上 `man jemalloc(3)`）。

[ru]: https://rustup.rs
[cr]: https://crates.io/
[nx]: https://search.nixos.org/packages?channel=unstable&query=sozu
