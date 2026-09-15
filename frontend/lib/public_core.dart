import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:dio/dio.dart';
import 'local_core/core_database.dart';
import 'local_core/core_repository.dart';
import 'local_core/chat/local_chat_service.dart';
import 'local_core/feature_unread_service.dart';
import 'local_core/group_chat/group_message_repository.dart';
import 'local_core/group_chat/group_room_repository.dart';
import 'local_core/import/import_service.dart';
import 'local_core/message_contract_facade.dart';
import 'local_core/token_usage_service.dart';
import 'services/model_discovery_service.dart';

import 'community_open_core.dart';
import 'community_chat_context_compiler.dart';
import 'community_group_context_builder.dart';
import 'community_group_round_engine.dart';
import 'community_group_service.dart';
import 'community_diary_service.dart';

/// 社区版真实本地核心。
///
/// 助手、会话、消息、模型服务、未读和用量写入 SQLite；尚未迁移的公开
/// 功能域临时由 [DemoCore] 承担，后续批次逐步替换。
class PublicCore implements OpenCore {
  PublicCore({CoreDatabase? database, DemoCore? fallback, Dio? chatDio})
    : database = database ?? CoreDatabase.instance,
      _fallback = fallback ?? DemoCore.withDemoSeed() {
    repository = CoreRepository(coreDatabase: this.database);
    chatContext = CommunityChatContextCompiler(repository: repository);
    chat = LocalChatService(
      coreDatabase: this.database,
      coreRepository: repository,
      contextCompiler: chatContext,
      dio: chatDio,
    );
    messages = MessageContractFacade(repository);
    groupRooms = GroupRoomRepository(coreDatabase: this.database);
    groupMessages = GroupMessageRepository(
      coreDatabase: this.database,
      roomRepository: groupRooms,
    );
    groupContext = CommunityGroupContextBuilder(
      chatContext: chatContext,
      rooms: groupRooms,
      messages: groupMessages,
    );
    groupRoundEngine = CommunityGroupRoundEngine(
      database: this.database,
      chat: chat,
      contextBuilder: groupContext,
      rooms: groupRooms,
      messages: groupMessages,
    );
    groupChat = CommunityGroupService(
      assistants: repository,
      modelServices: repository,
      rooms: groupRooms,
      messages: groupMessages,
      roundEngine: groupRoundEngine,
    );
    imports = ImportService(coreDatabase: this.database);
    diary = CommunityDiaryService(
      database: this.database,
      modelServices: repository,
    );
    featureUnread = FeatureUnreadService(coreDatabase: this.database);
    tokenUsage = TokenUsageService(coreDatabase: this.database);
    capabilityDetection = CommunityCapabilityDetection(
      modelServices: repository,
    );
  }

  final CoreDatabase database;
  final DemoCore _fallback;
  late final CoreRepository repository;
  late final CommunityChatContextCompiler chatContext;
  late final LocalChatService chat;
  @override
  late final MessageContractFacade messages;
  late final GroupRoomRepository groupRooms;
  late final GroupMessageRepository groupMessages;
  late final CommunityGroupContextBuilder groupContext;
  late final CommunityGroupRoundEngine groupRoundEngine;
  late final CommunityGroupService groupChat;

  /// 导入完成后不触发记忆重建等私有副作用。
  late final ImportService imports;
  late final CommunityDiaryService diary;
  @override
  late final FeatureUnreadService featureUnread;
  @override
  late final TokenUsageService tokenUsage;
  @override
  late final CommunityCapabilityDetection capabilityDetection;
  final ModelDiscoveryService _modelDiscovery = ModelDiscoveryService();

  Future<void> open() async {
    await database.open();
    await featureUnread.refresh();
  }

  /// 为用户配置的模型服务建立可被 SQLite 会话和群聊引用的本地助手。
  Future<Assistant> ensureAssistantForService(ModelService service) async {
    final assistants = await repository.getAssistants();
    final existing = assistants.where(
      (assistant) => assistant.modelServiceId == service.id,
    );
    if (existing.isNotEmpty) return existing.first;
    return repository.createAssistant(
      name: service.name,
      mainModel: service.model,
      modelServiceId: service.id,
      memoryAutoOrganizeEnabled: false,
    );
  }

  @override
  AssistantRepositoryApi get assistants => repository;
  @override
  ConversationRepositoryApi get conversations => repository;
  @override
  ModelServiceRepositoryApi get modelServices => repository;
  @override
  ModelDiscoveryApi get modelDiscovery => _modelDiscovery;
  @override
  CalendarRepositoryApi get calendar => _fallback.calendar;
  @override
  StickyNoteRepositoryApi get stickyNotes => _fallback.stickyNotes;
  @override
  MessageBoardRepositoryApi get messageBoard => _fallback.messageBoard;
}
