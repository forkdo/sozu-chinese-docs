# Nightly CI 矩阵 — 允许失败说明

CI 矩阵（`ci.yml`）包含 `rust: nightly` 配置，并带有 `experimental: true` / `continue-on-error: true`，使其在 PR 合并时不会造成阻塞。

## 当前状态（2026-04-22）

**分类：未观察到 nightly 专属失败。**

对 `feat/h2-mux` 分支所有已完成 CI 运行（运行 ID 24682798916 至 24768926470）的审计显示：
每个执行到完成的 `Test (nightly, true)` 任务均返回 **成功**。历史上 `feat/h2-mux` 的一次失败（运行 24718201148）属于 stable 任务失败，而非 nightly。

代码库中不包含任何 `#![feature(...)]` 门控，因此完全兼容 stable 工具链，除了编译器内部实现之外，nightly 不引入额外的风险面。

## 为什么 nightly 被设为允许失败

Nightly 版本的 rustc 偶尔会引入新的 lint、重命名不稳定标志，或更改类型推断行为，从而可能导致原本正确的代码被破坏。`experimental: true` 这一行存在的目的是尽早暴露此类回归，同时不阻塞 stable CI。截至撰写本文时，nightly 任务顺利通过，无需任何抑制属性。

## 需要采取的行动

无需任何操作。如果将来 nightly 任务开始持续失败，请使用 `gh run view <run-id> --log-failed` 检查，并按需添加针对性的 `#[allow(...)]`，或视情况向 rustc 提交 issue。
