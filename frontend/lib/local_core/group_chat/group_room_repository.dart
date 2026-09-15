library;

import 'package:sqflite/sqflite.dart';

import '../core_database.dart';
import 'group_models.dart';

class GroupRoomRepository {
  GroupRoomRepository({CoreDatabase? coreDatabase, GroupIdFactory? idFactory})
    : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
      _ids = idFactory ?? GroupIdFactory();

  final CoreDatabase _coreDatabase;
  final GroupIdFactory _ids;

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<GroupRoom> createRoom({
    required String title,
    required List<String> participantAssistantIds,
    String roomInstruction = '',
    bool sequentialEnabled = true,
    bool manualMentionEnabled = true,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) throw ArgumentError('群名称不能为空');
    final participantIds = participantAssistantIds
        .map((id) => id.trim())
        .toList(growable: false);
    if (participantIds.length < 2 || participantIds.toSet().length < 2) {
      throw ArgumentError('群聊至少需要两名不同的助手');
    }
    if (participantIds.any((id) => id.isEmpty) ||
        participantIds.toSet().length != participantIds.length) {
      throw ArgumentError('群成员不能重复或为空');
    }

    final database = await _coreDatabase.open();
    final roomId = _ids.next('group_room');
    final now = _now();
    await database.transaction((txn) async {
      final placeholders = List.filled(participantIds.length, '?').join(',');
      final assistants = await txn.query(
        'assistants',
        columns: ['id'],
        where: 'id IN ($placeholders)',
        whereArgs: participantIds,
      );
      if (assistants.length != participantIds.length) {
        throw StateError('所选助手不存在，请重新选择');
      }
      await txn.insert('group_rooms', {
        'room_id': roomId,
        'title': normalizedTitle,
        'room_instruction': roomInstruction.trim(),
        'sequential_enabled': sequentialEnabled ? 1 : 0,
        'manual_mention_enabled': 1,
        'status': 'active',
        'next_sequence': 1,
        'draft_text': '',
        'created_at': now,
        'updated_at': now,
      });
      for (var index = 0; index < participantIds.length; index++) {
        await txn.insert('group_participants', {
          'room_id': roomId,
          'assistant_id': participantIds[index],
          'speak_order': index,
          'created_at': now,
        });
      }
      await txn.insert('group_room_read_state', {
        'room_id': roomId,
        'last_read_sequence': 0,
        'last_read_at': now,
      });
    });
    return (await getRoom(roomId))!;
  }

  Future<GroupRoom?> getRoom(String roomId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_rooms',
      where: 'room_id = ?',
      whereArgs: [roomId],
      limit: 1,
    );
    return rows.isEmpty ? null : GroupRoom.fromRow(rows.single);
  }

  Future<List<GroupRoom>> listRooms({bool includeArchived = false}) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_rooms',
      where: includeArchived ? "status != 'deleted'" : "status = 'active'",
      orderBy: 'updated_at DESC',
    );
    return rows.map(GroupRoom.fromRow).toList(growable: false);
  }

  Future<List<GroupParticipant>> getParticipants(String roomId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_participants',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'speak_order ASC',
    );
    return rows.map(GroupParticipant.fromRow).toList(growable: false);
  }

  Future<bool> isParticipant(String roomId, String assistantId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_participants',
      columns: ['assistant_id'],
      where: 'room_id = ? AND assistant_id = ?',
      whereArgs: [roomId, assistantId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> updateSettings({
    required String roomId,
    required String title,
    required String roomInstruction,
    required bool sequentialEnabled,
    required bool manualMentionEnabled,
    required List<String> participantOrder,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('群名称不能为空');
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      final current = await txn.query(
        'group_participants',
        columns: ['assistant_id'],
        where: 'room_id = ?',
        whereArgs: [roomId],
      );
      final currentIds = current
          .map((row) => row['assistant_id']! as String)
          .toSet();
      if (participantOrder.length != currentIds.length ||
          participantOrder.toSet().length != currentIds.length ||
          !participantOrder.toSet().containsAll(currentIds)) {
        throw StateError('群成员创建后不能增删');
      }
      final updated = await txn.update(
        'group_rooms',
        {
          'title': title.trim(),
          'room_instruction': roomInstruction.trim(),
          'sequential_enabled': sequentialEnabled ? 1 : 0,
          'manual_mention_enabled': 1,
          'updated_at': _now(),
        },
        where: "room_id = ? AND status != 'deleted'",
        whereArgs: [roomId],
      );
      if (updated != 1) throw StateError('群聊不存在');
      // 先写远离正式范围的临时顺序，避免唯一索引在互换时中途冲突。
      for (var index = 0; index < participantOrder.length; index++) {
        await txn.update(
          'group_participants',
          {'speak_order': 1000000 + index},
          where: 'room_id = ? AND assistant_id = ?',
          whereArgs: [roomId, participantOrder[index]],
        );
      }
      for (var index = 0; index < participantOrder.length; index++) {
        await txn.update(
          'group_participants',
          {'speak_order': index},
          where: 'room_id = ? AND assistant_id = ?',
          whereArgs: [roomId, participantOrder[index]],
        );
      }
    });
  }

  Future<void> saveDraft(String roomId, String draftText) async {
    final database = await _coreDatabase.open();
    final now = _now();
    final changed = await database.update(
      'group_rooms',
      {
        'draft_text': draftText,
        'draft_updated_at': draftText.isEmpty ? null : now,
        'updated_at': now,
      },
      where: "room_id = ? AND status != 'deleted'",
      whereArgs: [roomId],
    );
    if (changed != 1) throw StateError('群聊不存在');
  }

  Future<void> markRead(String roomId, int sequence) async {
    final database = await _coreDatabase.open();
    final blockingRows = await database.rawQuery(
      '''
      SELECT MIN(sequence) AS sequence
      FROM group_messages
      WHERE room_id = ?
        AND sequence <= ?
        AND is_deleted = 0
        AND visible = 1
        AND speaker_type = 'assistant'
        AND answer_status = 'streaming'
      ''',
      [roomId, sequence],
    );
    final blockingSequence = blockingRows.single['sequence'] as int?;
    final readableSequence = blockingSequence == null
        ? sequence
        : (sequence < blockingSequence ? sequence : blockingSequence - 1);
    if (readableSequence < 0) return;
    await database.rawInsert(
      '''
      INSERT INTO group_room_read_state (room_id, last_read_sequence, last_read_at)
      VALUES (?, ?, ?)
      ON CONFLICT(room_id) DO UPDATE SET
        last_read_sequence = MAX(last_read_sequence, excluded.last_read_sequence),
        last_read_at = excluded.last_read_at
      ''',
      [roomId, readableSequence, _now()],
    );
  }

  Future<int> unreadCount(String roomId) async {
    final database = await _coreDatabase.open();
    final rows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM group_messages m
      LEFT JOIN group_room_read_state r ON r.room_id = m.room_id
      WHERE m.room_id = ? AND m.is_deleted = 0 AND m.visible = 1
        AND m.speaker_type = 'assistant'
        AND (
          m.answer_status IN ('completed', 'failed')
          OR (
            m.answer_status = 'cancelled'
            AND TRIM(COALESCE(m.content, '')) NOT IN ('', '回复已中断')
          )
        )
        AND m.sequence > COALESCE(r.last_read_sequence, 0)
      ''',
      [roomId],
    );
    return rows.single['count']! as int;
  }

  Future<void> softDelete(String roomId) async {
    final database = await _coreDatabase.open();
    final changed = await database.update(
      'group_rooms',
      {'status': 'deleted', 'updated_at': _now()},
      where: "room_id = ? AND status != 'deleted'",
      whereArgs: [roomId],
    );
    if (changed == 0 && await getRoom(roomId) == null) {
      throw StateError('群聊不存在');
    }
  }

  Future<int> reserveSequence(
    DatabaseExecutor transaction,
    String roomId,
  ) async {
    final changed = await transaction.rawUpdate(
      '''
      UPDATE group_rooms
      SET next_sequence = next_sequence + 1, updated_at = ?
      WHERE room_id = ? AND status = 'active'
      ''',
      [_now(), roomId],
    );
    if (changed != 1) throw StateError('群聊不存在或不可用');
    final rows = await transaction.query(
      'group_rooms',
      columns: ['next_sequence'],
      where: 'room_id = ?',
      whereArgs: [roomId],
      limit: 1,
    );
    return (rows.single['next_sequence']! as int) - 1;
  }
}
