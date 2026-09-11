import 'dart:convert';

enum ModelOutputKind {
  freeText,
  shortScalar,
  structuredJson,
  toolArguments,
  svgDocument,
  labeledText,
}

enum ModelReasoningPolicy { providerDefault, low, disabledPreferred }

enum StructuredOutputTransport {
  unknown,
  jsonSchema,
  jsonObject,
  forcedTool,
  geminiSchema,
  promptJson,
}

class ModelOutputContract {
  const ModelOutputContract({
    required this.kind,
    this.schemaName = 'asone_output',
    this.schema,
    this.reasoningPolicy = ModelReasoningPolicy.providerDefault,
    this.allowedStructuredTransports = const {
      StructuredOutputTransport.jsonSchema,
      StructuredOutputTransport.jsonObject,
      StructuredOutputTransport.forcedTool,
      StructuredOutputTransport.geminiSchema,
      StructuredOutputTransport.promptJson,
    },
  });

  const ModelOutputContract.freeText({
    this.reasoningPolicy = ModelReasoningPolicy.providerDefault,
  }) : kind = ModelOutputKind.freeText,
       schemaName = 'asone_output',
       schema = null,
       allowedStructuredTransports = const {};

  const ModelOutputContract.shortScalar()
    : kind = ModelOutputKind.shortScalar,
      schemaName = 'asone_output',
      schema = null,
      allowedStructuredTransports = const {},
      reasoningPolicy = ModelReasoningPolicy.disabledPreferred;

  const ModelOutputContract.structuredJson({
    required this.schemaName,
    required Map<String, Object?> this.schema,
    this.reasoningPolicy = ModelReasoningPolicy.disabledPreferred,
    this.allowedStructuredTransports = const {
      StructuredOutputTransport.jsonSchema,
      StructuredOutputTransport.jsonObject,
      StructuredOutputTransport.forcedTool,
      StructuredOutputTransport.geminiSchema,
      StructuredOutputTransport.promptJson,
    },
  }) : kind = ModelOutputKind.structuredJson;

  const ModelOutputContract.svgDocument()
    : kind = ModelOutputKind.svgDocument,
      schemaName = 'asone_output',
      schema = null,
      allowedStructuredTransports = const {},
      reasoningPolicy = ModelReasoningPolicy.low;

  const ModelOutputContract.labeledText()
    : kind = ModelOutputKind.labeledText,
      schemaName = 'asone_output',
      schema = null,
      allowedStructuredTransports = const {},
      reasoningPolicy = ModelReasoningPolicy.low;

  final ModelOutputKind kind;
  final String schemaName;
  final Map<String, Object?>? schema;
  final ModelReasoningPolicy reasoningPolicy;
  final Set<StructuredOutputTransport> allowedStructuredTransports;

  bool get requiresStructuredData =>
      kind == ModelOutputKind.structuredJson ||
      kind == ModelOutputKind.toolArguments;
}

class ModelCapabilityProfile {
  const ModelCapabilityProfile({
    this.structuredVerdict = 'unconfirmed',
    this.textVerdict = 'unconfirmed',
    this.structuredTransport = StructuredOutputTransport.unknown,
    this.strictSchemaObserved = false,
    this.reasoningControl = 'unknown',
    this.providerId = '',
    this.protocol = '',
    this.adapterVersion = 0,
    this.configurationFingerprint = '',
    this.verifiedStructuredTransports = const {},
  });

  final String structuredVerdict;
  final String textVerdict;
  final StructuredOutputTransport structuredTransport;
  final bool strictSchemaObserved;
  final String reasoningControl;
  final String providerId;
  final String protocol;
  final int adapterVersion;
  final String configurationFingerprint;
  final Set<StructuredOutputTransport> verifiedStructuredTransports;

  bool get hasReliableTextOutput => textVerdict == 'supported';

  bool get hasReliableStructuredOutput =>
      structuredVerdict == 'supported' &&
      structuredTransport != StructuredOutputTransport.unknown &&
      structuredTransport != StructuredOutputTransport.promptJson;

  static ModelCapabilityProfile fromRows(
    List<Map<String, Object?>> rows, {
    required String providerId,
    required String protocol,
    required int adapterVersion,
    required String configurationFingerprint,
  }) {
    final structured = rows.where(
      (row) => row['capability'] == 'structured_output',
    );
    final textRows = rows.where((row) => row['capability'] == 'text_chat');
    final textVerdict = textRows.isEmpty
        ? 'unconfirmed'
        : textRows.first['verdict'] as String? ?? 'unconfirmed';
    if (structured.isEmpty) {
      return ModelCapabilityProfile(
        textVerdict: textVerdict,
        providerId: providerId,
        protocol: protocol,
        adapterVersion: adapterVersion,
        configurationFingerprint: configurationFingerprint,
      );
    }
    final row = structured.first;
    final detail = row['detail'] as String? ?? '';
    Map<String, Object?> diagnosis = const {};
    try {
      final decoded = jsonDecode(row['diagnosis_json'] as String? ?? '{}');
      if (decoded is Map) {
        diagnosis = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      // Malformed historical evidence remains unconfirmed.
    }
    final observedProtocol = diagnosis['protocol'] as String? ?? protocol;
    final observedProvider = diagnosis['provider_id'] as String? ?? providerId;
    final observedVersion =
        diagnosis['adapter_version'] as int? ?? adapterVersion;
    final transport = _transportFrom(
      diagnosis['structured_transport'] as String?,
      detail: detail,
      protocol: observedProtocol,
    );
    final transports = <StructuredOutputTransport>{};
    final recordedTransports = diagnosis['structured_transports'];
    if (recordedTransports is List) {
      for (final raw in recordedTransports) {
        final parsed = _transportFrom(
          raw?.toString(),
          detail: '',
          protocol: observedProtocol,
        );
        if (parsed != StructuredOutputTransport.unknown) {
          transports.add(parsed);
        }
      }
    }
    if (transport != StructuredOutputTransport.unknown) {
      transports.add(transport);
    }
    return ModelCapabilityProfile(
      structuredVerdict: row['verdict'] as String? ?? 'unconfirmed',
      textVerdict: textVerdict,
      structuredTransport: transport,
      strictSchemaObserved:
          diagnosis['strict_schema_observed'] == true ||
          (transport == StructuredOutputTransport.jsonSchema &&
              !detail.contains('JSON Object')),
      reasoningControl: diagnosis['reasoning_control'] as String? ?? 'unknown',
      providerId: observedProvider,
      protocol: observedProtocol,
      adapterVersion: observedVersion,
      configurationFingerprint: configurationFingerprint,
      verifiedStructuredTransports: transports,
    );
  }

  static StructuredOutputTransport _transportFrom(
    String? raw, {
    required String detail,
    required String protocol,
  }) {
    switch (raw) {
      case 'json_schema':
        return StructuredOutputTransport.jsonSchema;
      case 'json_object':
        return StructuredOutputTransport.jsonObject;
      case 'forced_tool':
        return StructuredOutputTransport.forcedTool;
      case 'gemini_schema':
        return StructuredOutputTransport.geminiSchema;
      case 'prompt_json':
        return StructuredOutputTransport.promptJson;
    }
    if (detail.contains('JSON Object')) {
      return StructuredOutputTransport.jsonObject;
    }
    if (protocol == 'anthropic_messages') {
      return StructuredOutputTransport.forcedTool;
    }
    if (protocol == 'gemini') return StructuredOutputTransport.geminiSchema;
    if (detail.contains('严格 JSON Schema') || detail.contains('符合约束')) {
      return StructuredOutputTransport.jsonSchema;
    }
    return StructuredOutputTransport.unknown;
  }
}

StructuredOutputTransport selectStructuredOutputTransport({
  required ModelCapabilityProfile profile,
  required String protocol,
  required ModelOutputContract contract,
}) {
  final allowed = contract.allowedStructuredTransports;
  final verified = profile.verifiedStructuredTransports.isNotEmpty
      ? profile.verifiedStructuredTransports
      : {if (profile.hasReliableStructuredOutput) profile.structuredTransport};
  final nativePriority = switch (protocol) {
    'openai_chat' => const [
      StructuredOutputTransport.jsonSchema,
      StructuredOutputTransport.jsonObject,
      StructuredOutputTransport.forcedTool,
    ],
    'openai_responses' => const [StructuredOutputTransport.jsonSchema],
    'anthropic_messages' => const [StructuredOutputTransport.forcedTool],
    'gemini' => const [StructuredOutputTransport.geminiSchema],
    _ => const <StructuredOutputTransport>[],
  };
  for (final transport in nativePriority) {
    if (allowed.contains(transport) && verified.contains(transport)) {
      return transport;
    }
  }
  if (profile.hasReliableTextOutput &&
      allowed.contains(StructuredOutputTransport.promptJson)) {
    return StructuredOutputTransport.promptJson;
  }
  return StructuredOutputTransport.unknown;
}

List<Map<String, Object?>> messagesForStructuredTransport(
  List<Map<String, Object?>> messages, {
  required ModelOutputContract contract,
  required StructuredOutputTransport transport,
}) {
  if (transport != StructuredOutputTransport.promptJson) return messages;
  final instruction =
      '只输出一个完整 JSON 值，不要使用 Markdown 围栏或附加说明。'
      '结果必须满足以下 JSON Schema：${jsonEncode(contract.schema)}';
  return [
    ...messages,
    {'role': 'system', 'content': instruction},
  ];
}

void applyOutputContractPolicy(
  Map<String, Object?> payload, {
  required String protocol,
  required String providerId,
  required ModelOutputContract contract,
}) {
  if (contract.reasoningPolicy == ModelReasoningPolicy.providerDefault) return;
  switch (protocol) {
    case 'openai_chat':
      if (providerId == 'qwen' &&
          contract.reasoningPolicy == ModelReasoningPolicy.disabledPreferred) {
        payload['enable_thinking'] = false;
        payload.remove('reasoning_effort');
      } else if (providerId == 'deepseek') {
        payload['thinking'] = <String, Object?>{'type': 'disabled'};
        payload.remove('reasoning_effort');
      } else {
        payload['reasoning_effort'] = 'low';
      }
      break;
    case 'openai_responses':
      payload['reasoning'] = <String, Object?>{'effort': 'low'};
      break;
    case 'anthropic_messages':
      final outputConfig = Map<String, Object?>.from(
        payload['output_config'] as Map? ?? const {},
      );
      outputConfig['effort'] = 'low';
      payload['output_config'] = outputConfig;
      break;
    case 'gemini':
      // Gemini 思考参数随模型族变化；没有可靠能力证据时不注入未知字段。
      break;
  }
}

String extractStructuredJsonText(String source) {
  var text = source.trim();
  if (text.startsWith('```')) {
    final firstLine = text.indexOf('\n');
    final lastFence = text.lastIndexOf('```');
    if (firstLine >= 0 && lastFence > firstLine) {
      text = text.substring(firstLine + 1, lastFence).trim();
    }
  }
  if ((text.startsWith('{') && text.endsWith('}')) ||
      (text.startsWith('[') && text.endsWith(']'))) {
    return text;
  }
  final objectStart = text.indexOf('{');
  final objectEnd = text.lastIndexOf('}');
  final arrayStart = text.indexOf('[');
  final arrayEnd = text.lastIndexOf(']');
  if (arrayStart >= 0 &&
      arrayEnd >= arrayStart &&
      (objectStart < 0 || arrayStart < objectStart)) {
    return text.substring(arrayStart, arrayEnd + 1);
  }
  if (objectStart >= 0 && objectEnd >= objectStart) {
    return text.substring(objectStart, objectEnd + 1);
  }
  return text;
}

bool validateJsonSchemaValue(Object? value, Map<String, Object?> schema) {
  final anyOf = schema['anyOf'];
  if (anyOf is List) {
    return anyOf.whereType<Map>().any(
      (candidate) =>
          validateJsonSchemaValue(value, Map<String, Object?>.from(candidate)),
    );
  }
  final enumValues = schema['enum'];
  if (enumValues is List && !enumValues.contains(value)) return false;
  switch (schema['type']) {
    case 'object':
      if (value is! Map) return false;
      final properties = schema['properties'];
      final propertyMap = properties is Map
          ? properties.map((key, value) => MapEntry(key.toString(), value))
          : const <String, Object?>{};
      final required = (schema['required'] as List? ?? const []).map(
        (item) => item.toString(),
      );
      if (required.any((key) => !value.containsKey(key))) return false;
      if (schema['additionalProperties'] == false &&
          value.keys.any((key) => !propertyMap.containsKey(key.toString()))) {
        return false;
      }
      for (final entry in propertyMap.entries) {
        if (!value.containsKey(entry.key)) continue;
        if (entry.value is Map &&
            !validateJsonSchemaValue(
              value[entry.key],
              Map<String, Object?>.from(entry.value as Map),
            )) {
          return false;
        }
      }
      return true;
    case 'array':
      if (value is! List) return false;
      final items = schema['items'];
      return items is! Map ||
          value.every(
            (item) =>
                validateJsonSchemaValue(item, Map<String, Object?>.from(items)),
          );
    case 'string':
      return value is String;
    case 'integer':
      return value is int;
    case 'number':
      return value is num;
    case 'boolean':
      return value is bool;
    case 'null':
      return value == null;
    default:
      return true;
  }
}
