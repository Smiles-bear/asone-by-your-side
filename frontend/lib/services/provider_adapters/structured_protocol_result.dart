part of 'protocol_client.dart';

/// 协议调用结果（含文本与安全诊断）。
class ProtocolCallResult {
  ProtocolCallResult({
    required this.success,
    required this.text,
    required this.diagnosis,
    this.reasoning = '',
    this.toolCalls = const [],
    this.structuredData,
    this.structuredValue,
    this.usage = const {},
    this.model = '',
    this.requestId,
    this.failureKind = ModelTaskFailureKind.none,
    this.normalizationNotes = const [],
    this.validationIssues = const [],
  });

  final bool success;
  final String text;
  final String reasoning;
  final ProtocolDiagnosis diagnosis;
  final List<ProviderToolCall> toolCalls;
  final Map<String, Object?>? structuredData;
  final Object? structuredValue;
  final Map<String, Object?> usage;
  final String model;
  final String? requestId;
  final ModelTaskFailureKind failureKind;
  final List<String> normalizationNotes;
  final List<String> validationIssues;
}

ProtocolCallResult validateStructuredProtocolResult({
  required ProtocolCallResult raw,
  required ModelOutputContract contract,
  required StructuredOutputTransport transport,
  required ProtocolDiagnosis diagnosis,
}) {
  Object? toolValue;
  if (transport == StructuredOutputTransport.forcedTool) {
    final matching = raw.toolCalls.where(
      (call) => call.name == contract.schemaName,
    );
    if (matching.isNotEmpty) toolValue = matching.first.arguments;
  }
  final schema = contract.schema;
  final reception = schema == null
      ? StructuredOutputReception(
          success: false,
          rawText: raw.text,
          extractedText: '',
          failureKind: ModelTaskFailureKind.domainValidation,
          validationIssues: const ['任务缺少 JSON Schema'],
        )
      : receiveStructuredOutput(
          rawText: raw.text,
          schema: schema,
          toolValue: toolValue,
        );
  if (!reception.success) {
    final failureDiagnosis = diagnosis.copyWith(
      errorCode: 'INVALID_STRUCTURED_OUTPUT',
      detail: reception.validationIssues.join('；'),
      stage: 'validate',
      failureCategory: reception.failureKind.name,
    );
    return ProtocolCallResult(
      success: false,
      text: raw.text,
      reasoning: raw.reasoning,
      toolCalls: raw.toolCalls,
      usage: raw.usage,
      model: raw.model,
      diagnosis: failureDiagnosis,
      requestId: raw.requestId,
      structuredData: reception.value is Map<String, Object?>
          ? reception.value as Map<String, Object?>
          : null,
      structuredValue: reception.value,
      failureKind: reception.failureKind,
      normalizationNotes: reception.normalizationNotes,
      validationIssues: reception.validationIssues,
    );
  }
  final structured = reception.value;
  final successDiagnosis = diagnosis.copyWith(
    stage: 'validated',
    failureCategory: ModelTaskFailureKind.none.name,
  );
  return ProtocolCallResult(
    success: true,
    text: raw.text.trim(),
    reasoning: raw.reasoning,
    toolCalls: raw.toolCalls,
    structuredData: structured is Map<String, Object?> ? structured : null,
    structuredValue: structured,
    usage: raw.usage,
    model: raw.model,
    diagnosis: successDiagnosis,
    requestId: raw.requestId,
    normalizationNotes: reception.normalizationNotes,
  );
}

bool canFallbackToPromptJson(
  ProtocolCallResult result, {
  required StructuredOutputTransport transport,
  required ModelCapabilityProfile profile,
  required ModelOutputContract contract,
}) {
  if (result.success || transport == StructuredOutputTransport.promptJson) {
    return false;
  }
  if (!profile.hasReliableTextOutput ||
      !contract.allowedStructuredTransports.contains(
        StructuredOutputTransport.promptJson,
      )) {
    return false;
  }
  if (result.diagnosis.statusCode != 400 &&
      result.diagnosis.statusCode != 422) {
    return false;
  }
  final detail = result.diagnosis.detail.toLowerCase();
  return const [
    'response_format',
    'json_schema',
    'tool_choice',
    'responseschema',
    'output format',
  ].any(detail.contains);
}
