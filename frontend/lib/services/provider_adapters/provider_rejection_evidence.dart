/// Fixed technical facts survive privacy filtering without copying input data.
String? providerTechnicalFact(int status, String? message) {
  final lower = (message ?? '').toLowerCase();
  if (const {
        200,
        400,
        404,
        405,
        415,
        422,
        500,
        501,
        502,
        503,
        504,
      }.contains(status) &&
      RegExp(
        r'(?:^|[:;]\s*)protocol[\s_-]+mismatch(?:\s*:|\s*$)|^接口协议不匹配',
      ).hasMatch(lower.trim())) {
    return '接口协议不匹配';
  }
  if ((status == 400 || status == 401 || status == 403) &&
      (lower.contains('x-api-key') || lower.contains('x-goog-api-key')) &&
      (lower.contains('missing') || lower.contains('required'))) {
    return '当前接口要求专用认证头';
  }
  if (status != 400 && status != 422) return null;
  if (lower.contains('input_audio') && lower.contains('unknown variant')) {
    return '当前接口不支持音频输入';
  }
  if (lower.contains('reasoning_content') && lower.contains('passed back')) {
    return '工具模式要求关闭思考';
  }
  return null;
}

bool providerHasNoChannel(int status, String? message) =>
    (status == 400 || status == 503) &&
    RegExp(
      r'no available channel|no channels? available|无可用渠道|暂无可用渠道',
      caseSensitive: false,
    ).hasMatch(message ?? '');
