# asone_demo_core

Azruiyoi 公开契约（`asone_contracts`）的**纯内存演示实现**，供 Community/Demo 版本与公共仓库示例、测试使用。

- `DemoCore implements OpenCore`：启动时 `OpenCoreBinding.attach(DemoCore())` 即可让全部已迁移页面运行在演示数据上；
- 8 个内存 Store 分别实现六域仓储接口与 `FeatureUnreadApi`、`TokenUsageApi`，共约 103 个方法，全部为真实（简化）实现，不抛 `UnimplementedError`；
- 数据以内存 JSON 行存储，复用契约 DTO 的 `fromJson/toJson`，重启不持久（Demo 定位）；
- 简化语义：日历重复展开支持常见周期、`verifyDeletion` 按内存状态返回、`resolveCreatorColors` 固定调色板、token 统计对内存记录同形聚合；
- 不包含任何闭源核心（记忆、持续心智、心跳、互动编排、模型绑定、语音、工具运行时）的实现或桩。

许可证：Apache-2.0（见 LICENSE）。
