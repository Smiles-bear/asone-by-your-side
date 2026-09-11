import 'dart:convert';

import 'model_protocol_adapter.dart';
import 'model_output_contract.dart';
import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'protocol_types.dart';

/// Anthropic Messages API 适配器（/v1/messages）。
///
/// 覆盖 Claude 官方 + 中转原生协议。
class AnthropicMessagesAdapter extends ModelProtocolAdapter {
  @override
  String get protocolType => ProtocolType.anthropicMessages;

  @override
  Map<String, Object?> requireAnyToolPayload(Map<String, Object?> payload) => {
    ...payload,
    'tool_choice': {'type': 'any'},
  };

  @override
  List<String> candidateEndpoints(String baseUrl) {
    // Anthropic 端点规则：base 已含 /v1 → +messages；
    // base 已是 /messages → 直接用；否则 +v1/messages。
    // 同时提供 /v1 变体用于 404 补试。
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final variants = <String>[];

    String join(String b, String path) {
      var clean = path;
      while (clean.startsWith('/')) {
        clean = clean.substring(1);
      }
      final trimmed = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
      return '$trimmed/$clean';
    }

    if (base.endsWith('/v1')) {
      variants.add(join(base, 'messages'));
      // 补一个不带 /v1 的变体。
      final noV1 = base.substring(0, base.length - 3);
      if (noV1.isNotEmpty) variants.add(join(noV1, 'v1/messages'));
    } else if (base.endsWith('/messages')) {
      variants.add(base);
    } else {
      variants.add(join(base, 'v1/messages'));
      // 补一个 base+/messages 变体（部分中转把 /v1 省略）。
      variants.add(join(base, 'messages'));
    }
    return variants.toSet().toList();
  }

  @override
  Map<String, String> headers(String baseUrl, String apiKey) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    'anthropic-version': '2023-06-01',
    if (apiKey.isNotEmpty) 'x-api-key': apiKey,
  };

  /// 把 OpenAI 风格 messages 转成 Anthropic messages + system。
  /// 返回 {system: String, messages: List}。
  Map<String, Object?> _convertMessages(List<Map<String, Object?>> messages) {
    final systemParts = <String>[];
    final converted = <Map<String, Object?>>[];
    for (final message in messages) {
      final role = (message['role'] as String?) ?? 'user';
      final content = message['content'] ?? '';

      if (role == 'system') {
        systemParts.add(contentText(content));
        continue;
      }

      // 处理 tool 角色 → 转换为 user 消息的 tool_result block
      if (role == 'tool') {
        final toolCallId = message['tool_call_id'] as String?;
        final toolContent = contentText(content);
        converted.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolCallId ?? '',
              'content': toolContent,
            },
          ],
        });
        continue;
      }

      final targetRole = role == 'assistant' ? 'assistant' : 'user';
      final blocks = <Map<String, Object?>>[];

      if (content is String) {
        blocks.add({'type': 'text', 'text': content});
      } else if (content is List) {
        for (final part in content) {
          if (part is! Map) continue;
          final type = part['type'];
          if (type == 'text' || type == 'input_text') {
            blocks.add({'type': 'text', 'text': part['text'] ?? ''});
          } else if (type == 'image_url' || type == 'input_image') {
            final raw = part['image_url'];
            final url = raw is Map ? (raw['url'] as String?) : (raw as String?);
            if (url != null &&
                url.startsWith('data:') &&
                url.contains(';base64,')) {
              final comma = url.indexOf(',');
              final header = url.substring(5, url.indexOf(';'));
              final encoded = url.substring(comma + 1);
              final mediaType = header.isEmpty ? 'image/jpeg' : header;
              blocks.add({
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': mediaType,
                  'data': encoded,
                },
              });
            } else if (url != null && url.isNotEmpty) {
              blocks.add({
                'type': 'image',
                'source': {'type': 'url', 'url': url},
              });
            }
          } else if (type == 'file_data') {
            final data = part['data'] as String?;
            if (data != null && data.isNotEmpty) {
              blocks.add({
                'type': 'document',
                'source': {
                  'type': 'base64',
                  'media_type': part['mime_type'] ?? 'application/pdf',
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

            Map<String, dynamic> input = {};
            if (argsStr != null && argsStr.isNotEmpty) {
              try {
                final decoded = jsonDecode(argsStr);
                if (decoded is Map) {
                  input = Map<String, dynamic>.from(decoded);
                }
              } catch (_) {}
            }

            blocks.add({
              'type': 'tool_use',
              'id': call['id'] ?? name,
              'name': name,
              'input': input,
            });
          }
        }
      }

      converted.add({'role': targetRole, 'content': blocks});
    }
    return {'system': systemParts.join('\n\n'), 'messages': converted};
  }

  Map<String, Object?> _payload(
    String modelId,
    List<Map<String, Object?>> messages, {
    bool stream = false,
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  }) {
    final converted = _convertMessages(messages);
    final payload = <String, Object?>{
      'model': modelId,
      'messages': converted['messages'],
      'stream': stream,
      'temperature': temperature,
      'max_tokens': maxTokens ?? 1024,
    };
    final system = converted['system'] as String;
    if (system.isNotEmpty) payload['system'] = system;

    // 转换 OpenAI 格式的 tools 到 Anthropic 格式
    if (tools != null && tools.isNotEmpty) {
      final anthropicTools = <Map<String, Object?>>[];
      for (final tool in tools) {
        if (tool['type'] == 'function') {
          final func = tool['function'] as Map<String, Object?>?;
          if (func != null) {
            anthropicTools.add({
              'name': func['name'],
              'description': func['description'] ?? '',
              'input_schema':
                  func['parameters'] ?? {'type': 'object', 'properties': {}},
            });
          }
        }
      }
      if (anthropicTools.isNotEmpty) {
        payload['tools'] = anthropicTools;
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
  }) => _payload(
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
      final outputConfig = Map<String, Object?>.from(
        payload['output_config'] as Map? ?? const {},
      );
      outputConfig['effort'] = 'low';
      payload['output_config'] = outputConfig;
    }
    final schema = contract.schema;
    if (contract.requiresStructuredData && schema != null) {
      if (structuredTransport == StructuredOutputTransport.forcedTool) {
        payload['tools'] = [
          {
            'name': contract.schemaName,
            'description': '返回业务所需的结构化结果，不执行外部操作。',
            'input_schema': schema,
          },
        ];
        payload['tool_choice'] = {'type': 'tool', 'name': contract.schemaName};
      } else if (structuredTransport != StructuredOutputTransport.promptJson) {
        throw StateError('当前 Anthropic 配置没有可用的结构化输出通道');
      }
    }
    return payload;
  }

  @override
  String extractText(Map<dynamic, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) return '';
    final parts = <String>[];
    for (final part in content) {
      if (part is! Map) continue;
      if (part['type'] == 'text') {
        final text = part['text'];
        if (text is String) parts.add(text);
      }
    }
    return parts.join();
  }

  @override
  String extractReasoning(Map<dynamic, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) return '';
    final parts = <String>[];
    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type'];
      if (type == 'thinking' || type == 'signature') {
        final text = part['thinking'] ?? part['text'];
        if (text is String) parts.add(text);
      }
    }
    return parts.join();
  }

  @override
  List<ProviderToolCall> extractToolCalls(Map<dynamic, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) return const [];
    final calls = <ProviderToolCall>[];
    for (final part in content) {
      if (part is! Map || part['type'] != 'tool_use') continue;
      final name = (part['name'] as String?) ?? '';
      if (name.isEmpty) continue;
      calls.add(
        ProviderToolCall(
          id: (part['id'] as String?) ?? name,
          name: name,
          arguments: _parseArguments(part['input']),
        ),
      );
    }
    return calls;
  }

  @override
  String streamTextFromFrame(SseFrame frame) {
    final kind = frame.eventType.isNotEmpty
        ? frame.eventType
        : (frame.data['type'] as String?) ?? '';
    if (kind == 'content_block_delta') {
      final delta = frame.data['delta'];
      if (delta is Map && delta['type'] == 'text_delta') {
        return (delta['text'] as String?) ?? '';
      }
    }
    return '';
  }

  @override
  String streamReasoningFromFrame(SseFrame frame) {
    final kind = frame.eventType.isNotEmpty
        ? frame.eventType
        : (frame.data['type'] as String?) ?? '';

    // AsOne 桌面端验证逻辑
    if (kind == 'content_block_delta') {
      final delta = frame.data['delta'];
      if (delta is Map) {
        final deltaType = delta['type'];
        if (deltaType == 'thinking_delta' || deltaType == 'signature_delta') {
          return (delta['thinking'] as String?) ??
              (delta['text'] as String?) ??
              '';
        }
      }
    }
    return '';
  }

  @override
  ProviderStreamTerminal streamTerminalFromFrame(SseFrame frame) {
    final kind = frame.eventType.isNotEmpty
        ? frame.eventType
        : frame.data['type']?.toString() ?? '';
    if (kind == 'message_delta') {
      final delta = frame.data['delta'];
      final stopReason = delta is Map ? delta['stop_reason']?.toString() : null;
      if (stopReason == 'end_turn' ||
          stopReason == 'stop_sequence' ||
          stopReason == 'tool_use') {
        return ProviderStreamTerminal.success('stop_reason:$stopReason');
      }
      if (stopReason != null && stopReason.isNotEmpty) {
        return ProviderStreamTerminal.failure('stop_reason:$stopReason');
      }
    }
    if (kind == 'message_stop') {
      return const ProviderStreamTerminal.success('message_stop');
    }
    if (kind == 'error' || frame.data['error'] != null) {
      return ProviderStreamTerminal.failure(
        streamFailureReason(frame.data, fallback: 'anthropic_error'),
      );
    }
    return const ProviderStreamTerminal.none();
  }

  @override
  List<ProviderToolCall> streamExtractToolCalls(List<SseFrame> frames) {
    // Anthropic 流式工具调用：
    // 1. content_block_start (type=tool_use) 包含 id 和 name
    // 2. content_block_delta (type=input_json_delta) 累积 input JSON
    final toolBlocks = <String, Map<String, dynamic>>{};

    for (final frame in frames) {
      final kind = frame.eventType.isNotEmpty
          ? frame.eventType
          : (frame.data['type'] as String?) ?? '';

      if (kind == 'content_block_start') {
        final block = frame.data['content_block'];
        if (block is Map && block['type'] == 'tool_use') {
          final id = (block['id'] as String?) ?? '';
          final name = (block['name'] as String?) ?? '';
          if (id.isNotEmpty && name.isNotEmpty) {
            toolBlocks[id] = {'name': name, 'input_json': ''};
          }
        }
      } else if (kind == 'content_block_delta') {
        final delta = frame.data['delta'];
        if (delta is Map && delta['type'] == 'input_json_delta') {
          final index = frame.data['index'] as int?;
          if (index != null) {
            // 通过 index 找到对应的 tool block（按顺序）
            final keys = toolBlocks.keys.toList();
            if (index < keys.length) {
              final id = keys[index];
              final partial = (delta['partial_json'] as String?) ?? '';
              toolBlocks[id]!['input_json'] =
                  (toolBlocks[id]!['input_json'] as String) + partial;
            }
          }
        }
      }
    }

    final calls = <ProviderToolCall>[];
    for (final entry in toolBlocks.entries) {
      final id = entry.key;
      final name = entry.value['name'] as String;
      final inputJson = entry.value['input_json'] as String;

      Map<String, dynamic> arguments = {};
      if (inputJson.isNotEmpty) {
        try {
          arguments = _parseArguments(jsonDecode(inputJson));
        } catch (_) {
          // JSON 解析失败，使用空参数
        }
      }

      calls.add(ProviderToolCall(id: id, name: name, arguments: arguments));
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
    final payload = _payload(
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
        'name': toolName,
        'description': '用于验证客户端工具调用，不执行任何外部操作。',
        'input_schema': {
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
    ];
    payload['tool_choice'] = {'type': 'tool', 'name': toolName};
    return payload;
  }

  @override
  bool structuredViaTool() => true;

  @override
  Map<String, Object?> structuredProbePayload(
    String modelId,
    String instruction,
    Map<String, Object?> schema, {
    String? providerId,
  }) {
    // Anthropic 通过 forced tool 实现结构化输出。
    final payload = _payload(
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
        'name': 'asone_structured_test',
        'description': '返回结构化结果，不执行任何外部操作。',
        'input_schema': schema,
      },
    ];
    payload['tool_choice'] = {'type': 'tool', 'name': 'asone_structured_test'};
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
