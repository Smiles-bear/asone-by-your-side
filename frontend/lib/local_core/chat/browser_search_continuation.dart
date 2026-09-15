import 'dart:convert';

import '../../tool_runtime/sources/browser_tool_ids.dart';
import '../core_database.dart';

class BrowserSearchContinuation {
  const BrowserSearchContinuation({required this.topic, this.query});

  final String topic;
  final String? query;
}

class BrowserSearchContinuationResolver {
  BrowserSearchContinuationResolver({required CoreDatabase coreDatabase})
    : _coreDatabase = coreDatabase;

  final CoreDatabase _coreDatabase;

  Future<BrowserSearchContinuation?> resolve({
    required String assistantId,
    required String conversationId,
    required String currentText,
    String? currentMessageId,
  }) async {
    if (!BrowserToolIds.matchesContinuationIntent(currentText)) return null;
    final database = await _coreDatabase.open();
    final conversations = await database.query(
      'conversations',
      columns: ['assistant_id'],
      where: 'id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (!_belongsToAssistant(conversations, assistantId)) {
      return null;
    }

    final previous = await database.query(
      'messages',
      columns: ['id', 'role', 'content', 'answer_status', 'tool_used'],
      where:
          'conversation_id = ? AND is_deleted = 0 '
          '${currentMessageId == null ? '' : 'AND id != ? '}',
      whereArgs: [
        conversationId,
        if (currentMessageId != null) currentMessageId,
      ],
      orderBy: 'created_at DESC',
      limit: 4,
    );
    final assistantIndex = previous.indexWhere(
      (row) => row['role'] == 'assistant',
    );
    if (assistantIndex < 0 || previous[assistantIndex]['tool_used'] != 1) {
      return null;
    }
    final assistant = previous[assistantIndex];
    final priorUser = previous
        .skip(assistantIndex + 1)
        .where((row) => row['role'] == 'user')
        .firstOrNull;
    final topic = priorUser?['content']?.toString().trim() ?? '';
    if (topic.isEmpty) return null;

    final auditRows = await database.query(
      'tool_call_runs',
      columns: ['status', 'error_code', 'input_summary'],
      where:
          'assistant_id = ? AND conversation_id = ? '
          'AND tool_id IN (?, ?)',
      whereArgs: [
        assistantId,
        conversationId,
        BrowserToolIds.searchWeb,
        BrowserToolIds.readPage,
      ],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    final failedMessage = _isFailedMessage(assistant);
    if (auditRows.isEmpty) {
      return failedMessage ? BrowserSearchContinuation(topic: topic) : null;
    }
    final audit = auditRows.single;
    final auditSummary = _summaryFromJson(audit['input_summary']?.toString());
    if (!_auditMatchesMessage(auditSummary, assistant['id'])) {
      return null;
    }
    final failedAudit =
        audit['status'] != 'success' || audit['error_code'] != null;
    if (!failedAudit && !failedMessage) return null;
    return BrowserSearchContinuation(
      topic: topic,
      query: _queryFromSummary(auditSummary),
    );
  }

  bool _belongsToAssistant(
    List<Map<String, Object?>> conversations,
    String assistantId,
  ) =>
      conversations.isNotEmpty &&
      conversations.single['assistant_id'] == assistantId;

  bool _isFailedMessage(Map<String, Object?> assistant) {
    final answerStatus = assistant['answer_status']?.toString();
    final content = assistant['content']?.toString() ?? '';
    return answerStatus == 'failed' ||
        answerStatus == 'cancelled' ||
        content.contains('网页搜索未完成') ||
        content.contains('网页搜索已中断');
  }

  bool _auditMatchesMessage(
    Map<String, dynamic>? auditSummary,
    Object? assistantMessageId,
  ) {
    final auditedMessageId = auditSummary?['assistant_message_id']
        ?.toString()
        .trim();
    return auditedMessageId?.isNotEmpty != true ||
        auditedMessageId == assistantMessageId;
  }

  Map<String, dynamic>? _summaryFromJson(String? summary) {
    if (summary == null || summary.isEmpty) return null;
    try {
      final decoded = jsonDecode(summary);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  String? _queryFromSummary(Map<String, dynamic>? summary) {
    final value = summary?['query']?.toString().trim();
    return value?.isNotEmpty == true ? value : null;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
