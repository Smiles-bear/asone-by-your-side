# 第三方服务与组件清单

更新日期 2026年9月6日

## 用户选择的外部服务

- **第三方模型服务：**DeepSeek、Kimi、GLM、Qwen、豆包、MiniMax、混元、文心、星火、Step 及自定义地址。用于模型请求、能力检测和模型驱动功能；可能接收 API Key、模型名称、文本、上下文、图片、文件、音频、画面和工具结果。
- **远程语音服务：**由用户填写的 ElevenLabs 兼容或自定义地址。用于获取模型和音色、语音识别及语音合成；可能接收 API Key、录音和待合成文本。
- **MCP 与 HTTP 工具：**由用户添加并启用的远程地址。用于执行用户授权的外部工具；可能接收鉴权信息、工具参数和相关上下文。
- **GitHub：**用于用户确认后下载本地语音识别模型资源；会产生正常网络连接信息，模型安装后在设备本地运行。
- **用户输入的链接和资源主机：**用于读取用户指定网页、文件或远程图片；相应主机可能获得正常网络请求信息。

上述服务不是京山市如一软件科技有限公司的业务服务器，其处理规则由各自协议和隐私政策决定。

## 主要本地组件

Flutter、sqflite、shared_preferences、path_provider、flutter_secure_storage、cryptography、file_picker、workmanager、flutter_local_notifications、record、just_audio、audio_service、media_kit、sherpa_onnx、Health Connect、package_info_plus 等用于界面、本地存储、安全存储、文件选择、后台任务、通知、录音、媒体播放、本地语音识别、健康授权和版本展示。

根据当前集成方式，这些组件未被配置为向我们或商业统计平台独立上传聊天、记忆或 API Key。系统组件和开源项目可能随版本变化，本清单会随正式版本更新。
