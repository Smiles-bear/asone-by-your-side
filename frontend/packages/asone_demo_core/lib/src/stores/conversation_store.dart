import 'package:asone_contracts/asone_contracts.dart';

import '../demo_ids.dart';

/// In-memory [ConversationRepositoryApi] implementation.
class DemoConversationStore implements ConversationRepositoryApi {
  DemoConversationStore({List<Map<String, dynamic>>? seed})
    : _rows = [...?seed];

  final List<Map<String, dynamic>> _rows;

  Map<String, dynamic>? _rowById(String id) {
    for (final row in _rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  @override
  Future<List<Conversation>> getConversations() async {
    final list = _rows.map(Conversation.fromJson).toList();
    list.sort((a, b) {
      final pinnedOrder = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
      if (pinnedOrder != 0) return pinnedOrder;
      final pinnedAtOrder = (b.pinnedAt ?? DateTime(0)).compareTo(
        a.pinnedAt ?? DateTime(0),
      );
      if (pinnedAtOrder != 0) return pinnedAtOrder;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  @override
  Future<Conversation?> getConversation(String conversationId) async {
    final row = _rowById(conversationId);
    return row == null ? null : Conversation.fromJson(row);
  }

  @override
  Future<String> getConversationDraft(String conversationId) async =>
      _rowById(conversationId)?['draft_text'] as String? ?? '';

  @override
  Future<void> saveConversationDraft(String conversationId, String text) async {
    final row = _rowById(conversationId);
    if (row == null) return;
    row['draft_text'] = text;
    row['draft_updated_at'] = demoNowIso();
    row['updated_at'] = demoNowIso();
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    final row = _rowById(conversationId);
    if (row == null) return;
    row['unread_count'] = 0;
    row['updated_at'] = demoNowIso();
  }

  @override
  Future<Conversation> createConversation(
    String title, {
    required String assistantId,
  }) async {
    final now = demoNowIso();
    final conversation = Conversation(
      id: demoId('conversation'),
      title: title,
      assistantId: assistantId,
      createdAt: demoNow().toUtc(),
      updatedAt: demoNow().toUtc(),
    );
    _rows.add({...conversation.toJson(), 'created_at': now, 'updated_at': now});
    return conversation;
  }

  @override
  Future<Conversation> updateConversation(
    String id, {
    String? title,
    String? assistantId,
  }) async {
    final row = _rowById(id);
    if (row == null) {
      throw StateError('对话不存在');
    }
    if (title != null) row['title'] = title;
    if (assistantId != null) row['assistant_id'] = assistantId;
    row['updated_at'] = demoNowIso();
    return Conversation.fromJson(row);
  }

  @override
  Future<Conversation> setConversationPinned(
    String id, {
    required bool pinned,
  }) async {
    final row = _rowById(id);
    if (row == null) throw StateError('对话不存在');
    row['pinned_at'] = pinned ? demoNowIso() : null;
    return Conversation.fromJson(row);
  }

  @override
  Future<void> deleteConversation(String id) async {
    _rows.removeWhere((row) => row['id'] == id);
  }

  /// Demo-internal: drop conversations owned by a deleted assistant.
  void deleteByAssistant(String assistantId) {
    _rows.removeWhere((row) => row['assistant_id'] == assistantId);
  }

  /// Demo-internal: first conversation bound to the assistant, if any.
  Map<String, dynamic>? primaryRowOf(String assistantId) {
    for (final row in _rows) {
      if (row['assistant_id'] == assistantId) return row;
    }
    return null;
  }
}
