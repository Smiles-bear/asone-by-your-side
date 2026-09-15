part of 'message_version_service.dart';

extension MessageVersionToolUsage on MessageVersionService {
  Future<void> markStreamingAnswerToolUsed({
    required String answerVersionId,
    required String messageId,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'answer_versions',
        {'tool_used': 1},
        where: 'answer_version_id = ? AND message_id = ?',
        whereArgs: [answerVersionId, messageId],
      );
      await txn.update(
        'messages',
        {'tool_used': 1, 'updated_at': now},
        where: 'id = ? AND current_answer_version_id = ?',
        whereArgs: [messageId, answerVersionId],
      );
    });
  }
}
