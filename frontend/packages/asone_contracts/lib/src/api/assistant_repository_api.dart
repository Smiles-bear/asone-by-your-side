import '../models/assistant.dart';
import '../models/assistant_with_conversation.dart';
import '../models/conversation.dart';

/// Public data-access contract for assistant records.
abstract interface class AssistantRepositoryApi {
  Future<List<Assistant>> getAssistants();

  Future<Assistant?> getAssistant(String assistantId);

  Future<Assistant> createAssistant({
    required String name,
    String mainModel = '',
    String assistantModel = '',
    String voice = '',
    String systemPrompt = '',
    String modelServiceId = '',
    String memoryExpressionStyle = 'natural',
    String memoryExpressionCustom = '',
    bool memoryAutoOrganizeEnabled = true,
    String diaryWriter = '助手',
    String diarySubject = '用户',
  });

  Future<Assistant> updateAssistant(String id, Map<String, dynamic> fields);

  Future<void> deleteAssistant(String id);

  Future<String> getUserProfile(String assistantId);

  Future<void> updateUserProfile(
    String assistantId, {
    required String userProfile,
  });

  Future<AssistantWithConversation> createAssistantWithPrimaryConversation({
    required String name,
    String avatar = '',
    String systemPrompt = '',
    String voice = '',
    String diaryWriter = '助手',
    String diarySubject = '用户',
    String? primaryModelServiceId,
  });

  Future<Conversation> getOrCreatePrimaryConversation(String assistantId);
}
