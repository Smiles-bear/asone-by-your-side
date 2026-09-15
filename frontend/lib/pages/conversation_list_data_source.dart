import '../models/assistant.dart';
import '../models/conversation.dart';
import '../local_core/group_chat/group_models.dart';

/// 会话列表所需的最小公开数据面。
///
/// 页面不再依赖聚合型 ApiService；私有版与社区版都由已挂载的 OpenCore
/// 提供助手和单聊仓储。群聊数据面在 R5 以独立能力注入。
abstract interface class ConversationListDataSource {
  Future<List<Assistant>> getAssistants();

  Future<List<Conversation>> getConversations();

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

/// 会话列表展示群聊所需的最小公开数据面。
abstract interface class ConversationListGroupDataSource {
  Future<List<GroupRoom>> listRooms();

  Future<List<GroupParticipant>> getParticipants(String roomId);

  Future<int> unreadCount(String roomId);
}

/// 默认桥接到当前版本装配的公开核心。
class OpenCoreConversationListDataSource implements ConversationListDataSource {
  OpenCoreConversationListDataSource({
    AssistantRepositoryApi? assistants,
    ConversationRepositoryApi? conversations,
  }) : _assistants = assistants ?? OpenCoreBinding.instance.assistants,
       _conversations = conversations ?? OpenCoreBinding.instance.conversations;

  final AssistantRepositoryApi _assistants;
  final ConversationRepositoryApi _conversations;

  @override
  Future<List<Assistant>> getAssistants() => _assistants.getAssistants();

  @override
  Future<List<Conversation>> getConversations() =>
      _conversations.getConversations();

  @override
  Future<Conversation> createConversation(
    String title, {
    required String assistantId,
  }) => _conversations.createConversation(title, assistantId: assistantId);

  @override
  Future<Conversation> updateConversation(
    String id, {
    String? title,
    String? assistantId,
  }) => _conversations.updateConversation(
    id,
    title: title,
    assistantId: assistantId,
  );

  @override
  Future<void> deleteConversation(String id) =>
      _conversations.deleteConversation(id);
}
