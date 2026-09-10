import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoCore binding', () {
    test('attaches to OpenCoreBinding and exposes all eight APIs', () {
      final core = DemoCore.withDemoSeed();
      OpenCoreBinding.attach(core);
      addTearDown(OpenCoreBinding.detach);

      expect(OpenCoreBinding.instance, same(core));
      expect(OpenCoreBinding.instance.assistants, isNotNull);
      expect(OpenCoreBinding.instance.conversations, isNotNull);
      expect(OpenCoreBinding.instance.modelServices, isNotNull);
      expect(OpenCoreBinding.instance.calendar, isNotNull);
      expect(OpenCoreBinding.instance.stickyNotes, isNotNull);
      expect(OpenCoreBinding.instance.messageBoard, isNotNull);
      expect(OpenCoreBinding.instance.featureUnread, isNotNull);
      expect(OpenCoreBinding.instance.tokenUsage, isNotNull);
    });
  });

  group('assistants & conversations', () {
    test('seeded assistants support CRUD and profile', () async {
      final core = DemoCore.withDemoSeed();
      final assistants = await core.assistants.getAssistants();
      expect(assistants.length, 2);
      expect(assistants.first.name, '小如');

      final created = await core.assistants.createAssistant(name: ' 新助手 ');
      expect(created.name, '新助手');
      final updated = await core.assistants.updateAssistant(created.id, {
        'name': '改名助手',
      });
      expect(updated.name, '改名助手');
      expect((await core.assistants.getAssistant(created.id))?.name, '改名助手');

      await core.assistants.updateUserProfile(created.id, userProfile: '喜欢演示');
      expect(await core.assistants.getUserProfile(created.id), '喜欢演示');

      expect(
        () => core.assistants.createAssistant(name: '  '),
        throwsArgumentError,
      );
    });

    test(
      'primary conversation is created once and cascades on delete',
      () async {
        final core = DemoCore.withDemoSeed();
        final existing = await core.assistants.getOrCreatePrimaryConversation(
          'demo-assistant-xiaoru',
        );
        expect(existing.id, 'demo-conversation-xiaoru');

        final created = await core.assistants
            .createAssistantWithPrimaryConversation(name: '演示新助手');
        expect(created.assistant.name, '演示新助手');
        final again = await core.assistants.getOrCreatePrimaryConversation(
          created.assistant.id,
        );
        expect(again.id, created.conversation.id);

        await core.assistants.deleteAssistant(created.assistant.id);
        expect(
          await core.conversations.getConversation(created.conversation.id),
          isNull,
        );
      },
    );

    test('conversation draft, rename and read state', () async {
      final core = DemoCore.withDemoSeed();
      await core.conversations.saveConversationDraft(
        'demo-conversation-xiaoru',
        '草稿内容',
      );
      expect(
        await core.conversations.getConversationDraft(
          'demo-conversation-xiaoru',
        ),
        '草稿内容',
      );
      final conversation = await core.conversations.getConversation(
        'demo-conversation-xiaoru',
      );
      expect(conversation?.hasDraft, isTrue);

      final renamed = await core.conversations.updateConversation(
        'demo-conversation-alan',
        title: '阿澜的会话',
      );
      expect(renamed.title, '阿澜的会话');
      await core.conversations.markConversationRead('demo-conversation-xiaoru');
    });
  });

  group('model services', () {
    test('CRUD, in-use guard and capability snapshot', () async {
      final core = DemoCore.withDemoSeed();
      final services = await core.modelServices.getModelServices();
      expect(services.single.name, '演示模型服务');

      expect(
        () => core.modelServices.deleteModelService('demo-service'),
        throwsA(isA<ModelServiceInUseException>()),
      );

      final created = await core.modelServices.createModelService({
        'name': '备用服务',
        'base_url': 'https://backup.example.invalid/v1',
        'api_key': 'demo-key-not-real',
        'model': 'backup-model',
      });
      final updated = await core.modelServices.updateModelService(created.id, {
        'model': 'backup-model-2',
      });
      expect(updated.model, 'backup-model-2');

      final fingerprint = core.modelServices.modelConfigurationFingerprint(
        updated,
      );
      expect(fingerprint, isNotEmpty);
      await core.modelServices.saveModelCapabilityTest(
        serviceId: created.id,
        capability: 'chat',
        verdict: 'pass',
        elapsedMs: 120,
        configurationFingerprint: fingerprint,
      );
      await core.modelServices.saveModelCapabilityTest(
        serviceId: created.id,
        capability: 'audio',
        verdict: 'fail',
        elapsedMs: 80,
        configurationFingerprint: fingerprint,
      );
      expect(
        await core.modelServices.getModelCapabilityTests(created.id),
        hasLength(2),
      );
      await core.modelServices.clearModelCapabilityTests(
        created.id,
        preserveAudio: true,
      );
      final kept = await core.modelServices.getModelCapabilityTests(created.id);
      expect(kept.single['capability'], 'audio');

      final persisted = await core.modelServices.persistDetectedModelProtocol(
        created.id,
        'anthropic',
      );
      expect(persisted.protocolType, 'anthropic');
      expect(
        await core.modelServices.recoverDetectedModelProtocol(created.id),
        'anthropic',
      );

      await core.modelServices.deleteModelService(created.id);
      expect(await core.modelServices.getModelServices(), hasLength(1));
    });
  });

  group('message board', () {
    test('posts, comments, likes and unread flow', () async {
      final core = DemoCore.withDemoSeed();
      expect(await core.messageBoard.listActivePosts(), hasLength(2));
      expect(await core.messageBoard.unreadCount(), 2);

      final likeStates = await core.messageBoard.listPostLikeStates([
        'demo-post-welcome',
        'demo-post-xiaoru',
      ]);
      expect(likeStates['demo-post-welcome']?.currentUserLiked, isFalse);
      expect(likeStates['demo-post-welcome']?.totalCount, 1);
      expect(likeStates['demo-post-xiaoru']?.currentUserLiked, isTrue);

      final post = await core.messageBoard.publishPost(
        content: ' 新帖 ',
        authorType: 'user',
      );
      expect(post.content, '新帖');
      final comment = await core.messageBoard.publishComment(
        postId: post.postId,
        content: '沙发',
        authorType: 'assistant',
        authorAssistantId: 'demo-assistant-xiaoru',
        autoLikeUserPost: true,
      );
      final states = await core.messageBoard.listPostLikeStates([post.postId]);
      expect(states[post.postId]?.totalCount, 1);
      final counts = await core.messageBoard.listPostCommentCountsForUser([
        post.postId,
      ]);
      expect(counts[post.postId], 1);
      expect(
        await core.messageBoard.listCommentsForAssistant(
          post.postId,
          'demo-assistant-xiaoru',
        ),
        hasLength(1),
      );
      expect(
        await core.messageBoard.countAssistantComments(
          post.postId,
          'demo-assistant-xiaoru',
        ),
        1,
      );

      await core.messageBoard.markRead();
      expect(await core.messageBoard.unreadCount(), 0);

      expect(await core.messageBoard.deletePost(post.postId), isTrue);
      expect(
        (await core.messageBoard.loadPost(post.postId))?.isDeleted,
        isTrue,
      );
      expect(await core.messageBoard.listActivePosts(), hasLength(2));
      expect(await core.messageBoard.deleteComment(comment.commentId), isFalse);
      expect(
        () => core.messageBoard.publishComment(
          postId: post.postId,
          content: 'x',
          authorType: 'user',
        ),
        throwsStateError,
      );
      expect(
        () => core.messageBoard.publishPost(content: '  ', authorType: 'user'),
        throwsArgumentError,
      );
    });
  });

  group('sticky notes', () {
    test('wall listing and checklist completion lifecycle', () async {
      final core = DemoCore.withDemoSeed();
      expect(await core.stickyNotes.listOpen(), hasLength(3));

      final detail = await core.stickyNotes.loadDetail('demo-note-checklist');
      expect(detail?.items, hasLength(3));

      var updated = await core.stickyNotes.setChecklistItemChecked(
        'demo-item-2',
        true,
      );
      expect(updated.note.isCompleted, isFalse);
      updated = await core.stickyNotes.setChecklistItemChecked(
        'demo-item-3',
        true,
      );
      expect(updated.note.isCompleted, isTrue);
      expect(updated.note.completionReason, 'completed');
      updated = await core.stickyNotes.setChecklistItemChecked(
        'demo-item-3',
        false,
      );
      expect(updated.note.completionState, 'open');

      expect(
        await core.stickyNotes.setCompletion('demo-note-meeting', 'done'),
        isTrue,
      );
      expect(await core.stickyNotes.tear('demo-note-xiaoru'), isTrue);
      expect(
        (await core.stickyNotes.load('demo-note-xiaoru'))?.completionReason,
        'torn',
      );
      expect(await core.stickyNotes.restore('demo-note-meeting'), isTrue);
      expect(
        await core.stickyNotes.listHistory(completedOnly: true),
        isNotEmpty,
      );

      expect(
        () =>
            core.stickyNotes.createTextNote(content: '  ', authorType: 'user'),
        throwsArgumentError,
      );
      expect(
        () => core.stickyNotes.createChecklistNote(
          items: const ['  '],
          authorType: 'user',
        ),
        throwsArgumentError,
      );
      final created = await core.stickyNotes.createChecklistNote(
        items: const ['任务甲', '任务乙'],
        authorType: 'user',
        title: '新清单',
      );
      expect(created.items, hasLength(2));

      final found = await core.stickyNotes.search(keyword: '评审');
      expect(found.single.noteId, 'demo-note-meeting');

      expect(
        await core.stickyNotes.setPinned('demo-note-meeting', true),
        isTrue,
      );
      expect(
        (await core.stickyNotes.listOpen()).first.noteId,
        'demo-note-meeting',
      );

      final expiring = await core.stickyNotes.createTextNote(
        content: '过期演示',
        authorType: 'user',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(await core.stickyNotes.completeExpired(), greaterThanOrEqualTo(1));
      expect(
        (await core.stickyNotes.load(expiring.noteId))?.completionReason,
        'expired',
      );
      expect(await core.stickyNotes.hardDelete(expiring.noteId), isTrue);
      expect(await core.stickyNotes.load(expiring.noteId), isNull);

      expect(
        await core.stickyNotes.listByAssistant('demo-assistant-xiaoru'),
        hasLength(1),
      );
      expect(await core.stickyNotes.countActive(), greaterThan(0));
    });
  });

  group('calendar', () {
    test('weekly recurrence expansion and exceptions (fixed dates)', () async {
      final core = DemoCore();
      final created = await core.calendar.createEvent(
        input: CalendarEventInput(
          title: '站会',
          startAt: DateTime(2026, 3, 9, 10),
          recurrenceKind: 'weekly',
          recurrenceWeekdays: const [1, 3, 5],
        ),
        authorType: 'user',
      );

      final occurrences = await core.calendar.expandOccurrences(
        rangeStart: DateTime(2026, 3, 9),
        rangeEnd: DateTime(2026, 3, 22, 23, 59),
      );
      expect(occurrences.map((item) => item.occurrenceKey), [
        '2026-03-09',
        '2026-03-11',
        '2026-03-13',
        '2026-03-16',
        '2026-03-18',
        '2026-03-20',
      ]);

      await core.calendar.updateOccurrence(
        eventId: created.eventId,
        occurrenceKey: '2026-03-13',
        input: CalendarEventInput(
          title: '改期评审',
          startAt: DateTime(2026, 3, 13, 14),
        ),
      );
      final afterModify = await core.calendar.expandOccurrences(
        rangeStart: DateTime(2026, 3, 12),
        rangeEnd: DateTime(2026, 3, 14),
      );
      expect(afterModify.single.title, '改期评审');
      expect(afterModify.single.isException, isTrue);

      expect(
        await core.calendar.deleteOccurrence(
          eventId: created.eventId,
          occurrenceKey: '2026-03-16',
        ),
        isTrue,
      );
      expect(
        await core.calendar.expandOccurrences(
          rangeStart: DateTime(2026, 3, 15),
          rangeEnd: DateTime(2026, 3, 17),
        ),
        isEmpty,
      );
      final verification = await core.calendar.verifyDeletion(
        eventId: created.eventId,
        scope: 'occurrence',
        occurrenceKey: '2026-03-16',
      );
      expect(verification.verified, isTrue);

      final single = await core.calendar.addEvent(
        content: '单次事项',
        eventTime: DateTime(2026, 3, 10, 9),
        authorType: 'user',
      );
      expect(
        () => core.calendar.updateOccurrence(
          eventId: single.eventId,
          occurrenceKey: '2026-03-10',
          input: CalendarEventInput(title: 'x', startAt: DateTime(2026, 3, 10)),
        ),
        throwsArgumentError,
      );

      final successor = await core.calendar.updateFromOccurrence(
        eventId: created.eventId,
        occurrenceKey: '2026-03-18',
        input: CalendarEventInput(
          title: '新系列站会',
          startAt: DateTime(2026, 3, 18, 10),
          recurrenceKind: 'weekly',
          recurrenceWeekdays: const [1, 3, 5],
        ),
      );
      expect(successor.eventId, isNot(created.eventId));
      final afterSplit = await core.calendar.expandOccurrences(
        rangeStart: DateTime(2026, 3, 17),
        rangeEnd: DateTime(2026, 3, 25),
      );
      expect(
        afterSplit.where((item) => item.event.eventId == created.eventId),
        isEmpty,
      );
      expect(
        afterSplit.where((item) => item.event.eventId == successor.eventId),
        isNotEmpty,
      );

      expect(await core.calendar.deleteSeries(created.eventId), isTrue);
      final seriesVerification = await core.calendar.verifyDeletion(
        eventId: created.eventId,
        scope: 'series',
      );
      expect(seriesVerification.verified, isTrue);

      final month = await core.calendar.listMonthForUser(2026, 3);
      expect(month, isNotEmpty);
      final colors = await core.calendar.resolveCreatorColors(month);
      expect(colors['user'], isNotNull);

      final byDate = await core.calendar.listEventsByDate(2026, 3, 10);
      expect(byDate.map((item) => item.eventId), contains(single.eventId));

      final sourced = await core.calendar.createEvent(
        input: CalendarEventInput(
          title: '来源事项',
          startAt: DateTime(2026, 3, 11, 8),
        ),
        authorType: 'user',
        sourceType: 'demo',
        sourceId: 'src-1',
      );
      expect(
        (await core.calendar.findBySource('demo', 'src-1'))?.eventId,
        sourced.eventId,
      );
      expect(
        await core.calendar.listDefinitionsForAssistant('demo-assistant'),
        hasLength(3),
      );
      expect(
        () => core.calendar.createEvent(
          input: CalendarEventInput(title: ' ', startAt: DateTime(2026, 3, 11)),
          authorType: 'user',
        ),
        throwsArgumentError,
      );
    });

    test('seeded events appear in the upcoming window', () async {
      final core = DemoCore.withDemoSeed();
      final upcoming = await core.calendar.listUpcoming(7);
      expect(
        upcoming.map((item) => item.eventId).toSet(),
        containsAll(['demo-event-review', 'demo-event-water']),
      );
      final byMonth = await core.calendar.listEventsByMonth(
        DateTime.now().year,
        DateTime.now().month,
      );
      expect(byMonth, isNotNull);
    });
  });

  group('feature unread', () {
    test('seed flags, markRead flow and re-raise on new content', () async {
      final core = DemoCore.withDemoSeed();
      var snapshot = await core.featureUnread.refresh();
      expect(snapshot.messageBoardCount, 2);
      expect(snapshot.calendar, isTrue);
      expect(snapshot.stickyNote, isTrue);
      expect(snapshot.any, isTrue);

      await core.featureUnread.markRead(FeatureUnreadKind.messageBoard);
      await core.featureUnread.markRead(FeatureUnreadKind.calendar);
      await core.featureUnread.markRead(FeatureUnreadKind.stickyNote);
      snapshot = await core.featureUnread.refresh();
      expect(snapshot.any, isFalse);

      await core.messageBoard.publishPost(
        content: '新留言',
        authorType: 'assistant',
        authorAssistantId: 'demo-assistant-xiaoru',
      );
      snapshot = await core.featureUnread.refresh();
      expect(snapshot.messageBoard, isTrue);
      expect(
        core.featureUnread.changes.value.messageBoardCount,
        greaterThan(0),
      );
      expect(
        await core.featureUnread.messageBoardUnreadCount(
          assistantId: 'demo-assistant-xiaoru',
        ),
        greaterThan(0),
      );
    });
  });

  group('token usage', () {
    test('aggregations over seeded records', () async {
      final core = DemoCore.withDemoSeed();
      final overview = await core.tokenUsage.getUsageOverview();
      expect(overview['total_requests'], 4);
      expect(overview['total_tokens'], 4920);
      expect(overview['has_estimated'], isTrue);
      final byModel = overview['by_model'] as List<Map<String, Object?>>;
      expect(byModel.single['model'], 'demo-model');

      final total = await core.tokenUsage.getTotalSummary();
      expect(total.totalTokens, 4920);

      final alanChat = await core.tokenUsage.getSummaryByType(
        taskType: 'chat',
        assistantId: 'demo-assistant-alan',
      );
      expect(alanChat.totalTokens, 2130);

      final memory = await core.tokenUsage.getSummaryByType(
        taskType: 'memory_rebuild',
      );
      expect(memory.totalTokens, 0);

      expect(
        await core.tokenUsage.getDailyUsageByType(taskType: 'chat'),
        isNotEmpty,
      );
      expect(
        await core.tokenUsage.getDailyUsageByType(taskType: 'memory_rebuild'),
        isEmpty,
      );

      final records = await core.tokenUsage.getDetailedRecords(limit: 2);
      expect(records, hasLength(2));
      expect(records.first.createdAt.isBefore(records.last.createdAt), isFalse);
      final offsetRecords = await core.tokenUsage.getDetailedRecords(
        limit: 2,
        offset: 2,
      );
      expect(offsetRecords.first.recordId, isNot(records.first.recordId));
    });
  });
}
