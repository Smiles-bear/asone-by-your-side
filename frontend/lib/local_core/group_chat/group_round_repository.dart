library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core_database.dart';
import 'group_message_repository.dart';
import 'group_models.dart';

class GroupRoundRepository {
  GroupRoundRepository({
    CoreDatabase? coreDatabase,
    GroupMessageRepository? messageRepository,
    GroupIdFactory? idFactory,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _messages =
           messageRepository ??
           GroupMessageRepository(coreDatabase: coreDatabase),
       _ids = idFactory ?? GroupIdFactory();

  final CoreDatabase _coreDatabase;
  final GroupMessageRepository _messages;
  final GroupIdFactory _ids;

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<GroupRound> createRound({
    String? roundId,
    required String roomId,
    required String requestType,
    required List<String> participantOrder,
    String? rootTriggerMessageId,
    String? triggerMessageVersionId,
    String? branchParentRoundId,
    List<String>? logicalMessageIds,
    DatabaseExecutor? transaction,
  }) async {
    if (participantOrder.isEmpty ||
        participantOrder.toSet().length != participantOrder.length) {
      throw ArgumentError('轮次助手顺序不能为空或重复');
    }
    final id = roundId ?? _ids.next('group_round');
    Future<void> create(DatabaseExecutor txn) async {
      final existing = await txn.query(
        'group_rounds',
        columns: ['round_id'],
        where: 'round_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      final participants = await txn.query(
        'group_participants',
        columns: ['assistant_id'],
        where: 'room_id = ?',
        whereArgs: [roomId],
      );
      final available = participants
          .map((row) => row['assistant_id']! as String)
          .toSet();
      if (!participantOrder.every(available.contains)) {
        throw StateError('轮次包含非群成员助手');
      }
      if (logicalMessageIds != null) {
        if (logicalMessageIds.length != participantOrder.length ||
            logicalMessageIds.toSet().length != logicalMessageIds.length) {
          throw ArgumentError('复用逻辑消息必须与轮次助手一一对应且不能重复');
        }
        for (
          var position = 0;
          position < logicalMessageIds.length;
          position++
        ) {
          final rows = await txn.query(
            'group_messages',
            columns: [
              'room_id',
              'speaker_type',
              'speaker_assistant_id',
              'is_deleted',
            ],
            where: 'message_id = ?',
            whereArgs: [logicalMessageIds[position]],
            limit: 1,
          );
          if (rows.isEmpty ||
              rows.single['room_id'] != roomId ||
              rows.single['speaker_type'] != 'assistant' ||
              rows.single['speaker_assistant_id'] !=
                  participantOrder[position] ||
              rows.single['is_deleted'] == 1) {
            throw StateError('复用逻辑消息与当前房间或助手不匹配');
          }
        }
      }
      if (requestType == 'manual_mention') {
        final active = await txn.rawQuery(
          '''
          SELECT 1 FROM group_rounds
          WHERE room_id = ?
            AND status IN ('queued', 'running', 'cancel_requested')
          LIMIT 1
          ''',
          [roomId],
        );
        if (active.isNotEmpty) throw StateError('当前回复尚未结束，请稍后再点名');
      }
      final now = _now();
      await txn.insert('group_rounds', {
        'round_id': id,
        'room_id': roomId,
        'root_trigger_message_id': rootTriggerMessageId,
        'trigger_message_version_id': triggerMessageVersionId,
        'request_type': requestType,
        'branch_parent_round_id': branchParentRoundId,
        'branch_active': 1,
        'participant_order_json': jsonEncode(participantOrder),
        'status': 'queued',
        'created_at': now,
        'updated_at': now,
      });
      for (var position = 0; position < participantOrder.length; position++) {
        final logicalMessageId = logicalMessageIds?[position];
        final stepMessageId =
            logicalMessageId ??
            (await _messages.createAssistantPlaceholder(
              roomId: roomId,
              assistantId: participantOrder[position],
              rootTriggerMessageId: rootTriggerMessageId,
              roundPosition: position,
              requestType: requestType,
              replyToMessageId: rootTriggerMessageId,
              transaction: txn,
            )).messageId;
        await txn.insert('group_round_steps', {
          'round_id': id,
          'position': position,
          'assistant_id': participantOrder[position],
          'logical_message_id': stepMessageId,
          'status': 'queued',
        });
      }
    }

    if (transaction != null) {
      await create(transaction);
      final rows = await transaction.query(
        'group_rounds',
        where: 'round_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return _roundFromRow(rows.single);
    }
    final database = await _coreDatabase.open();
    await database.transaction(create);
    return (await getRound(id))!;
  }

  Future<GroupRound?> getRound(String roundId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_rounds',
      where: 'round_id = ?',
      whereArgs: [roundId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _roundFromRow(rows.single);
  }

  GroupRound _roundFromRow(Map<String, Object?> row) => GroupRound(
    roundId: row['round_id']! as String,
    roomId: row['room_id']! as String,
    rootTriggerMessageId: row['root_trigger_message_id'] as String?,
    triggerMessageVersionId: row['trigger_message_version_id'] as String?,
    requestType: row['request_type']! as String,
    branchParentRoundId: row['branch_parent_round_id'] as String?,
    branchActive: row['branch_active'] == 1,
    participantOrder:
        (jsonDecode(row['participant_order_json']! as String) as List)
            .whereType<String>()
            .toList(growable: false),
    status: row['status']! as String,
    activeJobId: row['active_job_id'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    completedAt: _date(row['completed_at']),
  );

  Future<List<GroupRoundStep>> getSteps(String roundId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_round_steps',
      where: 'round_id = ?',
      whereArgs: [roundId],
      orderBy: 'position ASC',
    );
    return rows.map(GroupRoundStep.fromRow).toList(growable: false);
  }

  Future<GroupRound?> activeRoundForRoom(String roomId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_rounds',
      where:
          "room_id = ? AND status IN ('queued', 'running', 'cancel_requested')",
      whereArgs: [roomId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _roundFromRow(rows.single);
  }

  Future<void> attachJob(String roundId, String jobId) async {
    final database = await _coreDatabase.open();
    final changed = await database.update(
      'group_rounds',
      {'active_job_id': jobId, 'updated_at': _now()},
      where:
          "round_id = ? AND status IN ('queued', 'running') AND (active_job_id IS NULL OR active_job_id = ?)",
      whereArgs: [roundId, jobId],
    );
    if (changed != 1) throw StateError('群轮次已绑定其他任务或已结束');
  }

  Future<GroupRoundStep?> claimNextStep(String roundId) async {
    final database = await _coreDatabase.open();
    GroupRoundStep? claimed;
    await database.transaction((txn) async {
      final roundRows = await txn.query(
        'group_rounds',
        columns: ['status'],
        where: 'round_id = ?',
        whereArgs: [roundId],
        limit: 1,
      );
      if (roundRows.isEmpty) throw StateError('群轮次不存在');
      final roundStatus = roundRows.single['status'];
      if (roundStatus == 'cancel_requested' || roundStatus == 'cancelled') {
        return;
      }
      final rows = await txn.query(
        'group_round_steps',
        where: "round_id = ? AND status = 'queued'",
        whereArgs: [roundId],
        orderBy: 'position ASC',
        limit: 1,
      );
      if (rows.isEmpty) return;
      final position = rows.single['position']! as int;
      final now = _now();
      final updated = await txn.update(
        'group_round_steps',
        {'status': 'running', 'started_at': now},
        where: "round_id = ? AND position = ? AND status = 'queued'",
        whereArgs: [roundId, position],
      );
      if (updated != 1) return;
      await txn.update(
        'group_rounds',
        {'status': 'running', 'updated_at': now},
        where: "round_id = ? AND status = 'queued'",
        whereArgs: [roundId],
      );
      claimed = GroupRoundStep.fromRow({
        ...rows.single,
        'status': 'running',
        'started_at': now,
      });
    });
    return claimed;
  }

  Future<void> completeStep(String roundId, int position) =>
      _finishStep(roundId, position, status: 'completed');

  Future<void> failStep(
    String roundId,
    int position, {
    required String errorCode,
  }) => _finishStep(roundId, position, status: 'failed', errorCode: errorCode);

  Future<void> failRound(
    String roundId,
    int failedPosition, {
    required String errorCode,
  }) async {
    final database = await _coreDatabase.open();
    final now = _now();
    await database.transaction((txn) async {
      await txn.update(
        'group_round_steps',
        {'status': 'failed', 'error_code': errorCode, 'completed_at': now},
        where: "round_id = ? AND position = ? AND status = 'running'",
        whereArgs: [roundId, failedPosition],
      );
      await txn.update(
        'group_round_steps',
        {'status': 'cancelled', 'completed_at': now},
        where: "round_id = ? AND status = 'queued'",
        whereArgs: [roundId],
      );
      await txn.update(
        'group_rounds',
        {'status': 'failed', 'updated_at': now, 'completed_at': now},
        where: "round_id = ? AND status IN ('queued', 'running')",
        whereArgs: [roundId],
      );
    });
  }

  Future<void> skipUnavailableStep(String roundId, int position) =>
      _finishStep(roundId, position, status: 'skipped_unavailable');

  Future<void> _finishStep(
    String roundId,
    int position, {
    required String status,
    String? errorCode,
  }) async {
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      final now = _now();
      await txn.update(
        'group_round_steps',
        {'status': status, 'error_code': errorCode, 'completed_at': now},
        where: "round_id = ? AND position = ? AND status = 'running'",
        whereArgs: [roundId, position],
      );
      await _settleRoundIfFinished(txn, roundId, now);
    });
  }

  Future<void> requestCancel(String roundId) async {
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      final now = _now();
      await txn.update(
        'group_rounds',
        {'status': 'cancel_requested', 'updated_at': now},
        where: "round_id = ? AND status IN ('queued', 'running')",
        whereArgs: [roundId],
      );
      await txn.update(
        'group_round_steps',
        {'status': 'cancelled', 'completed_at': now},
        where: "round_id = ? AND status = 'queued'",
        whereArgs: [roundId],
      );
    });
  }

  Future<void> settleCancelled(String roundId) async {
    final database = await _coreDatabase.open();
    final now = _now();
    await database.transaction((txn) async {
      await txn.update(
        'group_round_steps',
        {'status': 'cancelled', 'completed_at': now},
        where: "round_id = ? AND status IN ('queued', 'running')",
        whereArgs: [roundId],
      );
      await txn.update(
        'group_rounds',
        {'status': 'cancelled', 'updated_at': now, 'completed_at': now},
        where:
            "round_id = ? AND status IN ('cancel_requested', 'queued', 'running')",
        whereArgs: [roundId],
      );
    });
  }

  Future<void> _settleRoundIfFinished(
    DatabaseExecutor transaction,
    String roundId,
    String now,
  ) async {
    final open = await transaction.rawQuery(
      '''
      SELECT 1 FROM group_round_steps
      WHERE round_id = ? AND status IN ('queued', 'running')
      LIMIT 1
      ''',
      [roundId],
    );
    if (open.isNotEmpty) return;
    final failed = await transaction.rawQuery(
      '''
      SELECT 1 FROM group_round_steps
      WHERE round_id = ? AND status IN ('failed', 'skipped_unavailable')
      LIMIT 1
      ''',
      [roundId],
    );
    await transaction.update(
      'group_rounds',
      {
        'status': failed.isEmpty ? 'completed' : 'partial_failed',
        'updated_at': now,
        'completed_at': now,
      },
      where: "round_id = ? AND status IN ('queued', 'running')",
      whereArgs: [roundId],
    );
  }
}

DateTime? _date(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
