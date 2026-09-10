# APK 第三方组件许可证汇总

> 生成日期：2026-09-10。事实来源：本地 pub cache LICENSE 文件、pub.dev、上游 GitHub 仓库（逐项来源见盘点记录，交接文档第 9/10 节）。
> 本表为人工维护的摘要；pub 依赖许可证全文以 Flutter 构建自动生成的 `build/flutter_assets/NOTICES`（随 APK 分发）为权威载体，本目录只补足其未覆盖的原生组件义务。
> 升级依赖后必须复核本表（对照 `frontend/pubspec.lock`）。

## 产品版权

Azruiyoi © 2026 京山市如一软件科技有限公司、何俊雄、胡洋洋

- 公开源码部分：Apache-2.0（见公共仓库根 LICENSE 与 `frontend/packages/asone_contracts/LICENSE`）
- 闭源核心与正式签名构建：专有，保留所有权利

## 一、Dart/Flutter 直接依赖（37 项，全部为宽松许可证）

| 包名 | 锁定版本 | 许可证 | 含原生二进制 | 备注 |
|---|---|---|---|---|
| flutter / flutter_localizations (SDK) | sdk | BSD-3-Clause | 是（引擎） | Flutter 引擎本体 |
| cupertino_icons | 1.0.8 | MIT | 否 | |
| dio | 5.11.0 | MIT | 否 | |
| http | 1.6.0 | BSD-3-Clause | 否 | |
| shared_preferences | 2.5.3 | BSD-3-Clause | 否 | |
| flutter_markdown | 0.7.7+1 | BSD-3-Clause | 否 | 上游已停止维护（discontinued） |
| path_provider | 2.1.5 | BSD-3-Clause | 否 | |
| sqflite | 2.4.2 | BSD-2-Clause | 否 | SQLite 本体为 public domain |
| file_picker | 11.0.3 | MIT | 否 | |
| flutter_secure_storage | 10.3.1 | BSD-3-Clause | 否 | |
| cryptography | 2.9.0 | Apache-2.0 | 否 | |
| workmanager | 0.7.0 | MIT | 否 | |
| flutter_local_notifications | 17.2.4 | BSD-3-Clause | 否 | |
| intl | 0.20.3 | BSD-3-Clause | 否 | |
| package_info_plus | 8.3.1 | BSD-3-Clause | 否 | |
| fl_chart | 0.68.0 | MIT | 否 | |
| quickjs_engine | 0.1.5 | MIT | 是（.so） | QuickJS-NG（MIT），动态链接 |
| flutter_svg | 2.3.0 | MIT | 否 | |
| phosphoricons_flutter | 1.0.0 | MIT | 否 | 含 Phosphor 字体（MIT） |
| xml | 6.6.1 | MIT | 否 | |
| sherpa_onnx | 1.13.6 | Apache-2.0 | 是（.so） | 内嵌 onnxruntime（MIT）；NOTICE 义务见 NOTICE.md |
| archive | 4.2.0 | MIT | 否 | v3.1.3 起 Apache-2.0 → MIT |
| pdf_graphics / pdf_document | 4.0.0 | Apache-2.0 | 否 | dart-pdf 套件，纯 Dart |
| path | 1.9.1 | BSD-3-Clause | 否 | |
| just_audio | 0.10.6 | MIT + Apache-2.0 | 是 | Android 端依赖 Media3/ExoPlayer（Apache-2.0） |
| audio_service | 0.18.19 | MIT | 否 | |
| audio_session | 0.2.4 | MIT | 否 | |
| record | 7.1.1 | BSD-3-Clause | 否 | |
| media_kit | 1.2.6 | MIT | 否 | Dart wrapper；原生库见下节 libmpv |
| media_kit_video | 2.0.1 | MIT | 是 | |
| media_kit_libs_video | 1.0.7 | MIT | — | 元包，按平台转发 |
| image | 4.9.2 | MIT | 否 | v3.0.6 起改为 MIT |
| flutter_reorderable_grid_view | 5.7.0 | BSD-3-Clause | 否 | |

内部 path 包（第一方，非第三方依赖）：

| 包名 | 性质 | 许可 |
|---|---|---|
| asone_contracts | 公开契约包 | Apache-2.0（已含 LICENSE） |
| asone_android_capability | 闭源 Android 原生能力包 | 专有，保留所有权利（阶段 C 快照时加专有标注） |

## 二、随 APK 分发的关键原生/传递组件

| 组件 | 引入路径 | 许可证 | 说明 |
|---|---|---|---|
| **libmpv** | media_kit_libs_android_video 1.3.8 → libmpv-android-video-build release v1.1.7 的 default-{ABI}.jar | **LGPL-2.1+** | 唯一 copyleft 组件；义务与版本链证据见 `LIBMPV_COMPLIANCE.md` |
| onnxruntime | sherpa_onnx_android_*（4 ABI）内嵌 | MIT | Microsoft；归属声明见 NOTICE.md |
| Media3/ExoPlayer | just_audio Android 端 | Apache-2.0 | Google |
| QuickJS-NG | quickjs_engine | MIT | 动态链接 |
| Gradle Wrapper | frontend/android/gradle/wrapper | Apache-2.0 | 构建工具 |
| SQLite | sqflite / sqlite3 底层 | Public domain | 无许可义务 |

## 三、分发义务速查（事实性摘要，非法律建议）

| 许可证 | 义务 | 本产品落实方式 |
|---|---|---|
| MIT / BSD | 随分发附版权声明与许可文本 | Flutter 自动生成的 `flutter_assets/NOTICES` 随 APK 分发；本目录 `licenses/` 存官方全文 |
| Apache-2.0 | 附许可文本；传递上游 NOTICE | `licenses/Apache-2.0.txt` + `NOTICE.md` |
| LGPL-2.1（libmpv） | 附许可文本；允许用户替换库；提供对应源码或书面要约 | `licenses/LGPL-2.1.txt` + `LIBMPV_COMPLIANCE.md`（替换步骤 + 源码要约文本） |
