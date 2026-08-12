# 升级 E2E 测试指南

本目录包含端到端测试，用于验证 Sōzu worker 的运行时升级过程。
测试确保在滚动升级期间集群状态和事件总线的兼容性。

## 概述

`upgrade_e2e_tests.rs` 中的 E2E 升级测试验证了：

- Worker 进程可以在不丢失集群状态的情况下升级
- 升级后的 worker 可以继承事件订阅
- 集群配置在升级前后一致
- 连接跟踪在升级后正确恢复

## 架构

测试使用专用的 `sozu_upgrade_testing` crate（`tools/sozu-upgrade-testing/`），它提供：

- `UpgradeTester` —— 管理多版本 worker 生命周期的助手
- `WorkerLauncher` —— 以特定 Git 标签启动 worker
- `EventLogger` —— 捕获和验证升级期间的事件
- `ClusterStateVerifier` —— 验证升级前后的集群配置

## 关键测试场景

### 1. 基本升级
验证从旧版本到新版本的干净升级。

```rust
#[tokio::test]
async fn test_basic_upgrade() {
    let mut tester = UpgradeTester::from_tag("1.1.1").await.unwrap();
    tester.start().await;
    
    // 添加测试集群
    tester.add_cluster("test-cluster").await;
    
    // 执行升级
    tester.upgrade_to_tag("2.0.0").await;
    
    // 验证集群仍然存在
    tester.assert_cluster_exists("test-cluster").await;
}
```

### 2. 滚动升级
验证一次升级一个 worker 的滚动升级。

```rust
#[tokio::test]
async fn test_rolling_upgrade() {
    let mut tester = UpgradeTester::with_workers(3).await.unwrap();
    tester.start().await;
    
    // 按顺序升级每个 worker
    for i in 0..3 {
        tester.upgrade_worker(i, "2.0.0").await;
        tester.assert_cluster_consistency().await;
    }
}
```

### 3. 回滚测试
验证升级到新版本后可以回滚到旧版本。

```rust
#[tokio::test]
async fn test_rollback() {
    let mut tester = UpgradeTester::from_tag("1.1.1").await.unwrap();
    tester.start().await;
    
    // 升级到新版本
    tester.upgrade_to_tag("2.0.0").await;
    
    // 验证新版本正常工作
    tester.assert_version("2.0.0").await;
    
    // 回滚到旧版本
    tester.rollback_to_tag("1.1.1").await;
    
    // 验证集群状态已恢复
    tester.assert_cluster_exists("test-cluster").await;
}
```

## 测试基础设施

### 配置文件

每个测试场景使用独立的 TOML 配置：

```toml
# e2e/tests/upgrade/fixtures/test_upgrade.toml
id = "upgrade-test"

[[clusters]]
id = "test-cluster"
protocol = "http"
frontends = [{ address = "127.0.0.1:8080" }]
backends = [{ address = "127.0.0.1:3000" }]
```

### 版本管理

测试使用 Git 标签来识别版本：

- `1.1.1` —— 基础版本
- `2.0.0` —— 目标版本
- 自定义标签用于开发版本

### 事件验证

测试验证升级期间的事件序列：

```rust
// 期望的事件序列
assert_event_sequence(&[
    EventKind::WorkerStarting,
    EventKind::ConfigLoaded,
    EventKind::ClusterAdded,
    EventKind::UpgradeStart,
    EventKind::UpgradeComplete,
]).await;
```

## 运行测试

```bash
# 运行所有升级测试
cargo nextest run --test upgrade_e2e_tests

# 运行单个测试
cargo nextest run --test upgrade_e2e_tests test_basic_upgrade

# 带详细输出
cargo nextest run --test upgrade_e2e_tests -- --nocapture
```

## 故障排除

### 常见问题

1. **Worker 启动失败**
   - 检查端口是否被占用
   - 验证配置文件语法
   - 查看 worker 日志

2. **集群状态不一致**
   - 确保升级前集群已完全启动
   - 检查升级超时设置
   - 验证后端健康检查

3. **事件丢失**
   - 增加事件订阅超时
   - 验证事件总线连接
   - 检查日志级别

### 调试技巧

```bash
# 启用详细日志
RUST_LOG=debug cargo nextest run --test upgrade_e2e_tests

# 单独运行测试
SOZU_DEBUG=1 cargo test --test upgrade_e2e_tests test_basic_upgrade -- --nocapture
```

## 交叉引用

- [`testing.md`](testing.md) —— 完整测试策略。
- [`CLAUDE.md`](../CLAUDE.md) —— 代理约定包括测试指南。
- `e2e/COVERAGE.md` —— 功能覆盖矩阵。
