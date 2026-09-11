import 'dart:convert';

import 'model_protocol_adapter.dart';
import 'model_output_contract.dart';
import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'protocol_types.dart';

/// OpenAI Chat Completions 适配器（/chat/completions）。
///
/// 覆盖 OpenAI 官方及绝大多数国内外 OpenAI 兼容服务：
/// DeepSeek、通义千问/DashScope 兼容、智谱 GLM、Kimi/Moonshot、
/// 豆包/火山方舟、MiniMax、文心兼容端点、Grok、Groq、Mistral、OpenRouter 等。
class OpenAIChatAdapter extends ModelProtocolAdapter {
  @override
  String get protocolType => ProtocolType.openaiChat;

  @override
  Map<String, Object?> requireAnyToolPayload(Map<String, Object?> payload) => {
    ...payload,
    'tool_choice': 'required',
  };

  @override
  List<String> candidateEndpoints(String baseUrl) =>
      endpointVariants(baseUrl, 'chat/completions');

  @override
  Map<String, String> headers(String baseUrl, String apiKey) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  @override
  Map<String, Object?> textPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) {
    final payload = <String, Object?>{
      'model': modelId,
      'messages': _normalizeFileParts(messages),
      'stream': false,
      'temperature': temperature,
    };
    if (maxTokens != null) payload['max_tokens'] = maxTokens;
    if (tools != null && tools.isNotEmpty) payload['tools'] = tools;
    return payload;
  }

  @override
  Map<String, Object?> streamPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) {
    final payload = <String, Object?>{
      'model': modelId,
      'messages': _normalizeFileParts(messages),
      'stream': true,
      'temperature': temperature,
    };
    if (maxTokens != null) payload['max_tokens'] = maxTokens;
    if (tools != null && tools.isNotEmpty) payload['tools'] = tools;
    return payload;
  }

  @override
  Map<String, Object?> outputContractPayload(
    String modelId,
    List<Map<String, Object?>> messages,
    ModelOutputContract contract, {
    required StructuredOutputTransport structuredTransport,
    String? providerId,
    int? maxTokens,
    double temperature = 0,
  }) {
    final payload = textPayload(
      modelId,
      messages,
      maxTokens: maxTokens,
      temperature: temperature,
    );
    if (contract.reasoningPolicy != ModelReasoningPolicy.providerDefault) {
      if (providerId == 'qwen' &&
          contract.reasoningPolicy == ModelReasoningPolicy.disabledPreferred) {
        payload['enable_thinking'] = false;
      } else if (providerId == 'deepseek') {
        payload['thinking'] = <String, Object?>{'type': 'disabled'};
      } else {
        payload['reasoning_effort'] = 'low';
      }
    }
    final schema = contract.schema;
    if (contract.requiresStructuredData && schema != null) {
      if (structuredTransport == StructuredOutputTransport.jsonSchema) {
        payload['response_format'] = {
          'type': 'json_schema',
          'json_schema': {
            'name': contract.schemaName,
            'strict': true,
            'schema': schema,
          },
        };
      } else if (structuredTransport == StructuredOutputTransport.jsonObject) {
        payload['response_format'] = {'type': 'json_object'};
      } else if (structuredTransport == StructuredOutputTransport.forcedTool) {
        payload['tools'] = [
          {
            'type': 'function',
            'function': {
              'name': contract.schemaName,
              'description': '返回业务所需的结构化结果，不执行外部操作。',
              'parameters': schema,
            },
          },
        ];
        payload['tool_choice'] = {
          'type': 'function',
          'function': {'name': contract.schemaName},
        };
      } else if (structuredTransport != StructuredOutputTransport.promptJson) {
        throw StateError('当前 OpenAI Chat 配置没有可用的结构化输出通道');
      }
    }
    return payload;
  }

  List<Map<String, Object?>> _normalizeFileParts(
    List<Map<String, Object?>> messages,
  ) => messages
      .map((message) {
        final content = message['content'];
        if (content is! List) return message;
        return {
          ...message,
          'content': content
              .map((part) {
                if (part is! Map || part['type'] != 'file_data') return part;
                final data = part['data'] as String? ?? '';
                final mime = part['mime_type'] as String? ?? 'application/pdf';
                return {
                  'type': 'file',
                  'file': {
                    'filename': part['filename'] ?? 'attachment.pdf',
                    'file_data': 'data:$mime;base64,$data',
                  },
                };
              })
              .toList(growable: false),
        };
      })
      .toList(growable: false);

  @override
  Map<String, Object?>? audioPayload(
    String modelId,
    List<Map<String, Object?>> messages,
    AudioPayloadData audio, {
    int? maxTokens,
    String? instruction,
  }) {
    final format = audio.openAiFormat;
    if (format == null) return null;
    return textPayload(modelId, [
      ...messages,
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': instruction ?? '请描述这段短音频。'},
          {
            'type': 'input_audio',
            'input_audio': {'data': audio.base64Data, 'format': format},
          },
        ],
      },
    ], maxTokens: maxTokens);
  }

  @override
  String extractText(Map<dynamic, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final message = first['message'];
    if (message is! Map) return '';
    return contentText(message['content']);
  }

  @override
  String extractReasoning(Map<dynamic, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final message = (choices.first as Map)['message'];
    if (message is! Map) return '';
    for (final key in const ['reasoning_content', 'reasoning', 'thinking']) {
      final value = message[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  @override
  List<ProviderToolCall> extractToolCalls(Map<dynamic, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) return const [];
    final message = (choices.first as Map)['message'];
    if (message is! Map || message['tool_calls'] is! List) return const [];
    final calls = <ProviderToolCall>[];
    for (final raw in message['tool_calls'] as List) {
      if (raw is! Map || raw['function'] is! Map) continue;
      final function = raw['function'] as Map;
      final name = function['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final arguments = _parseArguments(function['arguments']);
      calls.add(
        ProviderToolCall(
          id: (raw['id'] as String?) ?? name,
          name: name,
          arguments: arguments,
        ),
      );
    }
    return calls;
  }

  @override
  String streamTextFromFrame(SseFrame frame) {
    final choices = frame.data['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final choice = choices.first as Map;
    final delta = choice['delta'];
    if (delta is Map) {
      final text = contentText(delta['content']);
      if (text.isNotEmpty) return text;
    }
    return contentText(choice['text']);
  }

  @override
  String streamReasoningFromFrame(SseFrame frame) {
    final choices = frame.data['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final delta = (choices.first as Map)['delta'];
    if (delta is! Map) return '';

    // AsOne 桌面端逻辑：尝试多个字段
    for (final key in const ['reasoning_content', 'reasoning', 'thinking']) {
      final value = delta[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  @override
  ProviderStreamTerminal streamTerminalFromFrame(SseFrame frame) {
    if (frame.data['error'] != null) {
      return ProviderStreamTerminal.failure(
        streamFailureReason(frame.data, fallback: 'openai_chat_error'),
      );
    }
    final choices = frame.data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const ProviderStreamTerminal.none();
    }
    final finishReason = (choices.first as Map)['finish_reason']?.toString();
    if (finishReason == null || finishReason.isEmpty) {
      return const ProviderStreamTerminal.none();
    }
    if (finishReason == 'stop' ||
        finishReason == 'tool_calls' ||
        finishReason == 'function_call') {
      return ProviderStreamTerminal.success('finish_reason:$finishReason');
    }
    return ProviderStreamTerminal.failure('finish_reason:$finishReason');
  }

  @override
  List<ProviderToolCall> streamExtractToolCalls(List<SseFrame> frames) {
    // 累积所有 delta 中的 tool_calls
    final toolCallsMap = <String, Map<String, dynamic>>{};

    for (final frame in frames) {
      final choices = frame.data['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'];
      if (delta is! Map || delta['tool_calls'] is! List) continue;

      for (final toolCall in delta['tool_calls'] as List) {
        if (toolCall is! Map) continue;
        final index = toolCall['index'] as int?;
        final id = toolCall['id'] as String?;
        final type = toolCall['type'] as String?;
        final function = toolCall['function'] as Map?;

        if (index == null) continue;
        final key = index.toString();

        toolCallsMap.putIfAbsent(
          key,
          () => {
            'id': id ?? '',
            'type': type ?? 'function',
            'function': {'name': '', 'arguments': ''},
          },
        );

        if (id != null) toolCallsMap[key]!['id'] = id;
        if (type != null) toolCallsMap[key]!['type'] = type;
        if (function != null) {
          final existingFunc =
              toolCallsMap[key]!['function'] as Map<String, dynamic>;
          if (function['name'] != null) {
            existingFunc['name'] = function['name'];
          }
          if (function['arguments'] != null) {
            existingFunc['arguments'] =
                (existingFunc['arguments'] as String) +
                (function['arguments'] as String);
          }
        }
      }
    }

    // 转换为 ProviderToolCall
    final calls = <ProviderToolCall>[];
    for (final entry in toolCallsMap.values) {
      final function = entry['function'] as Map;
      final name = function['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final arguments = _parseArguments(function['arguments']);
      calls.add(
        ProviderToolCall(
          id: entry['id'] as String? ?? name,
          name: name,
          arguments: arguments,
        ),
      );
    }

    return calls;
  }

  @override
  Map<String, Object?> toolProbePayload(
    String modelId,
    String toolName,
    String instruction, {
    String? providerId,
  }) {
    final payload = {
      'model': modelId,
      'stream': false,
      'temperature': 0,
      'max_tokens': 64,
      'messages': [
        {'role': 'user', 'content': instruction},
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': toolName,
            'description': '用于验证客户端工具调用，不执行任何外部操作。',
            'parameters': {
              'type': 'object',
              'properties': {
                'code': {
                  'type': 'string',
                  'enum': ['AZ731'],
                },
              },
              'required': ['code'],
              'additionalProperties': false,
            },
          },
        },
      ],
    };

    // Qwen 不支持强制指定函数，使用 auto（模型自主决定）
    if (providerId == 'qwen') {
      payload['tool_choice'] = 'auto';
    } else {
      // 其他服务商强制指定函数
      payload['tool_choice'] = {
        'type': 'function',
        'function': {'name': toolName},
      };
    }
    if (providerId == 'deepseek' &&
        modelId.trim().toLowerCase().startsWith('deepseek-v4')) {
      payload['thinking'] = <String, Object?>{'type': 'disabled'};
    }

    return payload;
  }

  @override
  Map<String, Object?> structuredProbePayload(
    String modelId,
    String instruction,
    Map<String, Object?> schema, {
    String? providerId,
  }) {
    return {
      'model': modelId,
      'stream': false,
      'temperature': 0,
      'max_tokens': 256,
      if (providerId == 'qwen') 'enable_thinking': false,
      if (providerId == 'deepseek' &&
          modelId.trim().toLowerCase().startsWith('deepseek-v4'))
        'thinking': <String, Object?>{'type': 'disabled'},
      'messages': [
        {'role': 'user', 'content': instruction},
      ],
      'response_format': {
        'type': 'json_schema',
        'json_schema': {
          'name': 'capability_probe',
          'strict': true,
          'schema': schema,
        },
      },
    };
  }

  @override
  Map<String, Object?> structuredFallbackPayload(
    String modelId,
    String instruction,
    Map<String, Object?> schema, {
    String? providerId,
  }) {
    return {
      'model': modelId,
      'stream': false,
      'temperature': 0,
      'max_tokens': 256,
      if (providerId == 'qwen') 'enable_thinking': false,
      if (providerId == 'deepseek' &&
          modelId.trim().toLowerCase().startsWith('deepseek-v4'))
        'thinking': <String, Object?>{'type': 'disabled'},
      'messages': [
        {'role': 'system', 'content': '只输出 JSON 对象，不要输出 Markdown 或解释。'},
        {'role': 'user', 'content': instruction},
      ],
      'response_format': {'type': 'json_object'},
    };
  }

  Map<String, Object?> _parseArguments(dynamic raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return {};
  }
}
