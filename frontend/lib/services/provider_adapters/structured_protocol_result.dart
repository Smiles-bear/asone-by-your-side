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
  var ambiguousTool = false;
  if (transport == StructuredOutputTransport.forcedTool) {
    final matching = raw.toolCalls.where(
      (call) => call.name == contract.schemaName,
    );
    if (matching.length == 1 && raw.toolCalls.length == 1) {
      toolValue = matching.single.arguments;
    } else {
      ambiguousTool = raw.toolCalls.isNotEmpty;
    }
  }
  final schema = contract.schema;
  final reception = ambiguousTool
      ? StructuredOutputReception(
          success: false,
          rawText: raw.text,
          extractedText: '',
          failureKind: ModelTaskFailureKind.domainValidation,
          validationIssues: const ['模型未返回唯一的目标工具结果'],
        )
      : schema == null
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
  final status = result.diagnosis.statusCode;
  final detail = result.diagnosis.detail.toLowerCase();
  final wrapped400 =
      status == 503 && RegExp(r'upstream status\s+400\b').hasMatch(detail);
  if (!const {400, 404, 405, 415, 422, 501}.contains(status) &&
      !wrapped400) {
    return false;
  }
  final mentionsStructuredParameter = const [
    'response_format',
    'json_schema',
    'json schema',
    'tool_choice',
    'responseschema',
    'output format',
  ].any(detail.contains);
  final explicitlyRejected = const [
    'unsupported',
    'not support',
    'unknown',
    'unrecognized',
    'invalid',
    'not allowed',
    '不支持',
    '参数无效',
    '需要 build 通道',
  ].any(detail.contains);
  return mentionsStructuredParameter && explicitlyRejected;
}
