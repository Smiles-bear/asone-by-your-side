import 'package:asone_contracts/asone_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
  final updatedAt = DateTime.utc(2026, 1, 3, 4, 5, 6);

  test('Assistant JSON round trip preserves public fields', () {
    final assistant = Assistant(
      id: 'assistant-1',
      name: '公开助手',
      avatar: 'avatar.png',
      mainModel: 'main-model',
      assistantModel: 'assistant-model',
      voice: 'voice-1',
      systemPrompt: 'prompt',
      modelServiceId: 'service-1',
      assistantModelServiceId: 'service-2',
      replyMode: 'continuous',
      memoryExpressionStyle: 'concise',
      memoryExpressionCustom: 'custom',
      memoryAutoOrganizeEnabled: false,
      communicationStyle: 'direct',
      behaviorBoundaries: 'boundary',
      contextWindow: 32_000,
      maxOutputTokens: 2_048,
      timestampsEnabled: 0,
      userProfile: 'profile',
      diaryWriter: 'writer',
      diarySubject: 'subject',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    expect(Assistant.fromJson(assistant.toJson()).toJson(), assistant.toJson());
  });

  test('Conversation JSON round trip preserves nullable activity fields', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: '测试对话',
      assistantId: 'assistant-1',
      kind: 'single',
      status: 'active',
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastMessage: '最后一条消息',
      lastMessageAt: updatedAt,
      draftText: '草稿',
      draftUpdatedAt: updatedAt,
      unreadCount: 2,
      chatBackgroundMode: 'custom',
      chatBackgroundPath: '/tmp/background.png',
    );

    final restored = Conversation.fromJson(conversation.toJson());
    expect(restored.toJson(), conversation.toJson());
    expect(restored.hasDraft, isTrue);
    expect(restored.listActivityAt, updatedAt);
  });

  test('ModelService JSON round trip preserves provider metadata', () {
    final service = ModelService(
      id: 'service-1',
      name: '测试服务',
      baseUrl: 'https://example.test/v1',
      apiKey: 'test-key',
      model: 'test-model',
      protocolType: 'openai_compatible',
      providerId: 'custom',
      providerAdapterVersion: 2,
      status: 'active',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    expect(ModelService.fromJson(service.toJson()).toJson(), service.toJson());
  });

  test('SearchResult JSON round trip preserves message references', () {
    final result = SearchResult(
      messageId: 'message-1',
      conversationId: 'conversation-1',
      role: 'assistant',
      content: '搜索结果',
      createdAt: updatedAt,
    );

    expect(SearchResult.fromJson(result.toJson()).toJson(), result.toJson());
  });

  test('Board models preserve soft-delete and threading fields', () {
    final post = BoardPostItem(
      postId: 'post-1',
      content: '公开留言',
      authorType: 'user',
      createdAt: createdAt,
      deletedAt: updatedAt,
    );
    final comment = BoardCommentItem(
      commentId: 'comment-1',
      postId: post.postId,
      content: '公开评论',
      authorType: 'assistant',
      authorAssistantId: 'assistant-1',
      targetAssistantId: 'assistant-2',
      parentCommentId: 'comment-0',
      createdAt: updatedAt,
    );

    expect(BoardPostItem.fromJson(post.toJson()).toJson(), post.toJson());
    expect(BoardPostItem.fromJson(post.toJson()).isDeleted, isTrue);
    expect(
      BoardCommentItem.fromJson(comment.toJson()).toJson(),
      comment.toJson(),
    );
    expect(BoardCommentItem.fromJson(comment.toJson()).isDeleted, isFalse);
  });

  test('Sticky note models preserve completion and checklist state', () {
    final note = StickyNoteItem(
      noteId: 'note-1',
      content: '待办事项',
      title: '今天',
      noteType: 'checklist',
      authorType: 'user',
      originConversationId: 'conversation-1',
      completionState: 'completed',
      completionReason: 'completed',
      completedAt: updatedAt,
      pinned: true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    final checklist = StickyNoteChecklistItem(
      itemId: 'item-1',
      noteId: note.noteId,
      content: '完成拆分',
      position: 0,
      checked: true,
      checkedAt: updatedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    expect(StickyNoteItem.fromJson(note.toJson()).toJson(), note.toJson());
    expect(StickyNoteItem.fromJson(note.toJson()).isCompleted, isTrue);
    expect(
      StickyNoteChecklistItem.fromJson(checklist.toJson()).toJson(),
      checklist.toJson(),
    );
  });

  test('Calendar event preserves recurrence and legacy JSON aliases', () {
    final event = CalendarEventItem(
      eventId: 'event-1',
      content: '每周例会',
      notes: '公开日历测试',
      categoryId: 'work',
      authorType: 'user',
      eventTime: updatedAt,
      endAt: updatedAt.add(const Duration(hours: 1)),
      recurrenceKind: 'weekly',
      recurrenceInterval: 2,
      recurrenceWeekdays: const [DateTime.monday, DateTime.friday],
      recurrenceUntil: updatedAt.add(const Duration(days: 30)),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final restored = CalendarEventItem.fromJson(event.toJson());
    expect(restored.toJson(), event.toJson());
    expect(restored.title, event.content);
    expect(restored.startAt, event.eventTime);
    expect(restored.isRecurring, isTrue);
  });

  test('Pending item JSON round trip preserves due date text', () {
    final item = PendingItem(
      pendingId: 'pending-1',
      content: '待处理事项',
      status: 'open',
      dueAt: '2026-09-10',
      createdAt: createdAt,
    );

    expect(PendingItem.fromJson(item.toJson()).toJson(), item.toJson());
  });
}
