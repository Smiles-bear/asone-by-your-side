part of 'message_version_service.dart';

extension MessageVersionEdit on MessageVersionService {
  Future<MessageVersion> editMessage({
    required String messageId,
    required String newContent,
    String? editedBy,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();
    final contentHash = _computeHash(newContent);
    final rows = await db.query(
      'messages',
      columns: ['revision', 'role', 'current_answer_version_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('消息不存在：$messageId');
    final revision = (rows.single['revision'] as int) + 1;
    final role = rows.single['role'] as String;
    final answerId = rows.single['current_answer_version_id'] as String?;
    final versionId = StableIdFactory.messageVersionId();
    await db.transaction((txn) async {
      await txn.insert('message_versions', {
        'version_id': versionId,
        'message_id': messageId,
        'version_number': revision,
        'content': newContent,
        'content_hash': contentHash,
        'edited_by': editedBy,
        'created_at': now,
      });
      await txn.update(
        'messages',
        {
          'content': newContent,
          'content_hash': contentHash,
          'revision': revision,
          'current_message_version_id': versionId,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
      if (role == 'assistant') {
        await txn.delete(
          'message_segments',
          where: 'message_id = ?',
          whereArgs: [messageId],
        );
        await txn.insert('message_segments', {
          'message_id': messageId,
          'segment_index': 0,
          'content': newContent,
        });
      }
      if (role == 'assistant' && answerId != null) {
        await txn.update(
          'answer_versions',
          {
            'content': newContent,
            'content_hash': contentHash,
            'tts_script': null,
            'tts_script_status': 'none',
            'tts_script_source_hash': null,
          },
          where: 'answer_version_id = ? AND message_id = ?',
          whereArgs: [answerId, messageId],
        );
        await txn.delete(
          'chat_answer_version_segments',
          where: 'answer_version_id = ?',
          whereArgs: [answerId],
        );
        await txn.insert('chat_answer_version_segments', {
          'answer_version_id': answerId,
          'segment_index': 0,
          'content': newContent,
        });
      }
      final predicate = answerId == null
          ? 'answer_version_id IS NULL'
          : 'answer_version_id = ?';
      final args = [messageId, if (answerId != null) answerId];
      await txn.update(
        'message_voice_assets',
        {'state': 'invalidated', 'updated_at': now},
        where:
            "message_id = ? AND $predicate AND state IN ('generating', 'ready')",
        whereArgs: args,
      );
      await txn.rawUpdate(
        '''UPDATE message_director_scripts
           SET script = NULL, status = 'none', revision = revision + 1,
               source_text_hash = '', updated_at = ?
           WHERE message_id = ? AND $predicate''',
        [now, messageId, if (answerId != null) answerId],
      );
    });
    await _lifecycleHooks?.markMessageChanged(messageId);
    return MessageVersion(
      versionId: versionId,
      messageId: messageId,
      versionNumber: revision,
      content: newContent,
      contentHash: contentHash,
      editedBy: editedBy,
      createdAt: now,
    );
  }
}
