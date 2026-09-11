import 'dart:convert';

import 'model_protocol_adapter.dart';
import 'model_output_contract.dart';
import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'protocol_types.dart';

/// Google Gemini generateContent 适配器。
///
/// 端点：base + /v1beta/models/{model}:generateContent
/// 流式：base + /v1beta/models/{model}:streamGenerateContent?alt=sse
/// 鉴权：x-goog-api-key
class GeminiAdapter extends ModelProtocolAdapter {
  @override
  String get protocolType => ProtocolType.gemini;

  @override
  Map<String, Object?> requireAnyToolPayload(Map<String, Object?> payload) => {
    ...payload,
    'toolConfig': {
      'functionCallingConfig': {'mode': 'ANY'},
    },
  };

  String _modelName(String modelId) {
    final value = modelId.trim();
    return value.startsWith('models/') ? value : 'models/$value';
  }

  @override
  List<String> candidateEndpoints(String baseUrl) {
    // Gemini 非流式端点在运行时根据 modelId 拼接，这里返回 base 变体。
    // 实际端点由 runtimeEndpoint 生成。
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return [base];
  }

  /// 运行时端点（非流式）。
  String generateContentEndpoint(String baseUrl, String modelId) {
    return joinEndpoint(baseUrl, '${_modelName(modelId)}:generateContent');
  }

  /// 运行时端点（流式）。
  String streamGenerateContentEndpoint(String baseUrl, String modelId) {
    return joinEndpoint(
      baseUrl,
      '${_modelName(modelId)}:streamGenerateContent?alt=sse',
    );
  }

  @override
  Map<String, String> headers(String baseUrl, String apiKey) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    if (apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
  };

  /// 把 OpenAI 风格 messages 转成 Gemini contents + systemInstruction。
  Map<String, Object?> _convertMessages(List<Map<String, Object?>> messages) {
    final systemParts = <String>[];
    final contents = <Map<String, Object?>>[];
    for (final message in messages) {
      final role = (message['role'] as String?) ?? 'user';
      final content = message['content'] ?? '';

      if (role == 'system') {
        systemParts.add(contentText(content));
        continue;
      }

      // 处理 tool 角色 → 转换为 user 角色的 functionResponse part
      if (role == 'tool') {
        final toolCallId = message['tool_call_id'] as String?;
        final toolContent = contentText(content);
        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': toolCallId ?? 'unknown',
                'response': {'result': toolContent},
              },
            },
          ],
        });
        continue;
      }

      final parts = <Map<String, Object?>>[];
      if (content is String) {
        parts.add({'text': content});
      } else if (content is List) {
        for (final part in content) {
          if (part is! Map) continue;
          final type = part['type'];
          if (type == 'text' || type == 'input_text') {
            parts.add({'text': part['text'] ?? ''});
          } else if (type == 'image_url' || type == 'input_image') {
            final raw = part['image_url'];
            final url = raw is Map ? (raw['url'] as String?) : (raw as String?);
            if (url != null &&
                url.startsWith('data:') &&
                url.contains(';base64,')) {
              final comma = url.indexOf(',');
              final header = url.substring(5, url.indexOf(';'));
              final encoded = url.substring(comma + 1);
              final mime = header.isEmpty ? 'image/jpeg' : header;
              parts.add({
                'inlineData': {'mimeType': mime, 'data': encoded},
              });
            }
          } else if (type == 'file_data') {
            final data = part['data'] as String?;
            if (data != null && data.isNotEmpty) {
              parts.add({
                'inlineData': {
                  'mimeType': part['mime_type'] ?? 'application/pdf',
                  'data': data,
                },
              });
            }
          }
        }
      }

      // 处理 assistant 消息的 tool_calls
      if (role == 'assistant' && message['tool_calls'] != null) {
        final toolCalls = message['tool_calls'] as List?;
        if (toolCalls != null) {
          for (final call in toolCalls) {
            if (call is! Map) continue;
            final func = call['function'] as Map?;
            if (func == null) continue;
            final name = func['name'] as String?;
            final argsStr = func['arguments'] as String?;
            if (name == null) continue;

            Map<String, dynamic> args = {};
            if (argsStr != null && argsStr.isNotEmpty) {
              try {
                final decoded = jsonDecode(argsStr);
                if (decoded is Map) {
                  args = Map<String, dynamic>.from(decoded);
                }
              } catch (_) {}
            }

            parts.add({
              'functionCall': {'name': name, 'args': args},
            });
          }
        }
      }

      contents.add({
        'role': role == 'assistant' ? 'model' : 'user',
        'parts': parts,
      });
    }
    return {
      'systemInstruction': systemParts.join('\n\n'),
      'contents': contents,
    };
  }

  Map<String, Object?> _payload(
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) {
    final converted = _convertMessages(messages);
    final generationConfig = <String, Object?>{'temperature': temperature};
    if (maxTokens != null) generationConfig['maxOutputTokens'] = maxTokens;
    final payload = <String, Object?>{
      'contents': converted['contents'],
      'generationConfig': generationConfig,
    };
    final system = converted['systemInstruction'] as String;
    if (system.isNotEmpty) {
      payload['systemInstruction'] = {
        'parts': [
          {'text': system},
        ],
      };
    }

    // 转换 OpenAI 格式的 tools 到 Gemini 格式
    if (tools != null && tools.isNotEmpty) {
      final functionDeclarations = <Map<String, Object?>>[];
      for (final tool in tools) {
        if (tool['type'] == 'function') {
          final func = tool['function'] as Map<String, Object?>?;
          if (func != null) {
            final params = func['parameters'] as Map<String, Object?>? ?? {};
            functionDeclarations.add({
              'name': func['name'],
              'description': func['description'] ?? '',
              'parameters': _convertSchemaToGemini(params),
            });
          }
        }
      }
      if (functionDeclarations.isNotEmpty) {
        payload['tools'] = [
          {'functionDeclarations': functionDeclarations},
        ];
      }
    }

    return payload;
  }

  @override
  Map<String, Object?> textPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) => _payload(
    messages,
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
  }) => _payload(
    messages,
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
    final schema = contract.schema;
    if (contract.requiresStructuredData && schema != null) {
      if (structuredTransport == StructuredOutputTransport.geminiSchema) {
        final config = payload['generationConfig'] as Map;
        config['responseMimeType'] = 'application/json';
        config['responseSchema'] = _convertSchemaToGemini(schema);
      } else if (structuredTransport != StructuredOutputTransport.promptJson) {
        throw StateError('当前 Gemini 配置没有可用的结构化输出通道');
      }
    }
    return payload;
  }

  @override
  Map<String, Object?> audioPayload(
    String modelId,
    List<Map<String, Object?>> messages,
    AudioPayloadData audio, {
    int? maxTokens,
    String? instruction,
  }) {
    final payload = _payload(messages, maxTokens: maxTokens, temperature: 0);
    final contents = (payload['contents'] as List).cast<Map<String, Object?>>();
    contents.add({
      'role': 'user',
      'parts': [
        {'text': instruction ?? '请描述这段短音频。'},
        {
          'inlineData': {'mimeType': audio.mimeType, 'data': audio.base64Data},
        },
      ],
    });
    return payload;
  }

  @override
  String extractText(Map<dynamic, dynamic> payload) {
    final candidates = payload['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final candidate = candidates.first;
    if (candidate is! Map) return '';
    final content = candidate['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List) return '';
    final textParts = <String>[];
    for (final part in parts) {
      if (part is! Map) continue;
      // AsOne 桌面端逻辑：排除 thought == true 的部分
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String) textParts.add(text);
    }
    return textParts.join();
  }

  @override
  String extractReasoning(Map<dynamic, dynamic> payload) {
    final candidates = payload['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final candidate = candidates.first;
    if (candidate is! Map) return '';
    final content = candidate['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is List) {
      final reasoningParts = <String>[];
      for (final part in parts) {
        if (part is! Map) continue;
        if (part['thought'] == true) {
          final text = part['text'];
          if (text is String) reasoningParts.add(text);
        }
      }
      return reasoningParts.join();
    }
    return '';
  }

  @override
  List<ProviderToolCall> extractToolCalls(Map<dynamic, dynamic> payload) {
    final candidates = payload['candidates'];
    if (candidates is! List) return const [];
    final calls = <ProviderToolCall>[];
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      final content = candidate['content'];
      if (content is! Map) continue;
      final parts = content['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map) continue;
          final call = part['functionCall'];
          if (call is! Map) continue;
          final name = (call['name'] as String?) ?? '';
          if (name.isEmpty) continue;
          calls.add(
            ProviderToolCall(
              id: (call['id'] as String?) ?? name,
              name: name,
              arguments: _parseArguments(call['args']),
            ),
          );
        }
      }
    }
    return calls;
  }

  @override
  String streamTextFromFrame(SseFrame frame) {
    // Gemini streamGenerateContent 每个 data 帧就是一个完整 candidates 响应。
    return extractText(frame.data);
  }

  @override
  String streamReasoningFromFrame(SseFrame frame) =>
      extractReasoning(frame.data);

  @override
  ProviderStreamTerminal streamTerminalFromFrame(SseFrame frame) {
    if (frame.data['error'] != null) {
      return ProviderStreamTerminal.failure(
        streamFailureReason(frame.data, fallback: 'gemini_error'),
      );
    }
    final candidates = frame.data['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      return const ProviderStreamTerminal.none();
    }
    final finishReason = (candidates.first as Map)['finishReason']?.toString();
    if (finishReason == null || finishReason.isEmpty) {
      return const ProviderStreamTerminal.none();
    }
    if (finishReason == 'STOP') {
      return ProviderStreamTerminal.success('finish_reason:$finishReason');
    }
    return ProviderStreamTerminal.failure('finish_reason:$finishReason');
  }

  @override
  List<ProviderToolCall> streamExtractToolCalls(List<SseFrame> frames) {
    // Gemini 流式：每个帧包含完整的 candidates 结构
    // 从最后一个包含工具调用的帧提取（流式累积，最后一帧最完整）
    for (final frame in frames.reversed) {
      final calls = extractToolCalls(frame.data);
      if (calls.isNotEmpty) return calls;
    }
    return const [];
  }

  @override
  Map<String, Object?> toolProbePayload(
    String modelId,
    String toolName,
    String instruction, {
    String? providerId,
  }) {
    final payload = _payload(
      [
        {'role': 'user', 'content': instruction},
      ],
      maxTokens: 64,
      temperature: 0,
    );
    payload['tools'] = [
      {
        'functionDeclarations': [
          {
            'name': toolName,
            'description': '用于验证客户端工具调用，不执行任何外部操作。',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'code': {
                  'type': 'STRING',
                  'enum': ['AZ731'],
                },
              },
              'required': ['code'],
            },
          },
        ],
      },
    ];
    payload['toolConfig'] = {
      'functionCallingConfig': {
        'mode': 'ANY',
        'allowedFunctionNames': [toolName],
      },
    };
    return payload;
  }

  @override
  Map<String, Object?> structuredProbePayload(
    String modelId,
    String instruction,
    Map<String, Object?> schema, {
    String? providerId,
  }) {
    final payload = _payload(
      [
        {'role': 'user', 'content': instruction},
      ],
      maxTokens: 64,
      temperature: 0,
    );
    // Gemini 的 schema 类型用大写。
    final geminiSchema = _convertSchemaToGemini(schema);
    (payload['generationConfig'] as Map)['responseMimeType'] =
        'application/json';
    (payload['generationConfig'] as Map)['responseSchema'] = geminiSchema;
    return payload;
  }

  /// 把 OpenAI 风格 schema（小写 type）转成 Gemini 风格（大写 type）。
  Map<String, Object?> _convertSchemaToGemini(Map<dynamic, dynamic> schema) {
    final result = <String, Object?>{};
    final type = schema['type'];
    if (type is String) {
      result['type'] = type.toUpperCase();
    }
    final properties = schema['properties'];
    if (properties is Map) {
      final converted = <String, Object?>{};
      for (final entry in properties.entries) {
        if (entry.value is Map) {
          converted[entry.key as String] = _convertSchemaToGemini(
            entry.value as Map,
          );
        }
      }
      result['properties'] = converted;
    }
    final required = schema['required'];
    if (required is List) {
      result['required'] = required;
    }
    final enumValues = schema['enum'];
    if (enumValues is List) {
      result['enum'] = enumValues;
    }
    return result;
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
