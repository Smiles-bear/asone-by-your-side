part of 'core_repository.dart';

extension CoreRepositoryExperience on CoreRepository {
  String _id() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = List.generate(
      3,
      (_) => _random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0'),
    ).join();
    return '$micros$random';
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<void> setConversationChatBackground(
    String conversationId,
    String? path,
  ) => setConversationChatBackgroundMode(
    conversationId,
    mode: path?.trim().isNotEmpty == true ? 'custom' : 'inherit',
    path: path,
  );

  Future<void> setConversationChatBackgroundMode(
    String conversationId, {
    required String mode,
    String? path,
  }) async {
    if (!const {'inherit', 'default', 'custom'}.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', '不支持的聊天背景模式');
    }
    final normalizedPath = path?.trim() ?? '';
    if (mode == 'custom' && normalizedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', '自定义背景需要图片');
    }
    final database = await _coreDatabase.open();
    final count = await database.update(
      'conversations',
      {
        'chat_background_mode': mode,
        'chat_background_path': mode == 'custom' ? normalizedPath : '',
        'updated_at': _now(),
      },
      where: 'id = ? AND import_pending = 0',
      whereArgs: [conversationId],
    );
    if (count != 1) throw StateError('对话不存在');
  }

  Future<void> clearConversationChatBackgrounds() async {
    final database = await _coreDatabase.open();
    await database.update(
      'conversations',
      {
        'chat_background_mode': 'inherit',
        'chat_background_path': '',
        'updated_at': _now(),
      },
      where: "chat_background_mode <> 'inherit' OR chat_background_path <> ''",
    );
  }

  Future<Set<String>> conversationChatBackgroundPaths() async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'conversations',
      distinct: true,
      columns: const ['chat_background_path'],
      where: "chat_background_path <> ''",
    );
    return rows
        .map((row) => row['chat_background_path']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();
  }
}

Future<void> _recoverStaleProjectedVoiceAssets(
  Database database,
  String conversationId,
) => database
    .update(
      'message_voice_assets',
      {
        'state': 'failed',
        'last_error': '语音生成已中断，请重试',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: '''conversation_id = ? AND state = 'generating'
    AND updated_at < ?''',
      whereArgs: [
        conversationId,
        DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
      ],
    )
    .then((_) {});
