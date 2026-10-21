import 'provider_adapters/adapter_types.dart';

class ProviderModelFailure implements Exception {
  const ProviderModelFailure(this.diagnosis);
  final ProtocolDiagnosis diagnosis;
  @override
  String toString() => '模型请求失败（${diagnosis.errorCode}）';
}

/// A provider explanation is accepted only at the response boundary, never
/// reconstructed from exception text or a historical diagnostic detail.
String safeProviderMessage(
  String? value, {
  Iterable<String> secrets = const [],
  Object? requestPayload,
}) {
  if (value == null || value.trim().isEmpty) return '';
  var text = value.trim();
  if (RegExp(
    r'<[^>]+>|```|Traceback|Exception:|\b(stack trace|internal stack|stacktrace)\b|\bat\s+\S+\([^)]*:\d+|[\{\[]\s*"',
    caseSensitive: false,
  ).hasMatch(text)) {
    return '';
  }
  for (final secret in secrets) {
    if (secret.isNotEmpty) text = text.replaceAll(secret, '[已隐藏]');
  }
  text = text
      .replaceAll(RegExp(r'bearer\s+\S+', caseSensitive: false), '[已隐藏]')
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]+'), '[已隐藏]')
      .replaceAll(
        RegExp(r'https?://\S+\?\S+', caseSensitive: false),
        '[地址已隐藏]',
      );
  if (RegExp(
    r'(api[_ -]?key|authorization|token|password|cookie|prompt|input|请求正文|输入内容)\s*[:=]',
    caseSensitive: false,
  ).hasMatch(text)) {
    return '';
  }
  text = text.replaceAll(RegExp(r'[\x00-\x1f\x7f\s]+'), ' ').trim();
  final preview = text.length > 200 ? text.substring(0, 200) : text;
  bool echoes(Object? source) {
    if (source is Map) return source.values.any(echoes);
    if (source is List) return source.any(echoes);
    if (source is! String || source.length < 8) return false;
    for (var i = 0; i + 8 <= preview.length; i++) {
      if (source.contains(preview.substring(i, i + 8))) return true;
    }
    return false;
  }

  if (echoes(requestPayload)) return '';
  return text.length > 200 ? '$preview…' : preview;
}

enum ModelFailureKind { review, transient, configuration, other }

ModelFailureKind modelFailureKind(String code, [int? status]) {
  if (code == 'CONTENT_POLICY_VIOLATION') return ModelFailureKind.review;
  if (const {
        'AUTH_FAILED',
        'ACCOUNT_BILLING',
        'ENDPOINT_NOT_FOUND',
        'INVALID_REQUEST',
        'MODEL_NOT_FOUND',
        'MODEL_CHANNEL_UNAVAILABLE',
        'MODEL_BINDING_INVALID',
        'MODEL_BINDING_CHANGED',
        'PROTOCOL_UNCONFIRMED',
        'MODEL_CAPABILITY_STALE',
        'OUTPUT_CONTRACT_UNAVAILABLE',
      }.contains(code) ||
      const {401, 402, 403, 404, 422}.contains(status)) {
    return ModelFailureKind.configuration;
  }
  if (const {
        'TIMEOUT',
        'CONNECT_TIMEOUT',
        'SEND_TIMEOUT',
        'RECEIVE_TIMEOUT',
        'NETWORK_ERROR',
        'NETWORK_CONNECTION',
        'RATE_LIMITED',
        'SERVER_ERROR',
      }.contains(code) ||
      const {408, 429, 502, 503, 504}.contains(status)) {
    return ModelFailureKind.transient;
  }
  return ModelFailureKind.other;
}

String providerExplanation(String message) {
  final safe = safeProviderMessage(message);
  return safe.isEmpty ? '' : 'API 服务商返回：$safe';
}

String reviewBatchHint(int? count, {String providerMessage = ''}) {
  final text = count != null && count > 1
      ? '这批资料包含多条消息，本次请求未通过服务商审核。可调整相关内容后重试，或暂时跳过。'
      : '这批资料的请求未通过服务商审核。可调整相关内容后重试，或暂时跳过。';
  final explanation = providerExplanation(providerMessage);
  return explanation.isEmpty ? text : '$text\n$explanation';
}

String diagnosisFailureHint(ProtocolDiagnosis diagnosis, String fallback) {
  final explanation = providerExplanation(diagnosis.providerMessage);
  return explanation.isEmpty ? fallback : '$explanation\n$fallback';
}
