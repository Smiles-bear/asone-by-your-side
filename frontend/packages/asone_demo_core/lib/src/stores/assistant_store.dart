import 'package:asone_contracts/asone_contracts.dart';

import '../demo_ids.dart';
import 'conversation_store.dart';

/// In-memory [AssistantRepositoryApi] implementation.
class DemoAssistantStore implements AssistantRepositoryApi {
  DemoAssistantStore({
    required DemoConversationStore conversations,
    List<Map<String, dynamic>>? seed,
  }) : _conversations = conversations,
       _rows = [...?seed];

  final DemoConversationStore _conversations;
  final List<Map<String, dynamic>> _rows;

  Map<String, dynamic>? _rowById(String id) {
    for (final row in _rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  @override
  Future<List<Assistant>> getAssistants() async =>
      _rows.map(Assistant.fromJson).toList();

  @override
  Future<Assistant?> getAssistant(String assistantId) async {
    final row = _rowById(assistantId);
    return row == null ? null : Assistant.fromJson(row);
  }

  @override
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
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('请填写助手名称');
    }
    final now = DateTime.now().toUtc();
    final assistant = Assistant(
      id: demoId('assistant'),
      name: trimmed,
      avatar: '',
      mainModel: mainModel,
      assistantModel: assistantModel,
      voice: voice,
      systemPrompt: systemPrompt,
      modelServiceId: modelServiceId,
      memoryExpressionStyle: memoryExpressionStyle,
      memoryExpressionCustom: memoryExpressionCustom,
      memoryAutoOrganizeEnabled: memoryAutoOrganizeEnabled,
      diaryWriter: diaryWriter,
      diarySubject: diarySubject,
      createdAt: now,
      updatedAt: now,
    );
    _rows.add(assistant.toJson());
    return assistant;
  }

  @override
  Future<Assistant> updateAssistant(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final row = _rowById(id);
    if (row == null) {
      throw StateError('助手不存在');
    }
    row.addAll({...fields, 'id': id, 'updated_at': demoNowIso()});
    return Assistant.fromJson(row);
  }

  @override
  Future<void> deleteAssistant(String id) async {
    _rows.removeWhere((row) => row['id'] == id);
    _conversations.deleteByAssistant(id);
  }

  @override
  Future<String> getUserProfile(String assistantId) async =>
      _rowById(assistantId)?['user_profile'] as String? ?? '';

  @override
  Future<void> updateUserProfile(
    String assistantId, {
    required String userProfile,
  }) async {
    final row = _rowById(assistantId);
    if (row == null) return;
    row['user_profile'] = userProfile;
    row['updated_at'] = demoNowIso();
  }

  @override
  Future<AssistantWithConversation> createAssistantWithPrimaryConversation({
    required String name,
    String avatar = '',
    String systemPrompt = '',
    String voice = '',
    String diaryWriter = '助手',
    String diarySubject = '用户',
    String? primaryModelServiceId,
  }) async {
    final assistant = await createAssistant(
      name: name,
      voice: voice,
      systemPrompt: systemPrompt,
      modelServiceId: primaryModelServiceId ?? '',
      diaryWriter: diaryWriter,
      diarySubject: diarySubject,
    );
    if (avatar.isNotEmpty) {
      await updateAssistant(assistant.id, {'avatar': avatar});
    }
    final conversation = await _conversations.createConversation(
      name.trim(),
      assistantId: assistant.id,
    );
    final row = _rowById(assistant.id);
    return AssistantWithConversation(
      assistant: row == null ? assistant : Assistant.fromJson(row),
      conversation: conversation,
    );
  }

  @override
  Future<Conversation> getOrCreatePrimaryConversation(
    String assistantId,
  ) async {
    final existing = _conversations.primaryRowOf(assistantId);
    if (existing != null) return Conversation.fromJson(existing);
    final assistant = _rowById(assistantId);
    return _conversations.createConversation(
      assistant?['name'] as String? ?? '对话',
      assistantId: assistantId,
    );
  }

  /// Demo-internal: names of assistants referencing the given model service.
  List<String> assistantNamesUsingModelService(String serviceId) => _rows
      .where(
        (row) =>
            row['model_service_id'] == serviceId ||
            row['assistant_model_service_id'] == serviceId,
      )
      .map((row) => row['name'] as String? ?? '')
      .toList();
}
