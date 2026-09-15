library;

import 'package:sqflite/sqflite.dart';

import '../core_database.dart';
import '../import/content_hash.dart';
import '../../models/message.dart';
import 'group_models.dart';
import 'group_attachment_repository.dart';
import 'group_room_repository.dart';

class GroupMessageRepository {
  GroupMessageRepository({
    CoreDatabase? coreDatabase,
    GroupRoomRepository? roomRepository,
    GroupIdFactory? idFactory,
    GroupAttachmentRepository? attachmentRepository,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _rooms =
           roomRepository ?? GroupRoomRepository(coreDatabase: coreDatabase),
       _ids = idFactory ?? GroupIdFactory(),
       _attachments =
           attachmentRepository ??
           GroupAttachmentRepository(coreDatabase: coreDatabase);

  final CoreDatabase _coreDatabase;
  final GroupRoomRepository _rooms;
  final GroupIdFactory _ids;
  final GroupAttachmentRepository _attachments;

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<GroupMessage> createUserMessage({
    required String roomId,
    required String content,
    String requestType = 'sequential',
    DatabaseExecutor? transaction,
    bool allowEmpty = false,
  }) async {
    final normalized = content.trim();
    if (normalized.isEmpty && !allowEmpty) throw ArgumentError('消息内容不能为空');
    if (transaction != null) {
      final messageId = await _insertMessage(
        transaction,
        roomId: roomId,
        speakerType: 'user',
        content: normalized,
        requestType: requestType,
        createMessageVersion: true,
      );
      final rows = await transaction.query(
        'group_messages',
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      return GroupMessage.fromRow(rows.single);
    }
    final database = await _coreDatabase.open();
    late String messageId;
    await database.transaction((txn) async {
      messageId = await _insertMessage(
        txn,
        roomId: roomId,
        speakerType: 'user',
        content: normalized,
        requestType: requestType,
        createMessageVersion: true,
      );
    });
    return (await getMessage(messageId))!;
  }

  Future<GroupMessage> createAssistantPlaceholder({
    required String roomId,
    required String assistantId,
    String? rootTriggerMessageId,
    required int roundPosition,
    required String requestType,
    String? replyToMessageId,
    DatabaseExecutor? transaction,
  }) async {
    final database = transaction ?? await _coreDatabase.open();
    final messageId = await _insertMessage(
      database,
      roomId: roomId,
      speakerType: 'assistant',
      speakerAssistantId: assistantId,
      content: '',
      requestType: requestType,
      rootTriggerMessageId: rootTriggerMessageId,
      replyToMessageId: replyToMessageId,
      roundPosition: roundPosition,
      answerStatus: 'queued',
    );
    if (transaction != null) {
      final rows = await transaction.query(
        'group_messages',
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      return GroupMessage.fromRow(rows.single);
    }
    return (await getMessage(messageId))!;
  }

  Future<String> _insertMessage(
    DatabaseExecutor transaction, {
    required String roomId,
    required String speakerType,
    String? speakerAssistantId,
    required String content,
    required String requestType,
    String? replyToMessageId,
    String? rootTriggerMessageId,
    int? roundPosition,
    String? answerStatus,
    bool createMessageVersion = false,
  }) async {
    final now = _now();
    final sequence = await _rooms.reserveSequence(transaction, roomId);
    final messageId = _ids.next('group_message');
    final hash = sha256Text(content);
    String? versionId;
    if (createMessageVersion) {
      versionId = _ids.next('group_message_version');
    }
    await transaction.insert('group_messages', {
      'message_id': messageId,
      'room_id': roomId,
      'sequence': sequence,
      'speaker_type': speakerType,
      'speaker_assistant_id': speakerAssistantId,
      'content': content,
      'reply_to_message_id': replyToMessageId,
      'root_trigger_message_id': rootTriggerMessageId,
      'round_position': roundPosition,
      'request_type': requestType,
      'revision': 1,
      'current_message_version_id': versionId,
      'answer_status': answerStatus,
      'content_hash': hash,
      'created_at': now,
      'updated_at': now,
    });
    if (versionId != null) {
      await transaction.insert('group_message_versions', {
        'version_id': versionId,
        'message_id': messageId,
        'version_number': 1,
        'content': content,
        'content_hash': hash,
        'edited_by': 'user',
        'created_at': now,
      });
    }
    return messageId;
  }

  Future<GroupAnswerVersion> startAnswerVersion({
    required String messageId,
    required String upstreamRevisionHash,
    required int contextCutoffSequence,
    DatabaseExecutor? transaction,
  }) async {
    Future<GroupAnswerVersion> create(DatabaseExecutor database) async {
      final rows = await database.query(
        'group_messages',
        columns: ['speaker_type', 'answer_version_count'],
        where: 'message_id = ? AND is_deleted = 0',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['speaker_type'] != 'assistant') {
        throw StateError('群助手消息不存在');
      }
      final versionNumber = (rows.single['answer_version_count']! as int) + 1;
      final answerVersionId = _ids.next('group_answer_version');
      final now = _now();
      await database.update(
        'group_answer_versions',
        {'branch_active': 0},
        where: 'message_id = ? AND branch_active = 1',
        whereArgs: [messageId],
      );
      await database.insert('group_answer_versions', {
        'answer_version_id': answerVersionId,
        'message_id': messageId,
        'version_number': versionNumber,
        'answer_status': 'streaming',
        'upstream_revision_hash': upstreamRevisionHash,
        'context_cutoff_sequence': contextCutoffSequence,
        'branch_active': 1,
        'created_at': now,
      });
      await database.update(
        'group_messages',
        {
          'current_answer_version_id': answerVersionId,
          'current_answer_version_number': versionNumber,
          'answer_version_count': versionNumber,
          'answer_status': 'streaming',
          'upstream_revision_hash': upstreamRevisionHash,
          'upstream_status': 'current',
          'updated_at': now,
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      final created = await database.query(
        'group_answer_versions',
        where: 'answer_version_id = ?',
        whereArgs: [answerVersionId],
        limit: 1,
      );
      return GroupAnswerVersion.fromRow(created.single);
    }

    if (transaction != null) return create(transaction);
    final database = await _coreDatabase.open();
    return database.transaction(create);
  }

  Future<GroupMessage> commitAssistantReply({
    required String messageId,
    required String answerVersionId,
    required String content,
    String? reasoning,
    List<String> segments = const [],
    int? promptTokens,
    int? completionTokens,
    bool toolUsed = false,
  }) async {
    final normalized = content.trim();
    if (normalized.isEmpty) throw ArgumentError('助手回复不能为空');
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      final versions = await txn.query(
        'group_answer_versions',
        columns: ['message_id', 'answer_status'],
        where: 'answer_version_id = ?',
        whereArgs: [answerVersionId],
        limit: 1,
      );
      if (versions.isEmpty || versions.single['message_id'] != messageId) {
        throw StateError('群回答版本不存在');
      }
      if (versions.single['answer_status'] == 'completed') return;
      final now = _now();
      final hash = sha256Text(content);
      await txn.update(
        'group_answer_versions',
        {
          'content': content,
          'reasoning': reasoning,
          'answer_status': 'completed',
          'failure_hint': null,
          'prompt_tokens': promptTokens,
          'completion_tokens': completionTokens,
          'tool_used': toolUsed ? 1 : 0,
          'completed_at': now,
        },
        where: 'answer_version_id = ?',
        whereArgs: [answerVersionId],
      );
      await txn.update(
        'group_messages',
        {
          'content': content,
          'reasoning': reasoning,
          'answer_status': 'completed',
          'failure_hint': null,
          'tool_used': toolUsed ? 1 : 0,
          'content_hash': hash,
          'updated_at': now,
        },
        where:
            'message_id = ? AND current_answer_version_id = ? AND is_deleted = 0',
        whereArgs: [messageId, answerVersionId],
      );
      await txn.delete(
        'group_message_segments',
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      final durableSegments = segments.where((item) => item.trim().isNotEmpty);
      var index = 0;
      for (final segment in durableSegments) {
        await txn.insert('group_message_segments', {
          'message_id': messageId,
          'segment_index': index++,
          'content': segment,
        });
      }
    });
    return (await getMessage(messageId))!;
  }

  Future<void> failAssistantReply({
    required String messageId,
    required String answerVersionId,
    required String failureHint,
    String content = '',
    bool cancelled = false,
  }) async {
    final database = await _coreDatabase.open();
    final status = cancelled ? 'cancelled' : 'failed';
    final now = _now();
    await database.transaction((txn) async {
      await txn.update(
        'group_answer_versions',
        {
          'content': content,
          'answer_status': status,
          'failure_hint': failureHint,
          'completed_at': now,
        },
        where: 'answer_version_id = ? AND message_id = ?',
        whereArgs: [answerVersionId, messageId],
      );
      await txn.update(
        'group_messages',
        {
          'content': content,
          'answer_status': status,
          'failure_hint': failureHint,
          'content_hash': sha256Text(content),
          'updated_at': now,
        },
        where: 'message_id = ? AND current_answer_version_id = ?',
        whereArgs: [messageId, answerVersionId],
      );
    });
  }

  Future<GroupMessage?> getMessage(String messageId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final message = GroupMessage.fromRow(rows.single);
    return message.copyWithMedia(
      attachments: await _attachments.listForMessage(message.messageId),
      voiceSegments: await _voiceForMessage(database, message),
    );
  }

  Future<List<GroupMessage>> listMessages(
    String roomId, {
    int? beforeSequence,
    int limit = 50,
    bool includeDeleted = false,
  }) async {
    final database = await _coreDatabase.open();
    final clauses = <String>['room_id = ?'];
    final arguments = <Object?>[roomId];
    if (beforeSequence != null) {
      clauses.add('sequence < ?');
      arguments.add(beforeSequence);
    }
    if (!includeDeleted) clauses.add('is_deleted = 0');
    final rows = await database.query(
      'group_messages',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'sequence DESC',
      limit: limit,
    );
    final messages = rows.reversed.map(GroupMessage.fromRow).toList();
    return Future.wait(
      messages.map(
        (message) async => message.copyWithMedia(
          attachments: await _attachments.listForMessage(message.messageId),
          voiceSegments: await _voiceForMessage(database, message),
        ),
      ),
    );
  }

  Future<List<VoiceMessageInfo>> _voiceForMessage(
    Database database,
    GroupMessage message,
  ) async {
    final versionClause = message.speakerType == 'assistant'
        ? 'answer_version_id = ?'
        : 'answer_version_id IS NULL';
    final rows = await database.query(
      'group_message_voice_assets',
      where: "message_id = ? AND state = 'ready' AND $versionClause",
      whereArgs: [
        message.messageId,
        if (message.speakerType == 'assistant')
          message.currentAnswerVersionId ?? '',
      ],
      orderBy: 'segment_index ASC, created_at ASC',
    );
    return rows
        .map((row) => VoiceMessageInfo.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<String>> getSegments(String messageId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'group_message_segments',
      columns: ['content'],
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'segment_index ASC',
    );
    return rows.map((row) => row['content']! as String).toList(growable: false);
  }

  Future<void> setVoiceTranscriptVisible({
    required String assetId,
    required bool visible,
  }) async {
    final database = await _coreDatabase.open();
    await database.update(
      'group_message_voice_assets',
      <String, Object?>{
        'transcript_visible': visible ? 1 : 0,
        'updated_at': _now(),
      },
      where: "asset_id = ? AND state = 'ready'",
      whereArgs: <Object?>[assetId],
    );
  }

  Future<void> softDelete(String messageId) async {
    final database = await _coreDatabase.open();
    final changed = await database.update(
      'group_messages',
      {
        'is_deleted': 1,
        'visible': 0,
        'context_visible': 0,
        'updated_at': _now(),
      },
      where: 'message_id = ? AND is_deleted = 0',
      whereArgs: [messageId],
    );
    if (changed == 0 && await getMessage(messageId) == null) {
      throw StateError('群消息不存在');
    }
  }
}
