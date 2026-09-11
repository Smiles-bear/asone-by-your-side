/// 协议类型常量与候选顺序。
///
/// 移植自桌面 AsOne `model_services/templates.py`，移动端精简为四协议：
/// openai_chat / openai_responses / anthropic_messages / gemini。
/// Azure OpenAI 暂缓（移动端无部署名字段）。
class ProtocolType {
  ProtocolType._();

  /// 自动识别：依次尝试候选协议，成功后持久化。
  static const auto = 'auto';

  /// OpenAI Chat Completions（/chat/completions）。
  /// 覆盖：OpenAI 官方、DeepSeek、通义千问/DashScope 兼容、智谱 GLM、
  /// Kimi/Moonshot、豆包/火山方舟、MiniMax、文心兼容端点、Grok、Groq、
  /// Mistral、OpenRouter 及各类 OpenAI 兼容中转。
  static const openaiChat = 'openai_chat';

  /// OpenAI Responses API（/responses）。
  /// 覆盖：OpenAI 新 API（gpt-5 系）及部分中转。
  static const openaiResponses = 'openai_responses';

  /// Anthropic Messages API（/v1/messages）。
  /// 覆盖：Claude 官方 + 中转原生协议。
  static const anthropicMessages = 'anthropic_messages';

  /// Google Gemini generateContent（/v1beta/models/{model}:generateContent）。
  /// 覆盖：Google Gemini 官方 Key。
  static const gemini = 'gemini';

  /// auto 模式下的候选尝试顺序。
  static const List<String> autoCandidates = [
    openaiChat,
    openaiResponses,
    anthropicMessages,
    gemini,
  ];

  /// 全部已知协议（不含 auto）。
  static const List<String> allProtocols = [
    openaiChat,
    openaiResponses,
    anthropicMessages,
    gemini,
  ];

  static bool isValid(String value) =>
      value == auto || allProtocols.contains(value);
}
