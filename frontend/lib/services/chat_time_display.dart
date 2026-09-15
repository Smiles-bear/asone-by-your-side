/// 聊天时间分隔线的统一显示规则。
///
/// 对话页面与需要复用对话时间线文本的模型上下文必须共同调用这里，
/// 避免两处规则或格式发生偏差。
abstract final class ChatTimeDisplay {
  static DateTime? resolveMessageTime(Map<String, Object?> message) {
    final status = message['timestamp_status'];
    if (status == 'missing' || status == 'unknown') return null;

    final rawTime = message['source_created_at'] ?? message['created_at'];
    if (rawTime is! String) return null;
    return DateTime.tryParse(rawTime);
  }

  static bool shouldShowSeparator(DateTime? previous, DateTime? current) {
    if (current == null) return false;
    if (previous == null) return true;
    return current.difference(previous).inSeconds >= 600;
  }

  static String formatSeparator(DateTime time, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final messageDay = DateTime(time.year, time.month, time.day);
    final age = today.difference(messageDay).inDays;
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    if (age == 0) return timeText;
    if (age == 1) return '昨天 $timeText';
    if (age >= 2 && age <= 6) {
      const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
      return '${weekdays[time.weekday - 1]} $timeText';
    }
    if (time.year == reference.year) {
      return '${time.month}月${time.day}日 $timeText';
    }
    return '${time.year}年${time.month}月${time.day}日 $timeText';
  }
}
