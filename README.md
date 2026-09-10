# Azruiyoi 社区演示版

Azruiyoi 的公开源码版本：包含公开 UI、基础数据模型与契约接口，以及留言板、小纸条、日历等基础功能，运行在内存演示数据（`DemoCore`）之上。记忆、持续心智、主动心跳、互动编排、语音、工具运行时等完整能力由私有正式版提供，不在本仓库范围内。

## 运行

```bash
cd frontend
flutter pub get
flutter run        # android 脚手架已内置
flutter test
```

> android 平台目录由 `flutter create --platforms=android --org com.ruyi.community` 干净生成，
> 不含任何正式签名配置。社区演示包可用 `flutter build apk --debug`（调试签名）构建；
> 正式发布版由私有仓库构建并签名，与本仓库无关。

## 包测试

```bash
cd frontend/packages/asone_contracts && flutter test
cd ../asone_demo_core && flutter test
```

## 结构

- `frontend/` — Flutter 应用（公开子集，入口 `lib/main.dart`：法律同意门 + `OpenCoreBinding.attach(DemoCore.withDemoSeed())` + 功能/我的双页签）
- `frontend/packages/asone_contracts` — 公开数据模型与接口契约（Apache-2.0）
- `frontend/packages/asone_demo_core` — 契约的纯内存演示实现（Apache-2.0）
- `website/` — 官网静态站
- `legal/apk_compliance/` — APK 第三方组件合规资料（许可证汇总、NOTICE、libmpv LGPL 说明）

## 演示数据说明

`DemoCore` 为纯内存实现：所有数据为虚构中文演示种子，重启后重置；不连接任何真实模型服务（模型服务条目为 `example.invalid` 占位）。

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。

版权所有 2026 京山市如一软件科技有限公司、何俊雄、胡洋洋。

第三方组件许可与 APK 分发义务见 `legal/apk_compliance/`。
