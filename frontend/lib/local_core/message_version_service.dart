import 'package:sqflite/sqflite.dart';

import 'core_database.dart';
import 'import/content_hash.dart';
import 'message_version_hooks.dart';
import 'message_version_models.dart';
import 'stable_id_factory.dart';

part 'message_version_tool_usage.dart';
part 'message_version_edit.dart';

/// 消息版本管理服务
///
/// 职责：
/// 1. 编辑消息或重新回答时创建新版本（保留历史）
/// 2. 切换、查询消息/回答版本
/// 3. 软删除消息
/// 4. 经生命周期钩子通知宿主派生数据重算（私有版挂记忆/关系状态，公开版为空）
class MessageVersionService {
  MessageVersionService({
    CoreDatabase? coreDatabase,
    MessageVersionLifecycleHooks? lifecycleHooks,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _lifecycleHooks =
           lifecycleHooks ??
           MessageVersionLifecycleHooksBinding.create?.call(coreDatabase);

  final CoreDatabase _coreDatabase;
  final MessageVersionLifecycleHooks? _lifecycleHooks;

  String _computeHash(String content) {
    return sha256Text(content);
  }

  bool _isFailedAnswerVersion(AnswerVersion version) {
    final finishReason = version.finishReason?.trim().toLowerCase();
    if (finishReason == null || finishReason.isEmpty) return false;
    return !const {
      'stop',
      'length',
      'tool_calls',
      'function_call',
      'content_filter',
    }.contains(finishReason);
  }

  bool _isCancelledAnswerVersion(AnswerVersion version) =>
      version.finishReason?.trim().toLowerCase() == 'cancelled';

  /// 创建新消息（带初始版本）
  Future<MessageWithVersions> createMessage({
    required String conversationId,
    required String role,
    required String content,
    String? messageId,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();
    final id = messageId ?? StableIdFactory.messageId();
    final contentHash = _computeHash(content);
    final versionId = StableIdFactory.messageVersionId();

    // 在事务中执行三步操作，防止中途失败留下孤儿记录
    await db.transaction((txn) async {
      // 1. 先创建消息镜像（外键约束要求）
      await txn.insert('messages', {
        'id': id,
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        'content_hash': contentHash,
        'revision': 1,
        'current_message_version_id': null,
        'current_answer_version_id': null,
        'current_answer_version_number': null,
        'answer_version_count': 0,
        'answer_status': null,
        'is_deleted': 0,
        'visible': 1,
        'created_at': now,
        'updated_at': now,
      });

      // 2. 再创建初始版本
      await txn.insert('message_versions', {
        'version_id': versionId,
        'message_id': id,
        'version_number': 1,
        'content': content,
        'content_hash': contentHash,
        'edited_by': null,
        'created_at': now,
      });

      // 3. 更新消息镜像，指向初始版本
      await txn.update(
        'messages',
        {'current_message_version_id': versionId},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await _lifecycleHooks?.registerMessage(id);

    return MessageWithVersions(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content,
      revision: 1,
      currentMessageVersionId: versionId,
      currentAnswerVersionId: null,
      currentAnswerVersionNumber: null,
      answerVersionCount: 0,
      answerStatus: null,
      isDeleted: false,
      visible: true,
      contentHash: contentHash,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 开始流式回答（创建进行中的回答版本）
  ///
  /// 首次回答在请求发出前就建立持久化消息和回答版本。这样页面离开、
  /// 工具调用或零正文中断都能更新同一个气泡，而不会依赖内存占位。
  Future<AnswerVersion> startInitialStreamingAnswer({
    required String conversationId,
    String? modelServiceId,
    String? modelName,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    final messageId = StableIdFactory.messageId();
    final answerVersionId = StableIdFactory.answerVersionId();
    final emptyHash = _computeHash('');

    await db.transaction((txn) async {
      await txn.insert('messages', {
        'id': messageId,
        'conversation_id': conversationId,
        'role': 'assistant',
        'content': '',
        'content_hash': emptyHash,
        'current_answer_version_id': answerVersionId,
        'current_answer_version_number': 1,
        'answer_version_count': 1,
        'answer_status': 'streaming',
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('answer_versions', {
        'answer_version_id': answerVersionId,
        'message_id': messageId,
        'version_number': 1,
        'content': '',
        'content_hash': emptyHash,
        'model_service_id': modelServiceId,
        'model_name': modelName,
        'prompt_tokens': null,
        'completion_tokens': null,
        'finish_reason': null,
        'reasoning': null,
        'tool_used': 0,
        'branch_parent_version_id': null,
        'branch_active': 1,
        'created_at': now,
      });
      await txn.update(
        'conversations',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
    await _lifecycleHooks?.registerMessage(
      messageId,
      changedAt: DateTime.parse(now),
    );

    return AnswerVersion(
      answerVersionId: answerVersionId,
      messageId: messageId,
      versionNumber: 1,
      content: '',
      contentHash: emptyHash,
      modelServiceId: modelServiceId,
      modelName: modelName,
      branchActive: true,
      createdAt: now,
    );
  }

  Future<AnswerVersion> startStreamingAnswer({
    required String messageId,
    String? modelServiceId,
    String? modelName,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();

    final messageRows = await db.query(
      'messages',
      columns: [
        'conversation_id',
        'content',
        'content_hash',
        'reasoning',
        'tool_used',
        'answer_status',
        'elapsed_ms',
        'answer_version_count',
        'current_answer_version_id',
      ],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    if (messageRows.isEmpty) {
      throw StateError('消息不存在：$messageId');
    }

    final message = messageRows.single;
    var currentAnswerCount = message['answer_version_count'] as int;
    var parentAnswerVersionId = message['current_answer_version_id'] as String?;
    final answerVersionId = StableIdFactory.answerVersionId();
    late final int newAnswerVersionNumber;
    await db.transaction((txn) async {
      // 普通首答历史上没有 answer_versions。第一次重新回答时先把当前
      // 镜像固化为 v1，保证旧回答可切回且版本号从 2/2 开始。
      if (parentAnswerVersionId == null) {
        parentAnswerVersionId = StableIdFactory.answerVersionId();
        currentAnswerCount += 1;
        await txn.insert('answer_versions', {
          'answer_version_id': parentAnswerVersionId,
          'message_id': messageId,
          'version_number': currentAnswerCount,
          'content': message['content'] as String? ?? '',
          'content_hash':
              message['content_hash'] as String? ??
              _computeHash(message['content'] as String? ?? ''),
          'model_service_id': null,
          'model_name': null,
          'prompt_tokens': null,
          'completion_tokens': null,
          'finish_reason': message['answer_status'] == 'failed'
              ? 'error'
              : 'stop',
          'elapsed_ms': message['elapsed_ms'],
          'reasoning': message['reasoning'],
          'tool_used': message['tool_used'] as int? ?? 0,
          'branch_parent_version_id': null,
          'branch_active': 1,
          'created_at': now,
        });
      }

      await _captureCurrentBranch(
        txn,
        rootMessageId: messageId,
        answerVersionId: parentAnswerVersionId!,
      );
      await txn.delete(
        'message_segments',
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      await _hideDownstream(txn, rootMessageId: messageId);
      await txn.update(
        'answer_versions',
        {'branch_active': 0},
        where: 'message_id = ?',
        whereArgs: [messageId],
      );

      newAnswerVersionNumber = currentAnswerCount + 1;
      await txn.insert('answer_versions', {
        'answer_version_id': answerVersionId,
        'message_id': messageId,
        'version_number': newAnswerVersionNumber,
        'content': '',
        'content_hash': _computeHash(''),
        'model_service_id': modelServiceId,
        'model_name': modelName,
        'prompt_tokens': null,
        'completion_tokens': null,
        'finish_reason': null,
        'elapsed_ms': null,
        'reasoning': null,
        'branch_parent_version_id': parentAnswerVersionId,
        'branch_active': 1,
        'created_at': now,
      });
      await txn.update(
        'messages',
        {
          'content': '',
          'content_hash': _computeHash(''),
          'current_answer_version_id': answerVersionId,
          'current_answer_version_number': newAnswerVersionNumber,
          'answer_version_count': newAnswerVersionNumber,
          'answer_status': 'streaming',
          'elapsed_ms': null,
          'reasoning': null,
          'tool_used': 0,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    });
    await _markDownstreamChanged(messageId);
    await _lifecycleHooks?.markMessageChanged(messageId);

    return AnswerVersion(
      answerVersionId: answerVersionId,
      messageId: messageId,
      versionNumber: newAnswerVersionNumber,
      content: '',
      contentHash: _computeHash(''),
      modelServiceId: modelServiceId,
      modelName: modelName,
      promptTokens: null,
      completionTokens: null,
      finishReason: null,
      reasoning: null,
      branchParentVersionId: parentAnswerVersionId,
      branchActive: true,
      createdAt: now,
    );
  }

  /// 更新流式回答内容（增量更新）
  Future<void> updateStreamingAnswer({
    required String answerVersionId,
    required String messageId,
    required String content,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();
    final contentHash = _computeHash(content);

    // 更新回答版本内容
    await db.update(
      'answer_versions',
      {'content': content, 'content_hash': contentHash},
      where: 'answer_version_id = ?',
      whereArgs: [answerVersionId],
    );

    // 同步更新消息镜像
    await db.update(
      'messages',
      {'content': content, 'content_hash': contentHash, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> setAnswerElapsed({
    required String answerVersionId,
    required String messageId,
    required int elapsedMs,
  }) async {
    final db = await _coreDatabase.open();
    final value = elapsedMs.clamp(1, 1 << 31);
    await db.transaction((txn) async {
      await txn.update(
        'answer_versions',
        {'elapsed_ms': value},
        where: 'answer_version_id = ? AND message_id = ?',
        whereArgs: [answerVersionId, messageId],
      );
      await txn.update(
        'messages',
        {
          'elapsed_ms': value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND current_answer_version_id = ?',
        whereArgs: [messageId, answerVersionId],
      );
    });
  }

  /// 完成流式回答（设置最终状态和 token 统计）
  Future<void> completeStreamingAnswer({
    required String answerVersionId,
    required String messageId,
    required String finalContent,
    int? promptTokens,
    int? completionTokens,
    String? finishReason,
    String? reasoning,
    bool toolUsed = false,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();
    final contentHash = _computeHash(finalContent);

    // 更新回答版本为完成状态
    await db.update(
      'answer_versions',
      {
        'content': finalContent,
        'content_hash': contentHash,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'finish_reason': finishReason ?? 'stop',
        'reasoning': reasoning?.trim().isEmpty == true ? null : reasoning,
        'tool_used': toolUsed ? 1 : 0,
      },
      where: 'answer_version_id = ?',
      whereArgs: [answerVersionId],
    );

    // 同步更新消息镜像状态为已完成
    await db.update(
      'messages',
      {
        'content': finalContent,
        'content_hash': contentHash,
        'answer_status': 'completed',
        'reasoning': reasoning?.trim().isEmpty == true ? null : reasoning,
        'tool_used': toolUsed ? 1 : 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    if (finalContent.trim().isNotEmpty) {
      await db.insert('auto_journal_message_state', {
        'message_id': messageId,
        'eligibility': 'eligible',
        'reason': null,
        'settled_by': null,
        'settled_at': null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await _lifecycleHooks?.markMessageChanged(messageId);
  }

  /// Finalize a failed streaming answer and synchronize the message mirror.
  Future<void> failStreamingAnswer({
    required String answerVersionId,
    required String messageId,
    String? finalContent,
    Object? error,
    String? finishReason,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();
    final normalizedFinishReason = finishReason?.trim();
    final normalizedError = error?.toString().trim();
    final resolvedFinishReason = normalizedFinishReason?.isNotEmpty == true
        ? normalizedFinishReason!
        : normalizedError?.isNotEmpty == true
        ? normalizedError!
        : 'error';

    await db.transaction((txn) async {
      final rows = await txn.query(
        'answer_versions',
        columns: ['content'],
        where: 'answer_version_id = ? AND message_id = ?',
        whereArgs: [answerVersionId, messageId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Answer version not found: $answerVersionId');
      }

      final content = finalContent ?? rows.single['content'] as String;
      final contentHash = _computeHash(content);
      await txn.update(
        'answer_versions',
        {
          'content': content,
          'content_hash': contentHash,
          'finish_reason': resolvedFinishReason,
        },
        where: 'answer_version_id = ? AND message_id = ?',
        whereArgs: [answerVersionId, messageId],
      );
      await txn.update(
        'messages',
        {
          'content': content,
          'content_hash': contentHash,
          'answer_status': resolvedFinishReason.toLowerCase() == 'cancelled'
              ? 'cancelled'
              : 'failed',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    });
    await _lifecycleHooks?.markMessageChanged(messageId);
  }

  /// 创建回答版本（非流式，一次性完成）
  ///
  /// 注意：回答版本号独立递增（不与消息编辑版本号混用）
  /// 例如：创建→编辑→第一次回答 = answer_version_number 1（不是 3）
  Future<AnswerVersion> createAnswerVersion({
    required String messageId,
    required String content,
    String? modelServiceId,
    String? modelName,
    int? promptTokens,
    int? completionTokens,
    String? finishReason,
    String? reasoning,
    String? branchParentVersionId,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();
    final contentHash = _computeHash(content);

    // 读取当前回答版本数（独立计数，不用 revision）
    final messageRows = await db.query(
      'messages',
      columns: ['answer_version_count'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    if (messageRows.isEmpty) {
      throw StateError('消息不存在：$messageId');
    }

    final currentAnswerCount =
        messageRows.single['answer_version_count'] as int;

    // 新回答版本号 = 当前回答计数 + 1（独立递增）
    final newAnswerVersionNumber = currentAnswerCount + 1;

    final answerVersionId = StableIdFactory.answerVersionId();
    await db.transaction((txn) async {
      // 同一逻辑消息只允许一个当前回答版本，切换和插入必须原子完成。
      await txn.update(
        'answer_versions',
        {'branch_active': 0},
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      await txn.insert('answer_versions', {
        'answer_version_id': answerVersionId,
        'message_id': messageId,
        'version_number': newAnswerVersionNumber,
        'content': content,
        'content_hash': contentHash,
        'model_service_id': modelServiceId,
        'model_name': modelName,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'finish_reason': finishReason,
        'reasoning': reasoning?.trim().isEmpty == true ? null : reasoning,
        'branch_parent_version_id': branchParentVersionId,
        'branch_active': 1,
        'created_at': now,
      });
      await txn.update(
        'messages',
        {
          'content': content,
          'content_hash': contentHash,
          'current_answer_version_id': answerVersionId,
          'current_answer_version_number': newAnswerVersionNumber,
          'answer_version_count': newAnswerVersionNumber,
          'answer_status': 'completed',
          'reasoning': reasoning?.trim().isEmpty == true ? null : reasoning,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    });
    await _lifecycleHooks?.markMessageChanged(messageId);

    return AnswerVersion(
      answerVersionId: answerVersionId,
      messageId: messageId,
      versionNumber: newAnswerVersionNumber,
      content: content,
      contentHash: contentHash,
      modelServiceId: modelServiceId,
      modelName: modelName,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      finishReason: finishReason,
      reasoning: reasoning,
      branchParentVersionId: branchParentVersionId,
      branchActive: true,
      createdAt: now,
    );
  }

  /// 切换到指定的回答版本
  Future<void> switchToAnswerVersion({
    required String messageId,
    required String answerVersionId,
  }) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();

    // 读取目标版本
    final versionRows = await db.query(
      'answer_versions',
      where: 'answer_version_id = ? AND message_id = ?',
      whereArgs: [answerVersionId, messageId],
      limit: 1,
    );

    if (versionRows.isEmpty) {
      throw StateError('回答版本不存在：$answerVersionId');
    }

    final version = AnswerVersion.fromJson(versionRows.single);

    // 读取当前修订号与当前分支。
    final messageRows = await db.query(
      'messages',
      columns: ['revision', 'current_answer_version_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    final currentRevision = messageRows.single['revision'] as int;
    final currentAnswerVersionId =
        messageRows.single['current_answer_version_id'] as String?;
    if (currentAnswerVersionId == answerVersionId) return;

    await db.transaction((txn) async {
      if (currentAnswerVersionId != null) {
        await _captureCurrentBranch(
          txn,
          rootMessageId: messageId,
          answerVersionId: currentAnswerVersionId,
        );
      }
      await _hideDownstream(txn, rootMessageId: messageId);
      await _restoreBranch(
        txn,
        rootMessageId: messageId,
        answerVersionId: answerVersionId,
      );
      await txn.update(
        'answer_versions',
        {'branch_active': 0},
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      await txn.update(
        'answer_versions',
        {'branch_active': 1},
        where: 'answer_version_id = ?',
        whereArgs: [answerVersionId],
      );
      await txn.update(
        'messages',
        {
          'content': version.content,
          'content_hash': version.contentHash,
          'revision': currentRevision + 1,
          'current_answer_version_id': answerVersionId,
          'current_answer_version_number': version.versionNumber,
          'answer_status': _isCancelledAnswerVersion(version)
              ? 'cancelled'
              : _isFailedAnswerVersion(version)
              ? 'failed'
              : 'completed',
          'tool_used': version.toolUsed ? 1 : 0,
          'reasoning': version.reasoning,
          'elapsed_ms': version.elapsedMs,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    });
    await _markDownstreamChanged(messageId);
    await _lifecycleHooks?.markMessageChanged(messageId);
  }

  /// 软删除消息
  /// 已整理消息保持冻结；尚未整理消息重置所在区块的稳定时间。
  Future<void> deleteMessage(String messageId) async {
    final db = await _coreDatabase.open();
    final now = DateTime.now().toIso8601String();

    final messageRows = await db.query(
      'messages',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    if (messageRows.isEmpty) {
      throw StateError('消息不存在：$messageId');
    }

    // 软删除消息
    await db.update(
      'messages',
      {'is_deleted': 1, 'visible': 0, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    await _lifecycleHooks?.markMessageDeleted(messageId);
  }

  /// 查询消息的所有版本
  Future<List<MessageVersion>> getMessageVersions(String messageId) async {
    final db = await _coreDatabase.open();
    final rows = await db.query(
      'message_versions',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'version_number DESC',
    );

    return rows.map((row) => MessageVersion.fromJson(row)).toList();
  }

  /// 查询消息的所有回答版本
  Future<List<AnswerVersion>> getAnswerVersions(String messageId) async {
    final db = await _coreDatabase.open();
    final rows = await db.query(
      'answer_versions',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'version_number DESC',
    );

    return rows.map((row) => AnswerVersion.fromJson(row)).toList();
  }

  /// 查询活动分支的回答版本
  Future<List<AnswerVersion>> getActiveBranchAnswers(String messageId) async {
    final db = await _coreDatabase.open();
    final rows = await db.query(
      'answer_versions',
      where: 'message_id = ? AND branch_active = 1',
      whereArgs: [messageId],
      orderBy: 'version_number DESC',
    );

    return rows.map((row) => AnswerVersion.fromJson(row)).toList();
  }

  Future<void> _captureCurrentBranch(
    DatabaseExecutor database, {
    required String rootMessageId,
    required String answerVersionId,
  }) async {
    final ordered = await _orderedConversationMessages(
      database,
      rootMessageId: rootMessageId,
    );
    final rootIndex = ordered.indexWhere((row) => row['id'] == rootMessageId);
    if (rootIndex < 0) throw StateError('消息不存在：$rootMessageId');

    await database.delete(
      'chat_answer_branch_messages',
      where: 'root_message_id = ? AND answer_version_id = ?',
      whereArgs: [rootMessageId, answerVersionId],
    );
    for (final row in ordered.skip(rootIndex + 1)) {
      final visible = row['visible'] as int? ?? 1;
      final contextVisible = row['context_visible'] as int? ?? 0;
      if (row['is_deleted'] == 1 || (visible == 0 && contextVisible == 0)) {
        continue;
      }
      await database.insert('chat_answer_branch_messages', {
        'root_message_id': rootMessageId,
        'answer_version_id': answerVersionId,
        'downstream_message_id': row['id'],
        'visible': visible,
        'context_visible': contextVisible,
      });
    }

    await database.delete(
      'chat_answer_version_segments',
      where: 'answer_version_id = ?',
      whereArgs: [answerVersionId],
    );
    final segments = await database.query(
      'message_segments',
      where: 'message_id = ?',
      whereArgs: [rootMessageId],
      orderBy: 'segment_index ASC',
    );
    for (final segment in segments) {
      await database.insert('chat_answer_version_segments', {
        'answer_version_id': answerVersionId,
        'segment_index': segment['segment_index'],
        'content': segment['content'],
      });
    }
  }

  Future<void> _hideDownstream(
    DatabaseExecutor database, {
    required String rootMessageId,
  }) async {
    final ordered = await _orderedConversationMessages(
      database,
      rootMessageId: rootMessageId,
    );
    final rootIndex = ordered.indexWhere((row) => row['id'] == rootMessageId);
    if (rootIndex < 0) throw StateError('消息不存在：$rootMessageId');
    final ids = ordered
        .skip(rootIndex + 1)
        .where((row) => row['is_deleted'] != 1)
        .map((row) => row['id'] as String)
        .toList(growable: false);
    for (final id in ids) {
      await database.update(
        'messages',
        {'visible': 0, 'context_visible': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _restoreBranch(
    DatabaseExecutor database, {
    required String rootMessageId,
    required String answerVersionId,
  }) async {
    final rows = await database.query(
      'chat_answer_branch_messages',
      where: 'root_message_id = ? AND answer_version_id = ?',
      whereArgs: [rootMessageId, answerVersionId],
    );
    for (final row in rows) {
      await database.update(
        'messages',
        {'visible': row['visible'], 'context_visible': row['context_visible']},
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [row['downstream_message_id']],
      );
    }

    await database.delete(
      'message_segments',
      where: 'message_id = ?',
      whereArgs: [rootMessageId],
    );
    final segments = await database.query(
      'chat_answer_version_segments',
      where: 'answer_version_id = ?',
      whereArgs: [answerVersionId],
      orderBy: 'segment_index ASC',
    );
    for (final segment in segments) {
      await database.insert('message_segments', {
        'message_id': rootMessageId,
        'segment_index': segment['segment_index'],
        'content': segment['content'],
      });
    }
  }

  Future<List<Map<String, Object?>>> _orderedConversationMessages(
    DatabaseExecutor database, {
    required String rootMessageId,
  }) async {
    final roots = await database.query(
      'messages',
      columns: ['conversation_id'],
      where: 'id = ?',
      whereArgs: [rootMessageId],
      limit: 1,
    );
    if (roots.isEmpty) return const [];
    return database.query(
      'messages',
      columns: ['id', 'visible', 'context_visible', 'is_deleted'],
      where: 'conversation_id = ? AND import_pending_job_id IS NULL',
      whereArgs: [roots.single['conversation_id']],
      orderBy:
          'CASE WHEN import_order IS NULL THEN 1 ELSE 0 END ASC, '
          'import_order ASC, created_at ASC, id ASC',
    );
  }

  Future<void> _markDownstreamChanged(String rootMessageId) async {
    final database = await _coreDatabase.open();
    final ordered = await _orderedConversationMessages(
      database,
      rootMessageId: rootMessageId,
    );
    final rootIndex = ordered.indexWhere((row) => row['id'] == rootMessageId);
    if (rootIndex < 0) return;
    for (final row in ordered.skip(rootIndex + 1)) {
      if (row['is_deleted'] == 1) continue;
      final messageId = row['id'] as String;
      await _lifecycleHooks?.markMessageChanged(messageId);
    }
  }
}
