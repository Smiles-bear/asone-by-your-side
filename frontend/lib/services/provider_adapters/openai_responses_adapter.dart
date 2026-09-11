import 'dart:convert';

import 'model_protocol_adapter.dart';
import 'model_output_contract.dart';
import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'protocol_types.dart';

/// OpenAI Responses API 适配器（/responses）。
///
/// 覆盖 OpenAI 新 API（gpt-5 系 Responses 端点）及部分中转。
class OpenAIResponsesAdapter extends ModelProtocolAdapter {
  @override
  String get protocolType => ProtocolType.openaiResponses;

  @override
  Map<String, Object?> requireAnyToolPayload(Map<String, Object?> payload) => {
    ...payload,
    'tool_choice': 'required',
  };

  @override
  List<String> candidateEndpoints(String baseUrl) =>
      endpointVariants(baseUrl, 'responses');

  @override
  Map<String, String> headers(String baseUrl, String apiKey) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  /// 把 OpenAI 风格 messages 转成 Responses 的 input。
  List<Map<String, Object?>> _toInput(List<Map<String, Object?>> messages) {
    final result = <Map<String, Object?>>[];
    for (final message in messages) {
      final role = (message['role'] as String?) ?? 'user';
      final content = message['content'] ?? '';
      if (role == 'tool') {
        result.add({
          'type': 'function_call_output',
          'call_id': message['tool_call_id'] ?? '',
          'output': content is String ? content : jsonEncode(content),
        });
        continue;
      }
      final toolCalls = message['tool_calls'];
      if (role == 'assistant' && toolCalls is List && toolCalls.isNotEmpty) {
        if (content is String && content.isNotEmpty) {
          result.add({'role': role, 'content': content});
        }
        for (final rawCall in toolCalls) {
          if (rawCall is! Map) continue;
          final function = rawCall['function'];
          if (function is! Map) continue;
          result.add({
            'type': 'function_call',
            'call_id': rawCall['id'] ?? '',
            'name': function['name'] ?? '',
            'arguments': function['arguments'] is String
                ? function['arguments']
                : jsonEncode(function['arguments'] ?? const {}),
          });
        }
        continue;
      }
      if (content is String) {
        result.add({'role': role, 'content': content});
        continue;
      }
      if (content is List) {
        final parts = <Map<String, Object?>>[];
        for (final part in content) {
          if (part is! Map) continue;
          final type = part['type'];
          if (type == 'text' || type == 'input_text') {
            parts.add({'type': 'input_text', 'text': part['text'] ?? ''});
          } else if (type == 'image_url' || type == 'input_image') {
            final raw = part['image_url'];
            final url = raw is Map ? (raw['url'] as String?) : (raw as String?);
            if (url != null && url.isNotEmpty) {
              parts.add({'type': 'input_image', 'image_url': url});
            }
          } else if (type == 'file_data') {
            final data = part['data'] as String?;
            final mime = part['mime_type'] as String? ?? 'application/pdf';
            if (data != null && data.isNotEmpty) {
              parts.add({
                'type': 'input_file',
                'filename': part['filename'] ?? 'attachment.pdf',
                'file_data': 'data:$mime;base64,$data',
              });
            }
          }
        }
        result.add({'role': role, 'content': parts});
      } else {
        result.add({'role': role, 'content': ''});
      }
    }
    return result;
  }

  Map<String, Object?> _responsesPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    bool stream = false,
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) {
    final payload = <String, Object?>{
      'model': modelId,
      'input': _toInput(messages),
      'stream': stream,
      'temperature': temperature,
      'store': false,
    };
    if (maxTokens != null) payload['max_output_tokens'] = maxTokens;
    if (tools != null && tools.isNotEmpty) {
      payload['tools'] = tools.map(_toResponsesTool).toList(growable: false);
    }
    return payload;
  }

  Map<String, Object?> _toResponsesTool(Map<String, Object?> tool) {
    final function = tool['function'];
    if (tool['type'] != 'function' || function is! Map) return tool;
    return {
      'type': 'function',
      'name': function['name'] ?? '',
      if (function['description'] != null)
        'description': function['description'],
      'parameters': function['parameters'] ?? const <String, Object?>{},
      if (function['strict'] != null) 'strict': function['strict'],
    };
  }

  @override
  Map<String, Object?> textPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) => _responsesPayload(
    modelId,
    messages,
    stream: false,
    maxTokens: maxTokens,
    temperature: temperature,
    tools: tools,
  );

  @override
  Map<String, Object?> streamPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) => _responsesPayload(
    modelId,
    messages,
    stream: true,
    maxTokens: maxTokens,
    temperature: temperature,
    tools: tools,
  );

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
      payload['reasoning'] = {'effort': 'low'};
    }
    final schema = contract.schema;
    if (contract.requiresStructuredData && schema != null) {
      if (structuredTransport == StructuredOutputTransport.jsonSchema) {
        payload['text'] = {
          'format': {
            'type': 'json_schema',
            'name': contract.schemaName,
            'schema': schema,
            'strict': true,
          },
        };
      } else if (structuredTransport != StructuredOutputTransport.promptJson) {
        throw StateError('当前 Responses 配置没有可用的严格结构化输出通道');
      }
    }
    return payload;
  }

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
    final payload = _responsesPayload(
      modelId,
      messages,
      maxTokens: maxTokens,
      temperature: 0,
    );
    final input = (payload['input'] as List).cast<Map<String, Object?>>();
    input.add({
      'role': 'user',
      'content': [
        {'type': 'input_text', 'text': instruction ?? '请描述这段短音频。'},
        {
          'type': 'input_audio',
          'input_audio': {'data': audio.base64Data, 'format': format},
        },
      ],
    });
    return payload;
  }

  @override
  String extractText(Map<dynamic, dynamic> payload) {
    final textParts = <String>[];
    final output = payload['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) continue;
        final content = item['content'];
        if (content is List) {
          for (final part in content) {
            if (part is! Map) continue;
            final type = part['type'];
            if (type == 'output_text' || type == 'text') {
              final text = part['text'];
              if (text is String) textParts.add(text);
            }
          }
        }
      }
    }
    if (textParts.isEmpty) {
      final outputText = payload['output_text'];
      if (outputText is String) textParts.add(outputText);
    }
    return textParts.join();
  }

  @override
  String extractReasoning(Map<dynamic, dynamic> payload) {
    final reasoningParts = <String>[];
    final output = payload['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) continue;
        // AsOne 桌面端逻辑：type == "reasoning"
        if (item['type'] == 'reasoning') {
          final summary = item['summary'];
          if (summary is List) {
            for (final part in summary) {
              if (part is Map && part['text'] is String) {
                reasoningParts.add(part['text'] as String);
              }
            }
          }
          final content = item['content'];
          if (content is List) {
            for (final part in content) {
              if (part is Map &&
                  (part['type'] == 'reasoning_text' ||
                      part['type'] == 'text') &&
                  part['text'] is String) {
                reasoningParts.add(part['text'] as String);
              }
            }
          }
        }
      }
    }
    return reasoningParts.join('\n');
  }

  @override
  List<ProviderToolCall> extractToolCalls(Map<dynamic, dynamic> payload) {
    final calls = <ProviderToolCall>[];
    final output = payload['output'];
    if (output is! List) return calls;
    for (final item in output) {
      if (item is! Map) continue;
      final type = item['type'];
      if (type != 'function_call' && type != 'tool_call') continue;
      final name = (item['name'] as String?) ?? '';
      if (name.isEmpty) continue;
      calls.add(
        ProviderToolCall(
          id: (item['call_id'] as String?) ?? (item['id'] as String?) ?? name,
          name: name,
          arguments: _parseArguments(item['arguments']),
        ),
      );
    }
    return calls;
  }

  @override
  String streamTextFromFrame(SseFrame frame) {
    final eventType = frame.eventType;
    final typeField = (frame.data['type'] as String?) ?? '';
    // 优先用 event: 行的类型，其次用 data 内的 type 字段。
    final effectiveType = eventType.isNotEmpty ? eventType : typeField;
    if (effectiveType.endsWith('output_text.delta')) {
      return (frame.data['delta'] as String?) ?? '';
    }
    return '';
  }

  @override
  String streamReasoningFromFrame(SseFrame frame) {
    final eventType = frame.eventType;
    final typeField = (frame.data['type'] as String?) ?? '';
    final effectiveType = eventType.isNotEmpty ? eventType : typeField;
    if (effectiveType.endsWith('reasoning_summary_text.delta') ||
        effectiveType.endsWith('reasoning_text.delta')) {
      return (frame.data['delta'] as String?) ?? '';
    }
    return '';
  }

  @override
  ProviderStreamTerminal streamTerminalFromFrame(SseFrame frame) {
    final eventType = frame.eventType;
    final typeField = frame.data['type']?.toString() ?? '';
    final effectiveType = eventType.isNotEmpty ? eventType : typeField;
    if (effectiveType == 'response.completed') {
      return const ProviderStreamTerminal.success('response.completed');
    }
    if (effectiveType == 'response.failed' ||
        effectiveType == 'response.incomplete' ||
        effectiveType == 'error' ||
        frame.data['error'] != null ||
        typeField == 'upstream_error') {
      return ProviderStreamTerminal.failure(
        streamFailureReason(frame.data, fallback: effectiveType),
      );
    }
    return const ProviderStreamTerminal.none();
  }

  @override
  List<ProviderToolCall> streamExtractToolCalls(List<SseFrame> frames) {
    final names = <String, String>{};
    final callIds = <String, String>{};
    final arguments = <String, StringBuffer>{};
    final order = <String>[];
    final completed = <ProviderToolCall>[];

    void rememberItem(Map<dynamic, dynamic> item, [String? fallbackKey]) {
      final type = item['type'];
      if (type != 'function_call' && type != 'tool_call') return;
      final name = item['name'] as String? ?? '';
      final key =
          (item['id'] as String?) ??
          (item['call_id'] as String?) ??
          fallbackKey ??
          name;
      if (key.isEmpty) return;
      if (!order.contains(key)) order.add(key);
      if (name.isNotEmpty) names[key] = name;
      callIds[key] =
          (item['call_id'] as String?) ?? (item['id'] as String?) ?? key;
      final rawArguments = item['arguments'];
      if (rawArguments is String && rawArguments.isNotEmpty) {
        arguments[key] = StringBuffer(rawArguments);
      } else if (rawArguments is Map) {
        arguments[key] = StringBuffer(jsonEncode(rawArguments));
      }
    }

    void rememberCompletedPayload(Map<dynamic, dynamic> payload) {
      for (final call in extractToolCalls(payload)) {
        completed.add(call);
      }
    }

    for (final frame in frames) {
      final data = frame.data;
      rememberCompletedPayload(data);
      final response = data['response'];
      if (response is Map) rememberCompletedPayload(response);

      final item = data['item'];
      final itemId = data['item_id'] as String?;
      if (item is Map) rememberItem(item, itemId);

      final effectiveType = frame.eventType.isNotEmpty
          ? frame.eventType
          : data['type'] as String? ?? '';
      if (effectiveType.endsWith('function_call_arguments.delta')) {
        final key = itemId ?? data['call_id'] as String? ?? '';
        final delta = data['delta'] as String? ?? '';
        if (key.isNotEmpty && delta.isNotEmpty) {
          if (!order.contains(key)) order.add(key);
          arguments.putIfAbsent(key, StringBuffer.new).write(delta);
        }
      } else if (effectiveType.endsWith('function_call_arguments.done')) {
        final key = itemId ?? data['call_id'] as String? ?? '';
        final value = data['arguments'];
        if (key.isNotEmpty && value != null) {
          if (!order.contains(key)) order.add(key);
          arguments[key] = StringBuffer(
            value is String ? value : jsonEncode(value),
          );
        }
      }
    }

    for (final key in order) {
      final name = names[key] ?? '';
      if (name.isEmpty) continue;
      completed.add(
        ProviderToolCall(
          id: callIds[key] ?? key,
          name: name,
          arguments: _parseArguments(arguments[key]?.toString()),
        ),
      );
    }

    final unique = <String, ProviderToolCall>{};
    for (final call in completed) {
      unique['${call.id}:${call.name}'] = call;
    }
    return unique.values.toList(growable: false);
  }

  @override
  Map<String, Object?> toolProbePayload(
    String modelId,
    String toolName,
    String instruction, {
    String? providerId,
  }) {
    final payload = _responsesPayload(
      modelId,
      [
        {'role': 'user', 'content': instruction},
      ],
      stream: false,
      maxTokens: 64,
      temperature: 0,
    );
    payload['tools'] = [
      {
        'type': 'function',
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
        'strict': true,
      },
    ];
    payload['tool_choice'] = {'type': 'function', 'name': toolName};
    return payload;
  }

  @override
  Map<String, Object?> structuredProbePayload(
    String modelId,
    String instruction,
    Map<String, Object?> schema, {
    String? providerId,
  }) {
    final payload = _responsesPayload(
      modelId,
      [
        {'role': 'user', 'content': instruction},
      ],
      stream: false,
      maxTokens: 64,
      temperature: 0,
    );
    payload['text'] = {
      'format': {
        'type': 'json_schema',
        'name': 'capability_probe',
        'schema': schema,
        'strict': true,
      },
    };
    return payload;
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
