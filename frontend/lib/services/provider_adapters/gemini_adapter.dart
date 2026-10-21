import 'prompt_context_layout.dart';
import '../model_endpoint.dart';

import 'model_protocol_adapter.dart';
import 'model_output_contract.dart';
import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'protocol_types.dart';
import 'provider_response_aggregation.dart';
import 'tool_argument_parser.dart';

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
    final base = protocolModelBaseUrl(baseUrl, protocolType);
    return [base];
  }

  /// 运行时端点（非流式）。
  String generateContentEndpoint(String baseUrl, String modelId) {
    return joinEndpoint(
      protocolModelBaseUrl(baseUrl, protocolType),
      '${_modelName(modelId)}:generateContent',
    );
  }

  /// 运行时端点（流式）。
  String streamGenerateContentEndpoint(String baseUrl, String modelId) {
    return joinEndpoint(
      protocolModelBaseUrl(baseUrl, protocolType),
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
    final nativeCallNames = <String, String>{};
    final localCallNames = <String, String>{};
    final associationNativeIds = <String, String?>{};
    for (final message in layoutPromptContext(messages)) {
      final role = (message['role'] as String?) ?? 'user';
      final content = message['content'] ?? '';

      if (role == 'system') {
        systemParts.add(contentText(content));
        continue;
      }

      // 处理 tool 角色 → 转换为 user 角色的 functionResponse part
      if (role == 'tool') {
        final toolCallId = message['tool_call_id'] as String?;
        final toolName = message['tool_name'] as String?;
        final toolContent = contentText(content);
        final nativeId = associationNativeIds.containsKey(toolCallId)
            ? associationNativeIds[toolCallId]
            : nativeCallNames.containsKey(toolCallId)
            ? toolCallId
            : null;
        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                if (nativeId != null) 'id': nativeId,
                'name':
                    toolName ??
                    localCallNames[toolCallId] ??
                    nativeCallNames[toolCallId] ??
                    toolCallId ??
                    'unknown',
                'response': {'result': toolContent},
              },
            },
          ],
        });
        continue;
      }

      final parts = <Map<String, Object?>>[];
      final native = message['_provider_continuation'];
      if (role == 'assistant' &&
          native is Map &&
          native['protocol'] == protocolType &&
          native['items'] is List) {
        parts.addAll(_nativeContinuationParts(native['items'] as List));
        if (parts.isEmpty) {
          throw const FormatException(
            'Gemini native continuation has no parts',
          );
        }
        for (final part in parts) {
          final call = part['functionCall'];
          if (call is Map && call['id'] is String && call['name'] is String) {
            nativeCallNames[call['id'] as String] = call['name'] as String;
          }
        }
        final associations = native['tool_associations'];
        if (associations is List) {
          for (final association in associations.whereType<Map>()) {
            if (association['id'] is String && association['name'] is String) {
              localCallNames[association['id'] as String] =
                  association['name'] as String;
              final nativeId = association['native_id'];
              if (nativeId == null || nativeId is String) {
                associationNativeIds[association['id'] as String] =
                    nativeId as String?;
              }
            }
          }
        }
        contents.add({'role': 'model', 'parts': parts});
        continue;
      }
      _appendContentBlocks(parts, content);

      if (role == 'assistant') {
        _appendToolCalls(parts, message['tool_calls']);
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

  void _appendToolCalls(List<Map<String, Object?>> parts, Object? raw) {
    final toolCalls = raw as List?;
    if (toolCalls == null) return;
    for (final call in toolCalls) {
      if (call is! Map) continue;
      final func = call['function'] as Map?;
      if (func == null) continue;
      final name = func['name'] as String?;
      final argsStr = func['arguments'] as String?;
      if (name == null) continue;
      parts.add({
        'functionCall': {
          'name': name,
          'args': _decodeFunctionArguments(argsStr),
        },
      });
    }
  }

  Map<String, dynamic> _decodeFunctionArguments(String? raw) {
    return requireToolArguments(raw);
  }

  void _appendContentBlocks(List<Map<String, Object?>> parts, Object? content) {
    if (content is String) {
      parts.add({'text': content});
    } else if (content is List) {
      for (final part in content) {
        if (part is! Map) continue;
        final type = part['type'];
        if (type == 'text' || type == 'input_text') {
          parts.add({'text': part['text'] ?? ''});
        } else if (type == 'image_url' || type == 'input_image') {
          final image = _inlineImageBlock(part['image_url']);
          if (image != null) parts.add(image);
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
  }

  Map<String, Object?>? _inlineImageBlock(Object? raw) {
    final url = raw is Map ? (raw['url'] as String?) : (raw as String?);
    if (url == null || !url.startsWith('data:') || !url.contains(';base64,')) {
      return null;
    }
    final comma = url.indexOf(',');
    final header = url.substring(5, url.indexOf(';'));
    final encoded = url.substring(comma + 1);
    final mime = header.isEmpty ? 'image/jpeg' : header;
    return {
      'inlineData': {'mimeType': mime, 'data': encoded},
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
    applyOutputContractPolicy(
      payload,
      protocol: protocolType,
      providerId: providerId ?? '',
      contract: contract,
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
  List<ProviderToolCall> extractToolCalls(Map<dynamic, dynamic> payload) =>
      _receivedCalls(aggregateProviderPayload(this, payload));

  @override
  Map<String, Object?>? extractNativeContinuation(
    Map<dynamic, dynamic> payload,
  ) {
    final candidates = payload['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      return null;
    }
    final content = (candidates.first as Map)['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List || parts.isEmpty) return null;
    final nativeParts = _nativeContinuationParts(parts);
    if (nativeParts.isEmpty) return null;
    return <String, Object?>{'protocol': protocolType, 'items': nativeParts};
  }

  List<Map<String, Object?>> _nativeContinuationParts(List parts) => [
    for (final part in parts.whereType<Map>())
      if (part.length != 1 || part['text'] != '')
        Map<String, Object?>.from(part),
  ];

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
    final feedback = frame.data['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      return ProviderStreamTerminal.failure(
        'prompt_block:${feedback['blockReason']}',
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
  List<ProviderToolCall> streamExtractToolCalls(List<SseFrame> frames) =>
      _receivedCalls(aggregateProviderFrames(this, frames));

  @override
  Map<String, Object?>? streamExtractNativeContinuation(
    List<SseFrame> frames,
  ) => aggregateProviderFrames(this, frames).nativeContinuation;

  @override
  Map<String, Object?> toolProbePayload(
    String modelId,
    String toolName,
    String instruction, {
    String? providerId,
    String expectedCode = 'AZ731',
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
                  'enum': [expectedCode],
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
    for (final key in const [
      'description',
      'title',
      'format',
      'nullable',
      'minimum',
      'maximum',
      'minItems',
      'maxItems',
      'minLength',
      'maxLength',
      'pattern',
      'minProperties',
      'maxProperties',
      'propertyOrdering',
      'default',
      'example',
    ]) {
      if (schema.containsKey(key)) result[key] = schema[key];
    }
    final type = schema['type'];
    if (type is String) {
      result['type'] = type.toUpperCase();
    } else if (type is List) {
      final nonNull = type.where((value) => value != 'null').toList();
      if (type.contains('null')) result['nullable'] = true;
      if (nonNull.length == 1 && nonNull.single is String) {
        result['type'] = (nonNull.single as String).toUpperCase();
      } else if (nonNull.isNotEmpty) {
        result['anyOf'] = [
          for (final value in nonNull) _convertSchemaToGemini({'type': value}),
        ];
      } else {
        result['type'] = 'NULL';
      }
    }
    final items = schema['items'];
    if (items is Map) result['items'] = _convertSchemaToGemini(items);
    final alternatives = schema['anyOf'];
    if (alternatives is List) {
      result['anyOf'] = alternatives
          .whereType<Map>()
          .map(_convertSchemaToGemini)
          .toList();
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

  // Legacy extraction returns reception data; dispatch gates use the shared result.
  List<ProviderToolCall> _receivedCalls(ProviderResponse response) {
    if (response.toolReceptions.any(
          (tool) => tool.state != ProviderToolArgumentState.valid,
        ) ||
        response.parsingIssues.isNotEmpty) {
      throw const FormatException('invalid_tool_reception');
    }
    return [
      for (final tool in response.toolReceptions)
        ProviderToolCall(
          id: tool.id,
          nativeId: tool.nativeId,
          name: tool.name,
          arguments: tool.arguments!,
        ),
    ];
  }
}
