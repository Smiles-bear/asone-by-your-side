import 'adapter_types.dart';
import 'protocol_types.dart';
import 'model_protocol_adapter.dart';
import 'openai_chat_adapter.dart';
import 'openai_responses_adapter.dart';
import 'anthropic_messages_adapter.dart';
import 'gemini_adapter.dart';

/// 协议适配器注册表。
///
/// 管理所有已注册的协议适配器，提供按类型获取和 auto 候选顺序。
class AdapterRegistry {
  AdapterRegistry._();

  static final AdapterRegistry instance = AdapterRegistry._();

  final Map<String, ModelProtocolAdapter> _adapters = {
    ProtocolType.openaiChat: OpenAIChatAdapter(),
    ProtocolType.openaiResponses: OpenAIResponsesAdapter(),
    ProtocolType.anthropicMessages: AnthropicMessagesAdapter(),
    ProtocolType.gemini: GeminiAdapter(),
  };

  /// 按协议类型获取适配器。未识别时抛异常。
  ModelProtocolAdapter get(String protocolType) {
    final adapter = _adapters[protocolType];
    if (adapter == null) {
      throw AdapterRequestException(
        const NormalizedError('PROTOCOL_MISMATCH', '未识别当前接口协议，请在高级设置中选择协议。'),
      );
    }
    return adapter;
  }

  /// auto 模式下的候选协议顺序。
  List<String> autoCandidates() => ProtocolType.autoCandidates.toList();

  /// 判断错误码是否允许换协议重试。
  bool mayTryAnother(AdapterRequestException exc) =>
      retryableErrorCodes.contains(exc.error.code);
}
