# 测试策略

Sōzu 使用分层测试战略。每个策略针对不同的验证目标：

## 分层

| 层           | 工具      | 目标                                        | 特点                           |
| ------------ | --------- | ------------------------------------------- | ------------------------------ |
| 单元测试     | cargo test | 单个函数/组件的行为                     | 快速、隔离、确定性             |
| 集成测试     | cargo test | 多个组件交互                                   | 更慢、集成、真实配置     |
| 端到端测试   | Nextest    | 完整部署场景                                   | 最慢、模拟基础设施     |
| 负载测试     | k6、wrk   | 吞吐量 / 延迟 / 资源使用                        | 性能基准                       |
| 模糊测试     | cargo-fuzz | 协议处理鲁棒性                                 | 随机输入、漏洞检测         |
| 文档测试     | cargo test --doc | 文档代码片段                                    | 保持示例更新           |
| 形式化规范   | Proptest  | 不变式                                       | 属性测试                     |
| 确定性仿真   | `cargo run` | 协议/ mux 行为                                | 重现、可调试                 |
| 跨版本升级   | Nextest    | 升级正确性                                    | 版本迁移                 |

## 1. 单元测试（`#[test]`）

### 定位

单个函数或模块。没有网络、没有进程间通信。

### 规则

- 每个公有的 `pub fn` / `pub struct` 应有单元测试。
- 使用真实的输入数据和边缘案例。
- 对协议解析器进行**输入/输出**测试（十六进制 blob ↔ 解析结构）。
- 对错误路径进行错误分类测试。
- 保持快且无 I/O。

### 示例

```rust
#[test]
fn test_parse_valid_request() {
    let input = b"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n";
    let result = parse_http_request(input);
    assert!(result.is_ok());
    let req = result.unwrap();
    assert_eq!(req.method, Method::GET);
    assert_eq!(req.path, "/");
}

#[test]
fn test_rejects_malformed_request() {
    let input = b"GARBAGE\r\n";
    assert!(parse_http_request(input).is_err());
}
```

## 2. 集成测试（`#[tokio::test]` + Nextest）

### 定位

组件组合。使用真实协议实现，
但没有完整的 worker 启动。

### 规则

- 测试组件间接口。
- 使用 `tempfile` 处理文件系统操作。
- 测试事件订阅、集群配置和后端选择。
- 对长生命周期状态（如连接池）使用 `#[tokio::test(flavor = "current_thread")]`。

### 示例

```rust
#[tokio::test(flavor = "current_thread")]
async fn test_backend_selection_round_robin() {
    let backend1 = Address::new("127.0.0.1", 3000);
    let backend2 = Address::new("127.0.0.1", 3001);

    let mut pool = BackendPool::new(vec![backend1, backend2]);
    assert_eq!(pool.next().unwrap(), backend1);
    assert_eq!(pool.next().unwrap(), backend2);
    assert_eq!(pool.next().unwrap(), backend1); // 轮回到第一个
}
```

## 3. 端到端测试（Nextest）

### 定位

完整系统行为。启动真实的 Sōzu worker，
连接前端，发送请求，验证结果。

### 架构

所有 E2E 测试使用固定的 Nextest profile：

```toml
# Cargo.toml
[profile.test]
opt-level = 1
debug = true
```

这是必需的，因为 Nextest 在 Linux 上强制执行
`sandbox.vsyscall = emulate`，
这使 `gettimeofday(2)` 通过虚页失败——
`get_time_us()` 路径。优化构建完全省略了时间函数调用，
因此从不在测试中崩溃；debug 构建
默认启用它们，所以必须关闭优化才能在此平台上运行
测试套件。

测试结构：

```
e2e/tests/
├── helpers/           # 公共助手
│   ├── runner.rs      # 管理 worker 生命周期
│   ├── clients/       # HTTP/TCP/WS 客户端
│   └── proto.rs       # 原型构造
├── common/            # 共享 fixture
│   ├── config.rs      # 配置生成器
│   └── backends.rs    # 测试后端
├── protocol/          # 协议特定测试
├── upgrade/           # 升级相关
└── <feature>/         # 功能测试
```

### 规则

- **每个 `#[test]` 一个测试文件**。不要将不相关的 E2E 测试聚集
  在一起——如果测试 A 修改集群配置，
  测试 B 依赖该集群将被污染。
- **显式隔离 worker 配置**。使用 `--config` 标志
  为每个测试启动干净的 worker。
- **使用 Nextest 的 `--test-threads 1`**。E2E 测试共享
  端口和资源；不能并行运行。
- **测试健康检查、重定向、答案模板和故障转移**。
- **测试覆盖矩阵**（`e2e/COVERAGE.md`）追踪已测试
  的配置组合。

### 示例

```rust
use sozu_lib::command::SōzuCommand;

#[nextest::test]
async fn test_http_cluster_routing() {
    let mut runner = TestRunner::start_test_cluster(1).unwrap();
    let client = HttpTestClient::new(runner.frontend_addr());

    // 发出请求
    let response = client.get("/").await.unwrap();
    assert_eq!(response.status(), 200);

    // 关闭后端并验证 fail-open
    runner.backends[0].kill().await;
    let response = client.get("/").await.unwrap();
    assert_eq!(response.status(), 200); // fail-open 到另一个后端
}
```

## 4. 负载测试（k6 / wrk）

### 定位

吞吐量、延迟和资源的性能基准。

### 规则

- 使用 wrk 进行快速基准（简单延迟分布）。
- 使用 k6 进行复杂场景（逐步增加负载）。
- 始终报告：并发连接数、每秒请求数、p50/p95/p99 延迟。
- 记录机器规格。
- 对回归测试使用固定参数集。

### 示例

```bash
# 用 wrk 测试
wrk -t12 -c400 -d60s http://localhost:8080/

# 用 k6 测试
k6 run load-test.js
```

## 5. 模糊测试

### 定位

检测协议处理中的漏洞。

### 规则

- 对每个协议解析器维护一个单独的对冲二进制文件。
- 每天用 fuzzilli 运行。
- 使用真实流量样本作为种子。
- 捕获崩溃并使用确定性复现测试修复。
- 模糊覆盖率数据存储在 `fuzz/coverage/`。

### 示例

```bash
# 构建对缓冲
cargo +nightly fuzz run h2_frame_parser

# 运行对缓冲
cargo +nightly fuzz run h2_frame_parser -- -max_len=4096 -jobs=8
```

## 6. 形式化规范（Proptest）

### 定位

验证协议不变式。

### 规则

- 使用 proptest 代替普通 `#[test]`。
- 定义数据生成器用于测试用例（流 ID、帧类型、头等）。
- 测试关键属性：
  - 流 ID 单调递增
  - 头帧始终遵循连接 preface
  - 流量控制窗口不溢出
- 生成器必须产生有效和无效输入。

### 示例

```rust
proptest! {
    #[test]
    fn test_stream_id_monotonic(incoming_streams in 0..1000u32) {
        let mut context = H2Context::default();
        let mut stream_id = 0;
        for _ in 0..incoming_streams {
            stream_id += 2; // 服务器流必须是偶数
            assert!(stream_id.is_some());
        }
    }
}
```

## 7. 确定性仿真

### 定位

重现和调试协议/mux 行为。

### 架构

- 仿真器在 `tools/simulator.rs` 中。
- 输入是一个 JSON 描述符（连接、事件、预期结果）。
- 输出是时间序列跟踪（日志、指标、连接状态）。
- 使用相同的 protobuf 消息传输格式。
- 集成到 `tools/dev.sh` 和 VSCode `launch.json`。

### 规则

- 每个仿真场景有独立的 JSON 文件。
- 包含边界案例（连接重置、超时、突发流量）。
- 使用 `--seed` 标志复现问题。
- 对回归测试使用固定种子。

### 示例

```bash
# 运行仿真
cargo run --bin simulator -- --scenario scenarios/rst_stream_edge_case.json

# 带种子复现
cargo run --bin simulator -- --scenario scenarios/issue_123.json --seed 42
```

## 8. 跨版本升级测试

### 定位

确保升级路径的安全和正确性。

### 架构

- 在 `tools/dev.sh` 中集成测试框架。
- 使用真实二进制文件（来自 CI）。
- 版本通过 Git 标签标识。
- 测试升级前/后的集群配置和事件一致性。
- 记录升级期间的事件顺序。

### 规则

- 始终测试从上一主要版本升级。
- 验证集群、监听器和后端状态。
- 检查事件总线是否产生预期事件。
- 测试升级失败时的回滚路径。
- 使用 `UpgradeTester::from_tag(...)` 选择版本。

### 示例

```rust
use sozu_upgrade_testing::UpgradeTester;

#[tokio::test]
async fn test_upgrade_1_1_to_2_0() {
    let mut tester = UpgradeTester::from_tag("1.1.1").await.unwrap();
    tester.start().await;

    // 添加集群和后端
    tester.add_cluster("my-cluster").await;
    tester.add_backend("127.0.0.1", 3000).await;

    // 升级
    tester.upgrade_to_tag("2.0.0").await;

    // 验证配置一致性
    tester.assert_cluster_exists("my-cluster").await;
    tester.assert_backend_up("127.0.0.1", 3000).await;

    // 检查事件
    let events = tester.get_events().await;
    assert!(events.iter().any(|e| e.kind == "upgrade_success"));
}
```

## 9. 持续集成

### GitHub Actions

- **测试矩阵**：Linux (x64/ARM)、macOS、Windows。
- **并行测试**：单元测试并行，E2E 测试顺序。
- **覆盖率报告**：使用 `cargo-llvm-cov`。
- **模糊测试**：每天运行，上传 corpus。
- **升级测试**：每个 PR 运行跨版本升级矩阵。

### 本地开发

```bash
# 运行所有测试
make test

# 运行特定类别
make test-unit     # 仅单元测试
make test-e2e      # 仅 E2E
make test-fuzz     # 仅模糊测试
make test-upgrade  # 仅升级测试

# 带覆盖率
make coverage
```

## 交叉引用

- [`udp_simulation.md`](udp_simulation.md) —— UDP 多路复用仿真详情。
- [`testing.md`](testing.md) —— 本测试策略。
- [`CLAUDE.md`](../CLAUDE.md) —— 代理约定包括测试指南。
- `e2e/COVERAGE.md` —— 功能覆盖矩阵。
