/// Shared projection rules for persisted chat messages entering model context.
abstract final class ContextMessagePolicy {
  static const _incompleteMarker = '【未完成的助手回复】';
  static const _stateOnlyContents = {'回复失败', '回复已中断'};

  static bool isEligible(Map<String, Object?> message) {
    if (message['role'] != 'assistant') return true;
    final status = message['answer_status']?.toString().toLowerCase();
    if (status != 'failed' && status != 'cancelled') return true;
    final content = message['content']?.toString().trim() ?? '';
    return content.isNotEmpty && !_stateOnlyContents.contains(content);
  }

  static Map<String, Object?> project(Map<String, Object?> message) {
    if (message['role'] != 'assistant') return message;
    final status = message['answer_status']?.toString().toLowerCase();
    if (status != 'failed' && status != 'cancelled') return message;
    final content = message['content']?.toString().trim() ?? '';
    if (content.startsWith(_incompleteMarker)) return message;
    return {...message, 'content': '$_incompleteMarker\n$content'};
  }
}
