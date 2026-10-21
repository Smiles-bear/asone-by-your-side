class TransientUpstreamFailure implements Exception {
  const TransientUpstreamFailure({
    this.statusCode,
    this.reason = '',
    this.providerMessage = '',
    this.hasVisibleText = false,
    this.hasVisibleReasoning = false,
    this.hasToolCalls = false,
  });

  final int? statusCode;
  final String reason;
  final String providerMessage;
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
    final value = '$code $reason'.trim().toLowerCase();
    // Gate semantic rejections before HTTP status: gateways often encode
    // billing, moderation or missing model channels as HTTP 503/server_error.
    if (RegExp(
      r'account_billing|model_channel_unavailable|content_policy_violation|auth_failed|quota|rate.limit|billing|balance|payment|insufficient.credit|no.available.channel|no.channel|nochannel|无可用渠道|暂无可用渠道|额度|余额|审核',
    ).hasMatch(value)) {
      return false;
    }
    if (const <int>{502, 503, 504}.contains(statusCode)) return true;
    return const <String>[
      'service_unavailable',
      'server_error',
      'upstream_error',
    ].any(value.contains);
  }

  static bool canRetry(Object error, {required bool cancelled}) {
    if (cancelled || error is! TransientUpstreamFailure) return false;
    return isTransient(
          statusCode: error.statusCode,
          reason: '${error.reason} ${error.providerMessage}',
        ) &&
        !error.hasVisibleText &&
        !error.hasVisibleReasoning &&
        !error.hasToolCalls;
  }

  static String diagnosticCode({
    int? statusCode,
    String code = '',
    String reason = '',
    required String fallback,
  }) =>
      const {
        'MODEL_CHANNEL_UNAVAILABLE',
        'ACCOUNT_BILLING',
        'CONTENT_POLICY_VIOLATION',
        'PROTOCOL_MISMATCH',
      }.contains(code)
      ? code
      : isTransient(statusCode: statusCode, code: code, reason: reason)
      ? 'TRANSIENT_UPSTREAM'
      : fallback;

  static void throwIfTransientHttp(
    int? statusCode, {
    String code = '',
    String providerMessage = '',
  }) {
    if (isTransient(
      statusCode: statusCode,
      code: code,
      reason: providerMessage,
    )) {
      throw TransientUpstreamFailure(
        statusCode: statusCode,
        reason: 'HTTP $statusCode',
        providerMessage: providerMessage,
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
