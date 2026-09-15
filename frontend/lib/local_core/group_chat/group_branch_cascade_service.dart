library;

import 'package:sqflite/sqflite.dart';

import '../core_database.dart';
import '../import/content_hash.dart';
import '../local_job_service.dart';
import 'group_message_repository.dart';
import 'group_models.dart';
import 'group_round_repository.dart';
import 'group_round_task.dart';
import 'group_room_repository.dart';
import 'group_upstream_revision_hasher.dart';

class GroupBranchCascadeLaunch {
  const GroupBranchCascadeLaunch({required this.round, required this.jobId});

  final GroupRound round;
  final String? jobId;
}

/// 分支变动后的私有派生数据通知。公共群聊只保留分支状态机，不挂载此回调。
class GroupBranchDerivedChange {
  const GroupBranchDerivedChange({
    required this.roomId,
    required this.participantAssistantIds,
    required this.changeType,
    this.changedCurrentIds = const {},
    this.staleDownstreamIds = const {},
  });

  final String roomId;
  final Set<String> participantAssistantIds;
  final String changeType;
  final Set<String> changedCurrentIds;
  final Set<String> staleDownstreamIds;
}

typedef GroupBranchDerivedHook = Future<void> Function(
  GroupBranchDerivedChange change,
);

class GroupBranchCascadeService {
  GroupBranchCascadeService({
    CoreDatabase? coreDatabase,
    GroupRoomRepository? roomRepository,
    GroupMessageRepository? messageRepository,
    GroupRoundRepository? roundRepository,
    LocalJobService? jobService,
    GroupIdFactory? idFactory,
    GroupBranchDerivedHook? derivedSourceHook,
    GroupUpstreamRevisionHasher? upstreamRevisionHasher,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _rooms =
           roomRepository ?? GroupRoomRepository(coreDatabase: coreDatabase),
       _messages =
           messageRepository ??
           GroupMessageRepository(coreDatabase: coreDatabase),
       _rounds =
           roundRepository ?? GroupRoundRepository(coreDatabase: coreDatabase),
       _jobs = jobService ?? LocalJobService(coreDatabase: coreDatabase),
       _ids = idFactory ?? GroupIdFactory(),
       _derivedSourceHook = derivedSourceHook,
       _upstreamHasher =
           upstreamRevisionHasher ??
           GroupUpstreamRevisionHasher(coreDatabase: coreDatabase);

  final CoreDatabase _coreDatabase;
  final GroupRoomRepository _rooms;
  final GroupMessageRepository _messages;
  final GroupRoundRepository _rounds;
  final LocalJobService _jobs;
  final GroupIdFactory _ids;
  final GroupBranchDerivedHook? _derivedSourceHook;
  final GroupUpstreamRevisionHasher _upstreamHasher;

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<({GroupMessageVersion version, GroupBranchCascadeLaunch launch})>
  editUserMessage({required String messageId, required String content}) async {
    final normalized = content.trim();
    if (normalized.isEmpty) throw ArgumentError('消息内容不能为空');
    final database = await _coreDatabase.open();
    late String versionId;
    late GroupRound round;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'group_messages',
        columns: ['room_id', 'speaker_type', 'revision', 'is_deleted'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isEmpty ||
          rows.single['speaker_type'] != 'user' ||
          rows.single['is_deleted'] == 1) {
        throw StateError('可编辑的群用户消息不存在');
      }
      final roomId = rows.single['room_id']! as String;
      await _ensureRoomIdle(txn, roomId);
      final branch = await _branchMessages(
        txn,
        roomId: roomId,
        rootMessageId: messageId,
      );
      final fallbackParticipants = branch.isEmpty
          ? await txn.query(
              'group_participants',
              columns: ['assistant_id'],
              where: 'room_id = ?',
              whereArgs: [roomId],
              orderBy: 'speak_order ASC',
            )
          : const <Map<String, Object?>>[];
      final participantOrder = branch.isNotEmpty
          ? branch.map((item) => item.assistantId).toList()
          : fallbackParticipants
                .map((item) => item['assistant_id']! as String)
                .toList();
      if (participantOrder.isEmpty) {
        throw StateError('群聊没有可回复的助手成员');
      }
      final nextVersion = (rows.single['revision']! as int) + 1;
      versionId = _ids.next('group_message_version');
      final hash = sha256Text(normalized);
      final now = _now();
      await txn.insert('group_message_versions', {
        'version_id': versionId,
        'message_id': messageId,
        'version_number': nextVersion,
        'content': normalized,
        'content_hash': hash,
        'edited_by': 'user',
        'created_at': now,
      });
      await txn.update(
        'group_messages',
        {
          'content': normalized,
          'revision': nextVersion,
          'current_message_version_id': versionId,
          'content_hash': hash,
          'updated_at': now,
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      final parentId = await _deactivateCurrentBranch(
        txn,
        rootMessageId: messageId,
        now: now,
      );
      final logicalIds = branch.map((item) => item.messageId).toList();
      await _markStale(txn, logicalIds, now);
      round = await _rounds.createRound(
        roomId: roomId,
        requestType: 'sequential',
        participantOrder: participantOrder,
        logicalMessageIds: logicalIds.isEmpty ? null : logicalIds,
        rootTriggerMessageId: messageId,
        triggerMessageVersionId: versionId,
        branchParentRoundId: parentId,
        transaction: txn,
      );
    });
    await _notifyDerived(
      GroupBranchDerivedChange(
        roomId: round.roomId,
        participantAssistantIds: round.participantOrder.toSet(),
        changeType: 'edit',
        changedCurrentIds: {messageId},
        staleDownstreamIds: (await _rounds.getSteps(
          round.roundId,
        )).map((step) => step.logicalMessageId).toSet(),
      ),
    );
    final launch = await _launch(round);
    return (version: (await _messageVersion(versionId))!, launch: launch);
  }

  Future<GroupBranchCascadeLaunch> regenerateFromAssistantMessage(
    String messageId,
  ) async {
    final database = await _coreDatabase.open();
    late GroupRound round;
    await database.transaction((txn) async {
      final targets = await txn.query(
        'group_messages',
        where:
            "message_id = ? AND speaker_type = 'assistant' AND is_deleted = 0",
        whereArgs: [messageId],
        limit: 1,
      );
      if (targets.isEmpty ||
          targets.single['root_trigger_message_id'] == null) {
        throw StateError('可重新回答的群消息不存在');
      }
      final target = targets.single;
      final roomId = target['room_id']! as String;
      final rootId = target['root_trigger_message_id']! as String;
      await _ensureRoomIdle(txn, roomId);
      final branch = await _branchMessages(
        txn,
        roomId: roomId,
        rootMessageId: rootId,
      );
      final start = branch.indexWhere((item) => item.messageId == messageId);
      if (start < 0) throw StateError('可重新回答的群消息不在当前分支');
      final selected = branch.skip(start).toList(growable: false);
      final now = _now();
      final parentId = await _deactivateCurrentBranch(
        txn,
        rootMessageId: rootId,
        now: now,
      );
      await _markStale(
        txn,
        selected.map((item) => item.messageId).toList(),
        now,
      );
      final root = await txn.query(
        'group_messages',
        columns: ['current_message_version_id'],
        where: 'message_id = ? AND is_deleted = 0',
        whereArgs: [rootId],
        limit: 1,
      );
      if (root.isEmpty) throw StateError('原用户消息已不存在');
      round = await _rounds.createRound(
        roomId: roomId,
        requestType: 'sequential',
        participantOrder: selected.map((item) => item.assistantId).toList(),
        logicalMessageIds: selected.map((item) => item.messageId).toList(),
        rootTriggerMessageId: rootId,
        triggerMessageVersionId:
            root.single['current_message_version_id'] as String?,
        branchParentRoundId: parentId,
        transaction: txn,
      );
    });
    await _notifyDerived(
      GroupBranchDerivedChange(
        roomId: round.roomId,
        participantAssistantIds: round.participantOrder.toSet(),
        changeType: 'regenerate',
        staleDownstreamIds: (await _rounds.getSteps(
          round.roundId,
        )).map((step) => step.logicalMessageId).toSet(),
      ),
    );
    final launch = await _launch(round);
    return launch;
  }

  Future<({GroupAnswerVersion version, GroupBranchCascadeLaunch? launch})>
  switchAnswerVersion({
    required String messageId,
    required String answerVersionId,
  }) async {
    final database = await _coreDatabase.open();
    GroupRound? round;
    var selectionChanged = false;
    await database.transaction((txn) async {
      final messageRows = await txn.query(
        'group_messages',
        where:
            "message_id = ? AND speaker_type = 'assistant' AND is_deleted = 0",
        whereArgs: [messageId],
        limit: 1,
      );
      if (messageRows.isEmpty) throw StateError('群助手消息不存在');
      final message = messageRows.single;
      final roomId = message['room_id']! as String;
      final rootId = message['root_trigger_message_id'] as String?;
      if (rootId == null) throw StateError('该回答没有可级联的原消息');
      await _ensureRoomIdle(txn, roomId);
      final versions = await txn.query(
        'group_answer_versions',
        where:
            "answer_version_id = ? AND message_id = ? AND answer_status = 'completed'",
        whereArgs: [answerVersionId, messageId],
        limit: 1,
      );
      if (versions.isEmpty) throw StateError('可切换的回答版本不存在');
      final selected = versions.single;
      if (message['current_answer_version_id'] == answerVersionId) return;
      selectionChanged = true;
      final downstream = await _cascadeDownstreamForSelection(
        txn,
        message: message,
        selected: selected,
      );
      final now = _now();
      await txn.update(
        'group_answer_versions',
        {'branch_active': 0},
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      await txn.update(
        'group_answer_versions',
        {'branch_active': 1},
        where: 'answer_version_id = ?',
        whereArgs: [answerVersionId],
      );
      await txn.update(
        'group_messages',
        {
          'content': selected['content'],
          'reasoning': selected['reasoning'],
          'answer_status': selected['answer_status'],
          'failure_hint': selected['failure_hint'],
          'tool_used': selected['tool_used'],
          'current_answer_version_id': answerVersionId,
          'current_answer_version_number': selected['version_number'],
          'upstream_revision_hash': selected['upstream_revision_hash'],
          'upstream_status': 'current',
          'content_hash': sha256Text(selected['content']! as String),
          'updated_at': now,
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      if (downstream.isNotEmpty) {
        final parentId = await _deactivateCurrentBranch(
          txn,
          rootMessageId: rootId,
          now: now,
        );
        await _markStale(
          txn,
          downstream.map((item) => item.messageId).toList(),
          now,
        );
        final root = await txn.query(
          'group_messages',
          columns: ['current_message_version_id'],
          where: 'message_id = ?',
          whereArgs: [rootId],
          limit: 1,
        );
        round = await _rounds.createRound(
          roomId: roomId,
          requestType: 'sequential',
          participantOrder: downstream.map((item) => item.assistantId).toList(),
          logicalMessageIds: downstream.map((item) => item.messageId).toList(),
          rootTriggerMessageId: rootId,
          triggerMessageVersionId:
              root.single['current_message_version_id'] as String?,
          branchParentRoundId: parentId,
          transaction: txn,
        );
      }
    });
    final selectedMessage = await _messages.getMessage(messageId);
    if (selectionChanged && selectedMessage != null) {
      await _notifyDerived(
        GroupBranchDerivedChange(
          roomId: selectedMessage.roomId,
          participantAssistantIds: (await _rooms.getParticipants(
            selectedMessage.roomId,
          )).map((item) => item.assistantId).toSet(),
          changeType: 'answer_version_switch',
          changedCurrentIds: {messageId},
          staleDownstreamIds: round == null
              ? const {}
              : (await _rounds.getSteps(
                  round!.roundId,
                )).map((step) => step.logicalMessageId).toSet(),
        ),
      );
    }
    final launch = round == null ? null : await _launch(round!);
    final rows = await database.query(
      'group_answer_versions',
      where: 'answer_version_id = ?',
      whereArgs: [answerVersionId],
      limit: 1,
    );
    return (version: GroupAnswerVersion.fromRow(rows.single), launch: launch);
  }

  Future<void> _notifyDerived(GroupBranchDerivedChange change) async {
    await _derivedSourceHook?.call(change);
  }

  Future<bool> answerVersionSwitchRequiresCascade({
    required String messageId,
    required String answerVersionId,
  }) async {
    final database = await _coreDatabase.open();
    final messageRows = await database.query(
      'group_messages',
      where: "message_id = ? AND speaker_type = 'assistant' AND is_deleted = 0",
      whereArgs: [messageId],
      limit: 1,
    );
    if (messageRows.isEmpty) throw StateError('群助手消息不存在');
    final message = messageRows.single;
    if (message['current_answer_version_id'] == answerVersionId) return false;
    final versions = await database.query(
      'group_answer_versions',
      where:
          "answer_version_id = ? AND message_id = ? AND answer_status = 'completed'",
      whereArgs: [answerVersionId, messageId],
      limit: 1,
    );
    if (versions.isEmpty) throw StateError('可切换的回答版本不存在');
    return (await _cascadeDownstreamForSelection(
      database,
      message: message,
      selected: versions.single,
    )).isNotEmpty;
  }

  Future<List<_BranchMessage>> _cascadeDownstreamForSelection(
    DatabaseExecutor database, {
    required Map<String, Object?> message,
    required Map<String, Object?> selected,
  }) async {
    final rootId = message['root_trigger_message_id'] as String?;
    if (rootId == null) return const [];
    final roomId = message['room_id']! as String;
    final messageId = message['message_id']! as String;
    final branch = await _branchMessages(
      database,
      roomId: roomId,
      rootMessageId: rootId,
    );
    final start = branch.indexWhere((item) => item.messageId == messageId);
    if (start < 0 || start + 1 >= branch.length) return const [];
    final downstream = branch.skip(start + 1).toList(growable: false);
    final selectedContent = selected['content'] as String? ?? '';
    for (var index = 0; index < downstream.length; index++) {
      final expectedHash = await _upstreamHasher.calculateWithExecutor(
        database,
        roomId: roomId,
        rootMessageId: rootId,
        logicalMessageId: downstream[index].messageId,
        overrideMessageId: messageId,
        overrideAnswerVersionId: selected['answer_version_id']! as String,
        overrideContentHash: sha256Text(selectedContent),
      );
      if (expectedHash != downstream[index].upstreamRevisionHash) {
        return downstream.skip(index).toList(growable: false);
      }
    }
    return const [];
  }

  Future<GroupBranchCascadeLaunch> _launch(GroupRound round) async {
    String? jobId;
    try {
      final job = await createGroupRoundJob(
        jobService: _jobs,
        roomId: round.roomId,
        roundId: round.roundId,
        totalSteps: round.participantOrder.length,
      );
      jobId = job.jobId;
      await _rounds.attachJob(round.roundId, job.jobId);
      await _jobs.start(job.jobId);
    } catch (_) {
      // round 仍保持 queued，启动恢复服务会补建或续跑。
    }
    return GroupBranchCascadeLaunch(round: round, jobId: jobId);
  }

  Future<void> _ensureRoomIdle(DatabaseExecutor txn, String roomId) async {
    final active = await txn.rawQuery(
      '''
      SELECT 1 FROM group_rounds
      WHERE room_id = ? AND status IN ('queued', 'running', 'cancel_requested')
      LIMIT 1
      ''',
      [roomId],
    );
    if (active.isNotEmpty) throw StateError('当前群回复尚未结束');
  }

  Future<String?> _deactivateCurrentBranch(
    DatabaseExecutor txn, {
    required String rootMessageId,
    required String now,
  }) async {
    final rows = await txn.query(
      'group_rounds',
      columns: ['round_id'],
      where: 'root_trigger_message_id = ? AND branch_active = 1',
      whereArgs: [rootMessageId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    await txn.update(
      'group_rounds',
      {'branch_active': 0, 'updated_at': now},
      where: 'root_trigger_message_id = ? AND branch_active = 1',
      whereArgs: [rootMessageId],
    );
    return rows.isEmpty ? null : rows.single['round_id'] as String;
  }

  Future<List<_BranchMessage>> _branchMessages(
    DatabaseExecutor txn, {
    required String roomId,
    required String rootMessageId,
  }) async {
    final rawRows = await txn.query(
      'group_messages',
      columns: ['message_id', 'speaker_assistant_id', 'upstream_revision_hash'],
      where:
          "room_id = ? AND root_trigger_message_id = ? AND speaker_type = 'assistant' AND is_deleted = 0",
      whereArgs: [roomId, rootMessageId],
      orderBy: 'round_position ASC, sequence ASC',
    );
    final rows = rawRows
        .map(
          (row) => <String, Object?>{
            'message_id': row['message_id'],
            'assistant_id': row['speaker_assistant_id'],
            'upstream_revision_hash': row['upstream_revision_hash'],
          },
        )
        .toList(growable: false);
    final seen = <String>{};
    return [
      for (final row in rows)
        if (row['assistant_id'] is String &&
            seen.add(row['assistant_id']! as String))
          _BranchMessage(
            messageId: row['message_id']! as String,
            assistantId: row['assistant_id']! as String,
            upstreamRevisionHash:
                row['upstream_revision_hash'] as String? ?? '',
          ),
    ];
  }

  Future<void> _markStale(
    DatabaseExecutor txn,
    List<String> messageIds,
    String now,
  ) async {
    for (final id in messageIds) {
      await txn.update(
        'group_messages',
        {'upstream_status': 'stale', 'updated_at': now},
        where: 'message_id = ? AND is_deleted = 0',
        whereArgs: [id],
      );
    }
  }

  Future<GroupMessageVersion?> _messageVersion(String versionId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_message_versions',
      where: 'version_id = ?',
      whereArgs: [versionId],
      limit: 1,
    );
    return rows.isEmpty ? null : GroupMessageVersion.fromRow(rows.single);
  }
}

class _BranchMessage {
  const _BranchMessage({
    required this.messageId,
    required this.assistantId,
    required this.upstreamRevisionHash,
  });

  final String messageId;
  final String assistantId;
  final String upstreamRevisionHash;
}
