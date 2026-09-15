import 'package:asone_contracts/asone_contracts.dart';
import 'local_core/core_database.dart';
import 'local_core/stable_id_factory.dart';
import 'services/provider_adapters/adapter_registry.dart';
import 'services/provider_adapters/protocol_client.dart';

class CommunityDiaryEntry {
  const CommunityDiaryEntry({
    required this.diaryId,
    required this.conversationId,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final String diaryId;
  final String conversationId;
  final String title;
  final String content;
  final DateTime createdAt;

  factory CommunityDiaryEntry.fromRow(Map<String, Object?> row) =>
      CommunityDiaryEntry(
        diaryId: row['diary_id']! as String,
        conversationId: row['conversation_id']! as String,
        title: row['title']! as String,
        content: row['content']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
      );
}

typedef CommunityDiaryGenerator =
    Future<Map<String, String>> Function({
      required ModelService service,
      required List<Map<String, Object?>> messages,
    });

/// 社区版降级日记：只根据当前单聊最近的基础文本生成。
///
/// 本服务不读取或写入记忆、关系状态、心跳和后台任务相关数据。
class CommunityDiaryService {
  CommunityDiaryService({
    required CoreDatabase database,
    required ModelServiceRepositoryApi modelServices,
    ProtocolClient? client,
  }) : _database = database,
       _modelServices = modelServices,
       _client = client ?? ProtocolClient();

  final CoreDatabase _database;
  final ModelServiceRepositoryApi _modelServices;
  final ProtocolClient _client;

  Future<List<CommunityDiaryEntry>> listForConversation(
    String conversationId,
  ) async {
    final database = await _database.open();
    final rows = await database.query(
      'diary_entries',
      columns: [
        'diary_id',
        'conversation_id',
        'title',
        'content',
        'created_at',
      ],
      where:
          "conversation_id = ? AND source = 'community_recent' AND status = 'active'",
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
    );
    return rows.map(CommunityDiaryEntry.fromRow).toList(growable: false);
  }

  Future<CommunityDiaryEntry> generate({
    required String conversationId,
    CommunityDiaryGenerator? generator,
  }) async {
    final database = await _database.open();
    final conversations = await database.query(
      'conversations',
      columns: ['assistant_id'],
      where: 'id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (conversations.isEmpty) throw StateError('对话不存在');
    final assistantId = conversations.single['assistant_id']! as String;
    final assistants = await database.query(
      'assistants',
      columns: ['model_service_id'],
      where: 'id = ?',
      whereArgs: [assistantId],
      limit: 1,
    );
    const legacyPrefix = 'community-api:';
    final serviceId = assistants.isNotEmpty
        ? assistants.single['model_service_id']! as String
        : assistantId.startsWith(legacyPrefix)
        ? assistantId.substring(legacyPrefix.length)
        : '';
    if (serviceId.isEmpty) throw StateError('该对话未绑定社区模型服务');
    final service = await _serviceById(serviceId);
    final messages = await _recentMessages(conversationId);
    if (messages.isEmpty) throw StateError('至少需要一条基础文本消息才能生成日记');
    final generated = await (generator ?? _requestDiary)(
      service: service,
      messages: messages,
    );
    final title = (generated['title'] ?? '').trim();
    final content = (generated['content'] ?? '').trim();
    if (content.isEmpty) throw StateError('模型未返回日记内容');

    final now = DateTime.now().toUtc().toIso8601String();
    final diaryId = StableIdFactory.generate('diary');
    final runId = StableIdFactory.generate('diary_run');
    await database.transaction((transaction) async {
      await transaction.insert('diary_entries', {
        'diary_id': diaryId,
        'assistant_id': assistantId,
        'conversation_id': conversationId,
        'title': title.isEmpty ? '对话日记' : title,
        'content': content,
        'mood': null,
        'tags': null,
        'source': 'community_recent',
        'status': 'active',
        'is_read': 0,
        'prompt_tokens': 0,
        'completion_tokens': 0,
        'total_tokens': 0,
        'created_at': now,
        'updated_at': now,
      });
      await transaction.insert('diary_runs', {
        'run_id': runId,
        'assistant_id': assistantId,
        'conversation_id': conversationId,
        'run_type': 'manual',
        'decision': 'executed',
        'reason': 'community recent conversation only',
        'candidate_count': messages.length,
        'source_hash': null,
        'diary_id': diaryId,
        'error_message': null,
        'created_at': now,
      });
    });
    return CommunityDiaryEntry(
      diaryId: diaryId,
      conversationId: conversationId,
      title: title.isEmpty ? '对话日记' : title,
      content: content,
      createdAt: DateTime.parse(now),
    );
  }

  Future<List<Map<String, Object?>>> _recentMessages(
    String conversationId,
  ) async {
    final database = await _database.open();
    final rows = await database.query(
      'messages',
      columns: ['id', 'role', 'content', 'created_at'],
      where:
          "conversation_id = ? AND is_deleted = 0 AND role IN ('user', 'assistant') AND TRIM(content) <> ''",
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: 50,
    );
    return rows.reversed
        .map(
          (row) => <String, Object?>{
            'id': row['id'],
            'role': row['role'],
            'content': row['content'],
            'created_at': row['created_at'],
          },
        )
        .toList(growable: false);
  }

  Future<ModelService> _serviceById(String id) async {
    final services = await _modelServices.getModelServices();
    final matches = services.where((service) => service.id == id);
    if (matches.isEmpty) throw StateError('模型服务不存在');
    return matches.first;
  }

  Future<Map<String, String>> _requestDiary({
    required ModelService service,
    required List<Map<String, Object?>> messages,
  }) async {
    final protocol = service.protocolType == ProtocolType.auto
        ? await _resolveProtocol(service)
        : service.protocolType;
    final result = await _client.streamText(
      adapter: AdapterRegistry.instance.get(protocol),
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      messages: [
        const <String, Object?>{
          'role': 'system',
          'content': '请只根据以下近期对话写一篇简短日记。第一行是标题，空一行后是正文。不要补充长期记忆或未提供的事实。',
        },
        ...messages.map(
          (message) => <String, Object?>{
            'role': message['role'],
            'content': message['content'],
          },
        ),
      ],
      maxTokens: 1600,
      temperature: 0.7,
      onDelta: (_) {},
    );
    final text = result.text.trim();
    if (!result.success || text.isEmpty) {
      throw StateError(
        result.diagnosis.detail.isEmpty ? '模型未返回日记内容' : result.diagnosis.detail,
      );
    }
    final lines = text.split('\n');
    final title = lines.first.trim();
    final content = lines.skip(1).join('\n').trim();
    return {'title': title, 'content': content.isEmpty ? text : content};
  }

  Future<String> _resolveProtocol(ModelService service) async {
    final resolution = await _client.resolveProtocol(
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
    );
    if (!resolution.success) throw StateError(resolution.diagnosis.detail);
    await _modelServices.persistDetectedModelProtocol(
      service.id,
      resolution.protocol,
    );
    return resolution.protocol;
  }
}
