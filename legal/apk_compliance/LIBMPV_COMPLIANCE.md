# libmpv（LGPL-2.1+）合规说明

> 生成日期：2026-09-10。本文件记录 APK 中唯一 copyleft 组件的实证版本链、LGPL-2.1 §6 义务落实方式与升级复核清单。事实性文档，非法律建议。

## 一、组件与版本链（全部实证，来源标注）

```
frontend/pubspec.lock
  └─ media_kit_libs_android_video 1.3.8        （pub 包，MIT wrapper，版权：Hitesh Kumar Saini）
       └─ android/build.gradle L61-64          （本地 pub cache 内核实）
            构建 APK 时从 GitHub 下载预编译 jar（带 MD5 校验，四 ABI）：
            https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.7/default-{arm64-v8a,armeabi-v7a,x86_64,x86}.jar
            MD5：83df25b61193af8fa815e373143ac9af / 22e21526fefc0a2b8f17adbec9f57590 /
                 6fa26bf0459b11f1c0b0dbc29e5b940d / 0d742b756dc9d1fcd84ea271d8b68f32
              └─ media-kit/libmpv-android-video-build release v1.1.7（发布于 2025 年，GitHub API 核实）
                   jar 内含 libmpv 预编译 .so（LGPL-2.1+ 模式构建）
```

- mpv 项目为 GPL-2.0+ / LGPL-2.1+ 双许可；media_kit 使用 **default（LGPL）flavor**（构建仓库同时存在 `bundle_encoders-gpl.sh` GPL flavor，本产品下载的 jar 均为 `default-*`，非 GPL 编码器集合）。参考：mpv `LICENSE.LGPL`、media-kit Issue #20。
- **待核实项（如实标注）**：v1.1.7 所用的具体 mpv/FFmpeg 版本 tag 钉在构建仓库 `buildscripts/` 内部（download.sh 在线核查未能提取），以 https://github.com/media-kit/libmpv-android-video-build/tree/v1.1.7 的构建脚本为准。

## 二、使用形态与法律定位（事实描述）

- libmpv 以独立 `.so` 形式打包进 APK 的 `lib/<abi>/`，由 media_kit 在运行时**动态加载**；
- 应用自身代码（专有/Apache-2.0）不静态链接、不修改 libmpv；
- 该形态属于 LGPL-2.1 §6 的"使用库的作品"（Combined Work）分发场景。

## 三、§6 义务落实

### 1. 许可文本（§4/§6）

- LGPL-2.1 全文：本目录 `licenses/LGPL-2.1.txt`（SPDX 官方文本）；
- 随 APK 分发：Flutter 构建的 `flutter_assets/NOTICES` 已包含 media_kit 系列 pub 包许可证；libmpv 文本的 APK 内呈现（"关于"页）为**后续候选项**，当前决策为仅仓库文件（2026-09-10）。

### 2. 用户可替换库（§6 反 Tivoization 要求）

替换步骤（面向最终用户的说明文本，可直接用于官网/关于页）：

1. 获取与本 APK 相同 ABI 的替换用 `libmpv` 系列 `.so`（自行编译或第三方构建）；
2. 使用 APK 解包工具（如 `apktool d app.apk`）解开安装包；
3. 替换 `lib/<abi>/` 下对应 `.so` 文件；
4. 重新打包（`apktool b`）并使用**用户自己的签名密钥**签名安装；
5. 注意：重签名后无法接收官方覆盖升级，需自行维护。

本产品未对 `.so` 加载施加签名校验或完整性锁定（media_kit 通过系统动态链接器加载）。

### 3. 对应源码书面要约（§6(a)）

随分发提供的要约文本模板：

> 本应用包含以 GNU LGPL-2.1+ 许可的 libmpv 库（经 media-kit/libmpv-android-video-build v1.1.7 构建）。您有权获取该库的对应源码：构建脚本与补丁见 https://github.com/media-kit/libmpv-android-video-build （tag v1.1.7），libmpv 上游源码见 https://github.com/mpv-player/mpv 与其依赖 https://github.com/FFmpeg/FFmpeg 。如需我们提供对应源码副本，请联系（联系方式待阶段 D 填写），该要约自分发之日起三年内有效。

## 四、升级复核清单

每次 `media_kit_libs_android_video`（或 media_kit 系列）版本变更时：

- [ ] 重读新版包内 `android/build.gradle`，更新本文件的下载 URL、release tag、MD5；
- [ ] 确认下载的仍是 `default-*`（LGPL）而非 `*-gpl` jar；
- [ ] 核实新 release 的构建脚本中 mpv/FFmpeg 版本，补"待核实项"；
- [ ] 同步更新 `THIRD_PARTY_LICENSES.md` 第二节。
