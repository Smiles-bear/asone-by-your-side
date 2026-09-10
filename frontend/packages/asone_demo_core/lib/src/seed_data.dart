import 'package:asone_contracts/asone_contracts.dart';

/// Seed rows for a fresh `DemoCore`.
///
/// 所有演示数据均为虚构中文文案，不包含任何真实用户数据；
/// 模型服务使用 example.invalid 占位地址与假 API Key。
class DemoSeedData {
  const DemoSeedData({
    this.assistants = const [],
    this.conversations = const [],
    this.modelServices = const [],
    this.boardPosts = const [],
    this.boardComments = const [],
    this.boardAssistantLikes = const {},
    this.boardUserLikedPosts = const [],
    this.stickyNotes = const [],
    this.stickyNoteItems = const [],
    this.calendarEvents = const [],
    this.tokenRecords = const [],
  });

  final List<Map<String, dynamic>> assistants;
  final List<Map<String, dynamic>> conversations;
  final List<Map<String, dynamic>> modelServices;
  final List<Map<String, dynamic>> boardPosts;
  final List<Map<String, dynamic>> boardComments;
  final Map<String, List<String>> boardAssistantLikes;
  final List<String> boardUserLikedPosts;
  final List<Map<String, dynamic>> stickyNotes;
  final List<Map<String, dynamic>> stickyNoteItems;
  final List<Map<String, dynamic>> calendarEvents;
  final List<Map<String, dynamic>> tokenRecords;

  static DemoSeedData empty() => const DemoSeedData();

  static Map<String, dynamic> tokenRow({
    required String recordId,
    required String assistantId,
    String taskType = 'chat',
    required int input,
    required int output,
    required DateTime createdAt,
    String model = 'demo-model',
    bool estimated = false,
    int requestCount = 1,
  }) => {
    'record_id': recordId,
    'assistant_id': assistantId,
    'task_type': taskType,
    'task_subtype': null,
    'input_tokens': input,
    'output_tokens': output,
    'total_tokens': input + output,
    'request_count': requestCount,
    'model_service_id': 'demo-service',
    'model': model,
    'protocol_type': 'openai',
    'is_estimated': estimated ? 1 : 0,
    'request_id': null,
    'conversation_id': 'demo-conversation-xiaoru',
    'message_id': null,
    'job_id': null,
    'created_at': createdAt.toIso8601String(),
  };

  static DemoSeedData standard() {
    final now = DateTime.now();
    DateTime ago(Duration duration) => now.subtract(duration);

    const xiaoruId = 'demo-assistant-xiaoru';
    const alanId = 'demo-assistant-alan';

    final xiaoru = Assistant(
      id: xiaoruId,
      name: '小如',
      avatar: '',
      mainModel: 'demo-model',
      assistantModel: '',
      voice: '',
      systemPrompt: '演示助手：温柔耐心，喜欢用简短的句子交流。',
      modelServiceId: 'demo-service',
      createdAt: ago(const Duration(days: 30)),
      updatedAt: ago(const Duration(days: 2)),
    );
    final alan = Assistant(
      id: alanId,
      name: '阿澜',
      avatar: '',
      mainModel: 'demo-model',
      assistantModel: '',
      voice: '',
      systemPrompt: '演示助手：理性直接，擅长整理待办与日程。',
      modelServiceId: 'demo-service',
      createdAt: ago(const Duration(days: 12)),
      updatedAt: ago(const Duration(days: 12)),
    );

    final conversations = [
      Conversation(
        id: 'demo-conversation-xiaoru',
        title: '小如',
        assistantId: xiaoruId,
        createdAt: ago(const Duration(days: 30)),
        updatedAt: ago(const Duration(days: 30)),
      ),
      Conversation(
        id: 'demo-conversation-alan',
        title: '阿澜',
        assistantId: alanId,
        createdAt: ago(const Duration(days: 12)),
        updatedAt: ago(const Duration(days: 12)),
      ),
    ];

    final modelService = ModelService(
      id: 'demo-service',
      name: '演示模型服务',
      baseUrl: 'https://api.example.invalid/v1',
      apiKey: 'demo-key-not-real',
      model: 'demo-model',
      protocolType: 'openai',
      status: 'untested',
      createdAt: ago(const Duration(days: 30)),
      updatedAt: ago(const Duration(days: 30)),
    );

    final boardPosts = [
      BoardPostItem(
        postId: 'demo-post-welcome',
        content: '欢迎使用留言板！这里是演示数据，可以随意发帖和评论。',
        authorType: 'user',
        createdAt: ago(const Duration(hours: 5)),
      ).toJson(),
      BoardPostItem(
        postId: 'demo-post-xiaoru',
        content: '今天也要好好吃饭、好好休息呀。',
        authorType: 'assistant',
        authorAssistantId: xiaoruId,
        createdAt: ago(const Duration(minutes: 40)),
      ).toJson(),
    ];
    final boardComments = [
      BoardCommentItem(
        commentId: 'demo-comment-welcome-1',
        postId: 'demo-post-welcome',
        content: '收到！有什么想聊的随时留言。',
        authorType: 'assistant',
        authorAssistantId: xiaoruId,
        createdAt: ago(const Duration(hours: 4)),
      ).toJson(),
    ];

    final meetingNote = StickyNoteItem(
      noteId: 'demo-note-meeting',
      content: '下午三点产品评审会，带上演示稿。',
      title: '今日安排',
      authorType: 'user',
      paletteKey: 1,
      wallOrder: 0,
      createdAt: ago(const Duration(days: 1)),
      updatedAt: ago(const Duration(days: 1)),
    );
    final checklistNote = StickyNoteItem(
      noteId: 'demo-note-checklist',
      content: '',
      title: '本周清单',
      noteType: 'checklist',
      authorType: 'user',
      paletteKey: 3,
      wallOrder: 1,
      createdAt: ago(const Duration(hours: 20)),
      updatedAt: ago(const Duration(hours: 3)),
    );
    final assistantNote = StickyNoteItem(
      noteId: 'demo-note-xiaoru',
      content: '帮你记下来了：周五前回复合作邮件。',
      authorType: 'assistant',
      authorAssistantId: xiaoruId,
      paletteKey: 4,
      wallOrder: 2,
      createdAt: ago(const Duration(minutes: 90)),
      updatedAt: ago(const Duration(minutes: 90)),
    );
    final doneNote = StickyNoteItem(
      noteId: 'demo-note-done',
      content: '给绿植浇水。',
      authorType: 'user',
      completionState: 'completed',
      completionReason: 'completed',
      completedAt: ago(const Duration(days: 2)),
      paletteKey: 2,
      wallOrder: 0,
      createdAt: ago(const Duration(days: 3)),
      updatedAt: ago(const Duration(days: 2)),
    );
    final checklistItems = [
      StickyNoteChecklistItem(
        itemId: 'demo-item-1',
        noteId: checklistNote.noteId,
        content: '买牛奶',
        position: 0,
        checked: true,
        checkedAt: ago(const Duration(hours: 3)),
        createdAt: ago(const Duration(hours: 20)),
        updatedAt: ago(const Duration(hours: 3)),
      ),
      StickyNoteChecklistItem(
        itemId: 'demo-item-2',
        noteId: checklistNote.noteId,
        content: '写周报',
        position: 1,
        createdAt: ago(const Duration(hours: 20)),
        updatedAt: ago(const Duration(hours: 20)),
      ),
      StickyNoteChecklistItem(
        itemId: 'demo-item-3',
        noteId: checklistNote.noteId,
        content: '回复邮件',
        position: 2,
        createdAt: ago(const Duration(hours: 20)),
        updatedAt: ago(const Duration(hours: 20)),
      ),
    ];

    final reviewEvent = CalendarEventItem(
      eventId: 'demo-event-review',
      content: '产品评审会',
      notes: '会议室 A，带演示稿。',
      categoryId: 'work',
      authorType: 'user',
      eventTime: DateTime(
        now.year,
        now.month,
        now.day,
        15,
      ).add(const Duration(days: 1)),
      timePrecision: 'exact',
      createdAt: ago(const Duration(days: 2)),
    );
    final standupEvent = CalendarEventItem(
      eventId: 'demo-event-standup',
      content: '每周例会',
      categoryId: 'work',
      authorType: 'user',
      eventTime: DateTime(
        now.year,
        now.month,
        now.day,
        10,
      ).subtract(Duration(days: now.weekday - 1)),
      recurrenceKind: 'weekly',
      recurrenceInterval: 1,
      recurrenceWeekdays: const [1, 3, 5],
      timePrecision: 'exact',
      createdAt: ago(const Duration(days: 20)),
    );
    final assistantEvent = CalendarEventItem(
      eventId: 'demo-event-water',
      content: '小如提醒：记得喝水',
      categoryId: 'daily',
      authorType: 'assistant',
      authorAssistantId: xiaoruId,
      eventTime: now.add(const Duration(hours: 2)),
      timePrecision: 'exact',
      createdAt: ago(const Duration(minutes: 60)),
    );

    final tokenRecords = [
      tokenRow(
        recordId: 'demo-token-1',
        assistantId: xiaoruId,
        input: 820,
        output: 260,
        createdAt: ago(const Duration(hours: 6)),
      ),
      tokenRow(
        recordId: 'demo-token-2',
        assistantId: xiaoruId,
        input: 1300,
        output: 410,
        createdAt: ago(const Duration(hours: 2)),
      ),
      tokenRow(
        recordId: 'demo-token-3',
        assistantId: alanId,
        input: 640,
        output: 180,
        createdAt: ago(const Duration(days: 1, hours: 3)),
        estimated: true,
      ),
      tokenRow(
        recordId: 'demo-token-4',
        assistantId: alanId,
        input: 990,
        output: 320,
        createdAt: ago(const Duration(days: 2)),
      ),
    ];

    return DemoSeedData(
      assistants: [xiaoru.toJson(), alan.toJson()],
      conversations: conversations
          .map((conversation) => conversation.toJson())
          .toList(),
      modelServices: [modelService.toJson()],
      boardPosts: boardPosts,
      boardComments: boardComments,
      boardAssistantLikes: const {
        'demo-post-welcome': [xiaoruId],
      },
      boardUserLikedPosts: const ['demo-post-xiaoru'],
      stickyNotes: [
        meetingNote.toJson(),
        checklistNote.toJson(),
        assistantNote.toJson(),
        doneNote.toJson(),
      ],
      stickyNoteItems: checklistItems.map((item) => item.toJson()).toList(),
      calendarEvents: [
        reviewEvent.toJson(),
        standupEvent.toJson(),
        assistantEvent.toJson(),
      ],
      tokenRecords: tokenRecords,
    );
  }
}
