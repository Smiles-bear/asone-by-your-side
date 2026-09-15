library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core_database.dart';
import '../import/content_hash.dart';

class GroupUpstreamRevisionHasher {
  GroupUpstreamRevisionHasher({CoreDatabase? coreDatabase})
    : _coreDatabase = coreDatabase ?? CoreDatabase.instance;

  final CoreDatabase _coreDatabase;

  Future<String> calculate({
    required String roomId,
    required String rootMessageId,
    required String logicalMessageId,
  }) async {
    final database = await _coreDatabase.open();
    return calculateWithExecutor(
      database,
      roomId: roomId,
      rootMessageId: rootMessageId,
      logicalMessageId: logicalMessageId,
    );
  }

  Future<String> calculateWithExecutor(
    DatabaseExecutor database, {
    required String roomId,
    required String rootMessageId,
    required String logicalMessageId,
    String? overrideMessageId,
    String? overrideAnswerVersionId,
    String? overrideContentHash,
  }) async {
    final roots = await database.query(
      'group_messages',
      columns: ['current_message_version_id', 'content_hash'],
      where: 'message_id = ? AND room_id = ? AND is_deleted = 0',
      whereArgs: [rootMessageId, roomId],
      limit: 1,
    );
    if (roots.isEmpty) throw StateError('群分支根消息不存在');
    final targets = await database.query(
      'group_messages',
      columns: ['sequence'],
      where: 'message_id = ? AND room_id = ? AND is_deleted = 0',
      whereArgs: [logicalMessageId, roomId],
      limit: 1,
    );
    if (targets.isEmpty) throw StateError('群逻辑回复不存在');
    final preceding = await database.query(
      'group_messages',
      columns: ['message_id', 'current_answer_version_id', 'content_hash'],
      where:
          "room_id = ? AND root_trigger_message_id = ? AND speaker_type = 'assistant' AND sequence < ? AND is_deleted = 0 AND upstream_status = 'current' AND answer_status = 'completed'",
      whereArgs: [roomId, rootMessageId, targets.single['sequence']],
      orderBy: 'sequence ASC',
    );
    final payload = <String, Object?>{
      'room_id': roomId,
      'root_message_id': rootMessageId,
      'root_version_id': roots.single['current_message_version_id'],
      'root_content_hash': roots.single['content_hash'],
      'preceding': [
        for (final row in preceding)
          {
            'message_id': row['message_id'],
            'answer_version_id': row['message_id'] == overrideMessageId
                ? overrideAnswerVersionId
                : row['current_answer_version_id'],
            'content_hash': row['message_id'] == overrideMessageId
                ? overrideContentHash
                : row['content_hash'],
          },
      ],
    };
    return sha256Text(jsonEncode(payload));
  }
}
