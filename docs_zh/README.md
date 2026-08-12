# Sōzu

## Sōzu 是什么？

Sōzu 是一个用 Rust 编写的用于负载均衡的反向代理。它的主要工作是在两个或多个集群后端之间平衡入站请求，以分散负载。

* 它作为 TLS 会话的终止点。因此，处理加密的工作负载从后端卸载。

* 它可以通过阻止来自网络的直接访问来保护后端。

* 它返回一些与其后面的客户端和后端集群之间流量相关的指标。

## 介绍

* [入门][gs]

* [配置 Sōzu][cg]

* [配置 Sōzu CLI][cgcli]

* [如何使用它][hw]

* [为什么你应该使用 Sōzu][ws]

* [设计动机][dm]

* [技巧][r]

## 概述

* [架构概述][ar]

* [工具和库][tl]

* [术语表][lx]

## 运维 Sōzu

* [配置 Sōzu][cg]

* [管理操作与实例讲解][cao]

* [可观测性 —— 日志、指标、审计日志][ob]

* [调试策略][ds]

* [基准测试][bm]

* [速率限制设计][rl]

## 深入

* [H2 多路复用内部机制][h2] —— HTTP/2 多路复用器实现的开发者参考

* [H2 多路复用 LIFECYCLE.md][h2lc] —— 树内状态机参考，与代码同步维护

* [UDP LIFECYCLE.md][udplc] —— UDP 数据路径（用户态 conntrack、NAT 回程、拆除、加固）的树内流/状态机参考，与代码同步维护

* [健康检查][hc]

* [会话的生命周期][li]

## 测试

* [测试指南][tst] —— 测试准则：断言优先 + 确定性仿真，分类，以及每次变更必须附带的内容

* [Worker 升级端到端测试][ue]

* [确定性仿真（UDP）][uds] —— 面向 sans-io UDP 核心的 FoundationDB/VOPR 式种子故障注入

* [每日 CI 说明][nci]

## 发行说明

* [变更日志](../CHANGELOG.md)

## 演示和幻灯片

* [Sōzu，一个可热重构的反向 HTTP 代理，作者：Geoffroy Couprie](https://youtu.be/y4NdVW9sHtU)

* [(法语) 2017 年重构反向代理以实现不可变基础设施，作者：Quentin Adam](https://youtu.be/uv3BG1J8YKc)

[gs]: ./getting_started.md
[cg]: ./configure.md
[cgcli]: ./configure_cli.md
[cao]: ./configure_admin_ops.md
[hw]: ./how_to_use.md
[dm]: ./design_motivation.md
[ar]: ./architecture.md
[tl]: ./tools_libraries.md
[lx]: ./lexicon.md
[ws]: ./why_you_should_use.md
[r]: ./recipes.md
[h2]: ./h2_mux_internals.md
[h2lc]: ../lib/src/protocol/mux/LIFECYCLE.md
[udplc]: ../lib/src/protocol/udp/LIFECYCLE.md
[hc]: ./health_checks.md
[li]: ./lifetime_of_a_session.md
[tst]: ./testing.md
[ue]: ./upgrade_e2e_tests.md
[uds]: ./udp_simulation.md
[ob]: ./observability.md
[ds]: ./debugging_strategies.md
[bm]: ./benchmark.md
[rl]: ./rate-limit-design.md
[nci]: ./nightly-ci-notes.md
