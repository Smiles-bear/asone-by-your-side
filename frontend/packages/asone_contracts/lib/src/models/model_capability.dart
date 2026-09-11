// 模型能力判定、单项探测结果与安全诊断元数据（公开契约）。

enum ModelCapabilityVerdict { supported, unsupported, unconfirmed }

class ModelCapabilityProbeResult {
  const ModelCapabilityProbeResult({
    required this.capability,
    required this.verdict,
    required this.elapsedMs,
    required this.detail,
    this.protocol = '',
    this.diagnosis,
    this.requestWasSent,
    this.evidenceSource = 'real_probe',
  });

  final String capability;
  final ModelCapabilityVerdict verdict;
  final int elapsedMs;
  final String detail;
  final String protocol;
  final ProtocolDiagnosis? diagnosis;
  final bool? requestWasSent;
  final String evidenceSource;

  bool get isSupported => verdict == ModelCapabilityVerdict.supported;
  bool get requestSent =>
      requestWasSent ?? diagnosis?.requestSent ?? elapsedMs > 0;

  String get nextAction {
    if (isSupported) return '';
    const configurationErrors = {
      'AUTH_FAILED',
      'ENDPOINT_NOT_FOUND',
      'MODEL_NOT_FOUND',
      'MODEL_ACCESS_DENIED',
      'INVALID_CONFIG',
      'INVALID_REQUEST',
      'PROTOCOL_MISMATCH',
    };
    return configurationErrors.contains(diagnosis?.errorCode)
        ? 'check_configuration'
        : 'retry';
  }

  Map<String, dynamic> toJson() => {
    'success': isSupported,
    'capability': capability,
    'verdict': verdict.name,
    'elapsed_ms': elapsedMs,
    'request_sent': requestSent,
    'evidence_source': evidenceSource,
    if (!isSupported) 'error': detail,
    'detail': detail,
    if (!isSupported) 'next_action': nextAction,
    if (protocol.isNotEmpty) 'protocol': protocol,
    if (diagnosis != null) 'diagnosis': diagnosis!.toJson(),
  };
}

/// 单项检测的安全诊断元数据（不含 Key 与原始响应）。
class ProtocolDiagnosis {
  ProtocolDiagnosis({
    required this.protocol,
    required this.endpoint,
    required this.requestSent,
    this.statusCode,
    this.contentType,
    required this.elapsedMs,
    this.topLevelKeys = const [],
    this.sseEventTypes = const [],
    this.errorCode = '',
    this.detail = '',
    this.finishReason = '',
    this.outputContract = '',
    this.structuredTransport = '',
    this.reasoningPolicy = '',
    this.textLength = 0,
    this.reasoningLength = 0,
    this.providerId = '',
    this.adapterVersion = 0,
    this.strictSchemaObserved = false,
    this.stage = '',
    this.attemptCount = 0,
    this.failureCategory = '',
  });

  /// 实际使用的协议名。
  final String protocol;

  /// 脱敏端点（无 query、无 Key）。
  final String endpoint;

  /// 是否真正发出了请求。
  final bool requestSent;

  final int? statusCode;
  final String? contentType;

  /// 真实耗时（毫秒）。未发出请求时为 0，由上层决定是否标记。
  final int elapsedMs;

  /// 响应顶层字段名集合。
  final List<String> topLevelKeys;

  /// SSE 中观察到的 event type 集合。
  final List<String> sseEventTypes;

  /// 归一化错误码。
  final String errorCode;

  /// 面向用户的中文原因。
  final String detail;
  final String finishReason;
  final String outputContract;
  final String structuredTransport;
  final String reasoningPolicy;
  final int textLength;
  final int reasoningLength;
  final String providerId;
  final int adapterVersion;
  final bool strictSchemaObserved;
  final String stage;
  final int attemptCount;
  final String failureCategory;

  ProtocolDiagnosis copyWith({
    int? elapsedMs,
    String? detail,
    String? errorCode,
    String? finishReason,
    String? outputContract,
    String? structuredTransport,
    String? reasoningPolicy,
    int? textLength,
    int? reasoningLength,
    String? providerId,
    int? adapterVersion,
    bool? strictSchemaObserved,
    String? stage,
    int? attemptCount,
    String? failureCategory,
  }) => ProtocolDiagnosis(
    protocol: protocol,
    endpoint: endpoint,
    requestSent: requestSent,
    statusCode: statusCode,
    contentType: contentType,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    topLevelKeys: topLevelKeys,
    sseEventTypes: sseEventTypes,
    errorCode: errorCode ?? this.errorCode,
    detail: detail ?? this.detail,
    finishReason: finishReason ?? this.finishReason,
    outputContract: outputContract ?? this.outputContract,
    structuredTransport: structuredTransport ?? this.structuredTransport,
    reasoningPolicy: reasoningPolicy ?? this.reasoningPolicy,
    textLength: textLength ?? this.textLength,
    reasoningLength: reasoningLength ?? this.reasoningLength,
    providerId: providerId ?? this.providerId,
    adapterVersion: adapterVersion ?? this.adapterVersion,
    strictSchemaObserved: strictSchemaObserved ?? this.strictSchemaObserved,
    stage: stage ?? this.stage,
    attemptCount: attemptCount ?? this.attemptCount,
    failureCategory: failureCategory ?? this.failureCategory,
  );

  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'endpoint': endpoint,
    'request_sent': requestSent,
    if (statusCode != null) 'status_code': statusCode,
    if (contentType != null) 'content_type': contentType,
    'elapsed_ms': elapsedMs,
    'top_level_keys': topLevelKeys,
    'sse_event_types': sseEventTypes,
    if (errorCode.isNotEmpty) 'error_code': errorCode,
    if (detail.isNotEmpty) 'detail': detail,
    if (finishReason.isNotEmpty) 'finish_reason': finishReason,
    if (outputContract.isNotEmpty) 'output_contract': outputContract,
    if (structuredTransport.isNotEmpty)
      'structured_transport': structuredTransport,
    if (reasoningPolicy.isNotEmpty) 'reasoning_policy': reasoningPolicy,
    'text_length': textLength,
    'reasoning_length': reasoningLength,
    if (providerId.isNotEmpty) 'provider_id': providerId,
    if (adapterVersion > 0) 'adapter_version': adapterVersion,
    'strict_schema_observed': strictSchemaObserved,
    if (stage.isNotEmpty) 'stage': stage,
    if (attemptCount > 0) 'attempt_count': attemptCount,
    if (failureCategory.isNotEmpty) 'failure_category': failureCategory,
  };
}
