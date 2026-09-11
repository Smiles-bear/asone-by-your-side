class TransientUpstreamFailure implements Exception {
  const TransientUpstreamFailure({
    this.statusCode,
    this.reason = '',
    this.hasVisibleText = false,
    this.hasVisibleReasoning = false,
    this.hasToolCalls = false,
  });

  final int? statusCode;
  final String reason;
  final bool hasVisibleText;
  final bool hasVisibleReasoning;
  final bool hasToolCalls;

  @override
  String toString() => '模型服务暂时不可用，请稍后重试';
}

class UpstreamFailurePolicy {
  const UpstreamFailurePolicy._();

  static bool isTransient({
    int? statusCode,
    String code = '',
    String reason = '',
  }) {
    if (const <int>{502, 503, 504}.contains(statusCode)) return true;
    final value = '$code $reason'.trim().toLowerCase();
    return const <String>[
      'service_unavailable',
      'server_error',
      'upstream_error',
    ].any(value.contains);
  }

  static bool canRetry(Object error, {required bool cancelled}) {
    if (cancelled || error is! TransientUpstreamFailure) return false;
    return isTransient(statusCode: error.statusCode, reason: error.reason) &&
        !error.hasVisibleText &&
        !error.hasVisibleReasoning &&
        !error.hasToolCalls;
  }

  static String diagnosticCode({
    int? statusCode,
    String code = '',
    String reason = '',
    required String fallback,
  }) => isTransient(statusCode: statusCode, code: code, reason: reason)
      ? 'TRANSIENT_UPSTREAM'
      : fallback;

  static void throwIfTransientHttp(int? statusCode) {
    if (isTransient(statusCode: statusCode)) {
      throw TransientUpstreamFailure(
        statusCode: statusCode,
        reason: 'HTTP $statusCode',
      );
    }
  }

  static void throwIfTransientStream({
    required String reason,
    required bool hasVisibleText,
    required bool hasVisibleReasoning,
    required bool hasToolCalls,
  }) {
    if (!isTransient(reason: reason)) return;
    throw TransientUpstreamFailure(
      reason: reason,
      hasVisibleText: hasVisibleText,
      hasVisibleReasoning: hasVisibleReasoning,
      hasToolCalls: hasToolCalls,
    );
  }
}
