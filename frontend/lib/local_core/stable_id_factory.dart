import 'dart:math';

/// 稳定 ID 工厂：按领域生成带前缀的安全随机 ID
///
/// 目标格式：
/// - `assistant_<uuid4hex>` (长度 42)
/// - `conversation_<uuid4hex>` (长度 45)
/// - `message_<uuid4hex>` (长度 40)
/// - `message_version_<uuid4hex>` (长度 48)
/// - `answer_version_<uuid4hex>` (长度 47)
/// - `model_service_<uuid4hex>` (长度 46)
///
/// 使用安全随机 128 bit UUID v4（32 位十六进制字符）
class StableIdFactory {
  static final _random = Random.secure();

  /// 生成 UUID v4 的 32 位十六进制字符串
  static String _uuid4hex() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // UUID v4: 设置版本位和变体位
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // 版本 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // 变体 RFC4122

    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// 生成助手 ID: `assistant_<uuid4hex>`
  static String assistantId() => 'assistant_${_uuid4hex()}';

  /// 生成对话 ID: `conversation_<uuid4hex>`
  static String conversationId() => 'conversation_${_uuid4hex()}';

  /// 生成消息 ID: `message_<uuid4hex>`
  static String messageId() => 'message_${_uuid4hex()}';

  /// 生成消息版本 ID: `message_version_<uuid4hex>`
  static String messageVersionId() => 'message_version_${_uuid4hex()}';

  /// 生成回答版本 ID: `answer_version_<uuid4hex>`
  static String answerVersionId() => 'answer_version_${_uuid4hex()}';

  /// 生成模型服务 ID: `model_service_<uuid4hex>`
  static String modelServiceId() => 'model_service_${_uuid4hex()}';

  /// 生成记忆 ID: `memory_<uuid4hex>`
  static String memoryId() => 'memory_${_uuid4hex()}';

  /// 生成日记 ID: `diary_<uuid4hex>`
  static String diaryId() => 'diary_${_uuid4hex()}';

  /// 生成任务 ID: `task_<uuid4hex>`
  static String taskId() => 'task_${_uuid4hex()}';

  /// 生成快照 ID: `snapshot_<uuid4hex>`
  static String snapshotId() => 'snapshot_${_uuid4hex()}';

  /// 通用生成方法：根据前缀生成 ID
  static String generate(String prefix) => '${prefix}_${_uuid4hex()}';

  /// 验证 ID 格式是否符合规范
  static bool isValidFormat(String id, String expectedPrefix) {
    if (!id.startsWith('${expectedPrefix}_')) return false;
    final suffix = id.substring(expectedPrefix.length + 1);
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(suffix);
  }

  /// 提取 ID 的领域前缀
  static String? extractPrefix(String id) {
    final underscoreIndex = id.indexOf('_');
    if (underscoreIndex == -1) return null;
    return id.substring(0, underscoreIndex);
  }
}
