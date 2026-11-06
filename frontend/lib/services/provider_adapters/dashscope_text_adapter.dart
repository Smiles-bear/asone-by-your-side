import '../model_endpoint.dart';
import 'adapter_types.dart';
import 'adapter_helpers.dart' show SseFrame;
import 'model_protocol_adapter.dart' show ProviderStreamTextChunk;
import 'dashscope_response.dart';
import 'openai_chat_adapter.dart';
import 'protocol_types.dart';

/// Native DashScope HTTP. Shared policies use logical message fields; only the
/// transport boundary produces input/parameters and the native SSE header.
class DashScopeTextAdapter extends OpenAIChatAdapter {
  @override
  String get protocolType => ProtocolType.dashscopeText;

  @override
  Map<String, String> streamHeaders(String baseUrl, String apiKey) => {
    ...headers(baseUrl, apiKey),
    'X-DashScope-SSE': 'enable',
  };

  @override
  List<String> candidateEndpoints(String baseUrl) =>
      requestEndpoints(baseUrl, 'qwen-plus');

  @override
  List<String> requestEndpoints(String baseUrl, String modelId) {
    final base = protocolModelBaseUrl(baseUrl, protocolType);
    if (base.endsWith('/services/aigc/text-generation/generation') ||
        base.endsWith('/services/aigc/multimodal-generation/generation')) {
      return [base];
    }
    return [
      modelEndpointUri(
        base,
        'services/aigc/${_multimodal(modelId) ? 'multimodal' : 'text'}-generation/generation',
      ).toString(),
    ];
  }

  bool _multimodal(String model) {
    final id = model.toLowerCase();
    final version = RegExp(r'^qwen3\.(\d+)').firstMatch(id);
    return id.contains('-vl') ||
        id.contains('-omni') ||
        id.startsWith('qvq-') ||
        (version != null &&
            const {'5', '6', '7', '8'}.contains(version.group(1)));
  }

  @override
  Map<String, Object?> transportPayload(
    Map<String, Object?> payload, {
    String? baseUrl,
  }) {
    final model = payload['model'] as String;
    final messages = payload['messages'] as List;
    return {
      'model': model,
      'input': {
        'messages': [
          for (final raw in messages)
            _message(
              Map<String, Object?>.from(raw as Map),
              _multimodal(model) ||
                  (baseUrl?.contains('/multimodal-generation/') ?? false),
            ),
        ],
      },
      'parameters': {
        for (final entry in payload.entries)
          if (!const {
            'model',
            'messages',
            'stream',
            'stream_options',
            'max_completion_tokens',
            'reasoning_effort',
          }.contains(entry.key))
            entry.key: entry.value,
        if (payload['max_completion_tokens'] != null)
          'max_tokens': payload['max_completion_tokens'],
        'result_format': 'message',
        if (payload['stream'] == true) 'incremental_output': true,
      },
    };
  }

  Map<String, Object?> _message(Map<String, Object?> raw, bool multimodal) {
    final content = raw['content'];
    if (content is List) {
      return {
        ...raw,
        'content': [for (final part in content) _contentPart(part as Map)],
      };
    }
    if (multimodal && content is String) {
      return {
        ...raw,
        'content': [
          {'text': content},
        ],
      };
    }
    return raw;
  }

  Map<String, Object?> _contentPart(Map part) {
    if (part['type'] == 'text' && part['text'] is String) {
      return {'text': part['text']};
    }
    if (part['type'] == 'image_url' && part['image_url'] is Map) {
      return {'image': (part['image_url'] as Map)['url']};
    }
    // Already-native parts remain intact; never drop unknown media silently.
    return Map<String, Object?>.from(part);
  }

  @override
  Map<String, Object?> requireAnyToolPayload(Map<String, Object?> payload) {
    final tools = payload['tools'] as List;
    final function = (tools.first as Map)['function'] as Map;
    return {
      ...payload,
      'tool_choice': {
        'type': 'function',
        'function': {'name': function['name']},
      },
    };
  }

  @override
  String extractText(Map payload) =>
      super.extractText(dashscopeChatPayload(payload));

  @override
  String extractReasoning(Map payload) =>
      super.extractReasoning(dashscopeChatPayload(payload));

  @override
  Map<String, Object?>? extractNativeContinuation(Map payload) =>
      super.extractNativeContinuation(dashscopeChatPayload(payload));

  @override
  ProviderStreamTerminal streamTerminalFromFrame(SseFrame frame) =>
      super.streamTerminalFromFrame(_frame(frame));

  @override
  String streamTextFromFrame(SseFrame frame) =>
      super.streamTextFromFrame(_frame(frame));

  @override
  ProviderStreamTextChunk streamTextChunkFromFrame(SseFrame frame) =>
      super.streamTextChunkFromFrame(_frame(frame));

  @override
  String streamReasoningFromFrame(SseFrame frame) =>
      super.streamReasoningFromFrame(_frame(frame));

  SseFrame _frame(SseFrame frame) => SseFrame(
    eventType: frame.eventType,
    data: dashscopeChatPayload(frame.data, streaming: true),
  );
}
