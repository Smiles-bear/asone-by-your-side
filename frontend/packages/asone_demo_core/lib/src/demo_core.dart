import 'package:asone_contracts/asone_contracts.dart';

import 'read_state.dart';
import 'seed_data.dart';
import 'stores/assistant_store.dart';
import 'stores/board_store.dart';
import 'stores/calendar_store.dart';
import 'stores/conversation_store.dart';
import 'stores/feature_unread_store.dart';
import 'stores/model_service_store.dart';
import 'stores/sticky_note_store.dart';
import 'stores/token_usage_store.dart';

/// In-memory [OpenCore] implementation for Community/Demo editions.
///
/// 用法：启动时执行 `OpenCoreBinding.attach(DemoCore.withDemoSeed())`，
/// 已迁移到公开接口的页面即可运行在演示数据上。
class DemoCore implements OpenCore {
  factory DemoCore({DemoSeedData? seed}) {
    final data = seed ?? DemoSeedData.empty();
    final readState = DemoReadState();
    final conversations = DemoConversationStore(seed: data.conversations);
    final assistants = DemoAssistantStore(
      conversations: conversations,
      seed: data.assistants,
    );
    final modelServices = DemoModelServiceStore(
      assistants: assistants,
      seed: data.modelServices,
    );
    final board = DemoBoardStore(
      readState: readState,
      posts: data.boardPosts,
      comments: data.boardComments,
      assistantLikes: data.boardAssistantLikes,
      userLikedPosts: data.boardUserLikedPosts,
    );
    final stickyNotes = DemoStickyNoteStore(
      readState: readState,
      notes: data.stickyNotes,
      items: data.stickyNoteItems,
    );
    final calendar = DemoCalendarStore(
      readState: readState,
      events: data.calendarEvents,
    );
    final featureUnread = DemoFeatureUnreadStore(
      readState: readState,
      board: board,
      stickyNotes: stickyNotes,
      calendar: calendar,
    );
    final tokenUsage = DemoTokenUsageStore(seed: data.tokenRecords);
    return DemoCore._(
      assistants: assistants,
      conversations: conversations,
      modelServices: modelServices,
      calendar: calendar,
      stickyNotes: stickyNotes,
      messageBoard: board,
      featureUnread: featureUnread,
      tokenUsage: tokenUsage,
    );
  }

  /// Builds a core pre-filled with the standard Chinese demo dataset.
  factory DemoCore.withDemoSeed() => DemoCore(seed: DemoSeedData.standard());

  DemoCore._({
    required DemoAssistantStore assistants,
    required DemoConversationStore conversations,
    required DemoModelServiceStore modelServices,
    required DemoCalendarStore calendar,
    required DemoStickyNoteStore stickyNotes,
    required DemoBoardStore messageBoard,
    required DemoFeatureUnreadStore featureUnread,
    required DemoTokenUsageStore tokenUsage,
  }) : _assistants = assistants,
       _conversations = conversations,
       _modelServices = modelServices,
       _calendar = calendar,
       _stickyNotes = stickyNotes,
       _messageBoard = messageBoard,
       _featureUnread = featureUnread,
       _tokenUsage = tokenUsage;

  final DemoAssistantStore _assistants;
  final DemoConversationStore _conversations;
  final DemoModelServiceStore _modelServices;
  final DemoCalendarStore _calendar;
  final DemoStickyNoteStore _stickyNotes;
  final DemoBoardStore _messageBoard;
  final DemoFeatureUnreadStore _featureUnread;
  final DemoTokenUsageStore _tokenUsage;

  @override
  AssistantRepositoryApi get assistants => _assistants;

  @override
  ConversationRepositoryApi get conversations => _conversations;

  @override
  ModelServiceRepositoryApi get modelServices => _modelServices;

  @override
  CalendarRepositoryApi get calendar => _calendar;

  @override
  StickyNoteRepositoryApi get stickyNotes => _stickyNotes;

  @override
  MessageBoardRepositoryApi get messageBoard => _messageBoard;

  @override
  FeatureUnreadApi get featureUnread => _featureUnread;

  @override
  TokenUsageApi get tokenUsage => _tokenUsage;
}
