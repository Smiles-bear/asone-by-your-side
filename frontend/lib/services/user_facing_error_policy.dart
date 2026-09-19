import '../models/message.dart';

class UserFacingErrorPolicy {
  const UserFacingErrorPolicy._();

  static const assistantReplyFailed = '回复失败';
  static const defaultFailureHint = '请检查网络设置后重试。';
  static const streamingInterrupted = '回复传输中断，可重新生成。';

  static String failureHintFor(
    Object? error, {
    bool hasPartialContent = false,
  }) {
    if (hasPartialContent) return streamingInterrupted;
    final text = error?.toString().toLowerCase() ?? '';
    if (text.contains('vision_route_unavailable')) {
      return '请在模型设置中配置可用的图片理解模型后重试。';
    }
    if (text.contains('pdf')) {
      return text.contains('没有可读取的文字')
          ? '这个 PDF 没有可读取的文字，请换用文字版 PDF。'
          : 'PDF 读取失败，请检查文件后重试。';
    }
    if (_containsAny(text, const [
      '401',
      '403',
      'api key',
      'unauthorized',
      'authentication',
    ])) {
      return '请检查API配置后重试。';
    }
    if (_containsAny(text, const ['http 400', 'status code of 400'])) {
      return '请求参数不受该模型支持，请检查模型配置后重试。';
    }
    if (_containsAny(text, const ['429', 'rate limit', 'quota'])) {
      return '请检查服务额度后重试。';
    }
    if (text.contains('model') &&
        (text.contains('not found') || text.contains('unsupported'))) {
      return '请检查模型设置后重试。';
    }
    if (_containsAny(text, const ['upstream', '502', '503', '504'])) {
      return '请检查上游服务后重试。';
    }
    if (_containsAny(text, const ['content policy', 'safety'])) {
      return '请检查消息内容后重试。';
    }
    if (_containsAny(text, const [
      'database is locked',
      'database is busy',
      'sqlite_busy',
      'sqlite_locked',
    ])) {
      return '本地数据正在处理中，请稍后重试。';
    }
    if (_containsAny(text, const [
      'socketexception',
      'connection timeout',
      'receive timeout',
      'network error',
      'failed host lookup',
    ])) {
      return '网络连接异常，请稍后重试。';
    }
    if (_containsAny(text, const [
      'formatexception',
      'protocol error',
      'invalid response',
      'empty response',
    ])) {
      return '模型返回异常，请检查模型配置后重试。';
    }
    if (_containsAny(text, const ['tool', '工具'])) {
      return '请检查工具配置后重试。';
    }
    return defaultFailureHint;
  }

  static bool _containsAny(String text, List<String> candidates) =>
      candidates.any(text.contains);

  static Message normalizeAssistantReply(Message message) {
    if (message.role != 'assistant' ||
        message.answerStatus != 'failed' ||
        message.content.trim().isNotEmpty) {
      return message;
    }
    return message.copyWith(
      content: assistantReplyFailed,
      failureHint: message.failureHint ?? defaultFailureHint,
      streaming: false,
      segments: const [],
    );
  }

  static bool isAssistantReplyFailureBubble(Message message) =>
      message.role == 'assistant' && message.answerStatus == 'failed';
}
