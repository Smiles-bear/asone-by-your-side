import 'package:shared_preferences/shared_preferences.dart';

class AssistantConversationPreferences {
  final bool showTimestamps;
  final String replyStyle;
  final bool voiceEnabled;

  const AssistantConversationPreferences({
    this.showTimestamps = true,
    this.replyStyle = 'segmented',
    this.voiceEnabled = true,
  });
}

class AssistantPreferencesService {
  static String _key(String assistantId, String name) =>
      'assistant.$assistantId.conversation.$name';

  static Future<AssistantConversationPreferences> load(
    String assistantId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    return AssistantConversationPreferences(
      showTimestamps:
          preferences.getBool(_key(assistantId, 'timestamps')) ?? true,
      replyStyle:
          preferences.getString(_key(assistantId, 'reply_style')) ??
          'segmented',
      voiceEnabled:
          preferences.getBool(_key(assistantId, 'voice_enabled')) ?? true,
    );
  }

  static Future<void> save(
    String assistantId,
    AssistantConversationPreferences value,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setBool(
        _key(assistantId, 'timestamps'),
        value.showTimestamps,
      ),
      preferences.setString(_key(assistantId, 'reply_style'), value.replyStyle),
      preferences.setBool(
        _key(assistantId, 'voice_enabled'),
        value.voiceEnabled,
      ),
    ]);
  }

  /// 删除助手时移除它在 SharedPreferences 中的全部私有配置。
  ///
  /// 使用 `assistant.<id>.` 前缀而不是逐个枚举当前字段，避免未来新增
  /// 助手级设置后遗漏清理；删除“对话”不会调用这里，因此助手设置会保留。
  static Future<void> clear(String assistantId) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = 'assistant.$assistantId.';
    final keys = preferences
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    await Future.wait(keys.map(preferences.remove));
  }
}
