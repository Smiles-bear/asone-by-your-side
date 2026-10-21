import 'prompt_context_layout.dart';
import 'dart:convert';

import 'model_protocol_adapter.dart';
import 'model_output_contract.dart';
import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'protocol_types.dart';
import 'provider_response_aggregation.dart';

part 'openai_responses_stream_tool_calls.dart';

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
    for (final message in layoutPromptContext(messages)) {
      final role = (message['role'] as String?) ?? 'user';
      final content = message['content'] ?? '';
      final native = message['_provider_continuation'];
      if (role == 'assistant' &&
          native is Map &&
          native['protocol'] == protocolType &&
          native['items'] is List) {
        result.addAll(
          (native['items'] as List).whereType<Map>().map(
            (item) => item.cast<String, Object?>(),
          ),
        );
        continue;
      }
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
        _appendAssistantToolCalls(result, role, content, toolCalls);
        continue;
      }
      if (content is String) {
        result.add({'role': role, 'content': content});
        continue;
      }
      if (content is List) {
        result.add({'role': role, 'content': _inputContentParts(content)});
      } else {
        result.add({'role': role, 'content': ''});
      }
    }
    return result;
  }

  void _appendAssistantToolCalls(
    List<Map<String, Object?>> result,
    String role,
    Object content,
    List toolCalls,
  ) {
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
  }

  List<Map<String, Object?>> _inputContentParts(List content) {
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
    return parts;
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
    applyOutputContractPolicy(
      payload,
      protocol: protocolType,
      providerId: providerId ?? '',
      contract: contract,
    );
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
        _appendOutputText(item, textParts);
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
        _appendReasoningItem(item, reasoningParts);
      }
    }
    return reasoningParts.join('\n');
  }

  void _appendOutputText(Object? item, List<String> parts) {
    if (item is! Map) return;
    final content = item['content'];
    if (content is! List) return;
    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type'];
      if (type == 'output_text' || type == 'text') {
        final text = part['text'];
        if (text is String) parts.add(text);
      }
    }
  }

  void _appendReasoningItem(Object? item, List<String> parts) {
    if (item is! Map || item['type'] != 'reasoning') return;
    final summary = item['summary'];
    if (summary is List) {
      for (final part in summary) {
        if (part is Map && part['text'] is String) {
          parts.add(part['text'] as String);
        }
      }
    }
    final content = item['content'];
    if (content is! List) return;
    for (final part in content) {
      if (part is Map &&
          (part['type'] == 'reasoning_text' || part['type'] == 'text') &&
          part['text'] is String) {
        parts.add(part['text'] as String);
      }
    }
  }

  @override
  List<ProviderToolCall> extractToolCalls(Map<dynamic, dynamic> payload) =>
      _receivedCalls(aggregateProviderPayload(this, payload));

  @override
  Map<String, Object?>? extractNativeContinuation(
    Map<dynamic, dynamic> payload,
  ) {
    final output = payload['output'];
    if (output is! List || output.isEmpty) return null;
    final items = output
        .whereType<Map>()
        .where(
          (item) => const <String>{
            'reasoning',
            'function_call',
            'tool_call',
            'message',
          }.contains(item['type']),
        )
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
    if (items.isEmpty) return null;
    return <String, Object?>{'protocol': protocolType, 'items': items};
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
    final nested = frame.data['response'];
    final response = nested is Map ? nested : frame.data;
    final status = response['status'];
    if (effectiveType == 'response.failed' ||
        effectiveType == 'response.incomplete' ||
        status == 'failed' ||
        status == 'incomplete' ||
        response['error'] != null ||
        response['incomplete_details'] != null ||
        effectiveType == 'error' ||
        frame.data['error'] != null ||
        typeField == 'upstream_error') {
      return ProviderStreamTerminal.failure(
        streamFailureReason(frame.data, fallback: effectiveType),
      );
    }
    if (effectiveType == 'response.completed' || status == 'completed') {
      return const ProviderStreamTerminal.success('response.completed');
    }
    return const ProviderStreamTerminal.none();
  }

  @override
  List<ProviderToolCall> streamExtractToolCalls(List<SseFrame> frames) =>
      (_ResponsesToolCallAccumulator(this)..addFrames(frames)).finish();

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
              'enum': [expectedCode],
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
