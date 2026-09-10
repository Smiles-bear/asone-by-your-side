import '../models/conversation.dart';

/// Public data-access contract for conversation metadata.
abstract interface class ConversationRepositoryApi {
  Future<List<Conversation>> getConversations();

  Future<Conversation?> getConversation(String conversationId);

  Future<String> getConversationDraft(String conversationId);

  Future<void> saveConversationDraft(String conversationId, String text);

  Future<void> markConversationRead(String conversationId);

  Future<Conversation> createConversation(
    String title, {
    required String assistantId,
  });

  Future<Conversation> updateConversation(
    String id, {
    String? title,
    String? assistantId,
  });

  Future<void> deleteConversation(String id);
}
