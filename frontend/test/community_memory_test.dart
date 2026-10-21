import 'dart:convert';
import 'dart:io';
import 'package:asone_contracts/asone_contracts.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/services/provider_adapters/protocol_client.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:azruiyoi_community/community_memory_service.dart';
import 'package:azruiyoi_community/community_memory_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<
  ({
    PublicCore core,
    CoreDatabase database,
    Assistant assistant,
    String conversationId,
  })
>
_fixture() async {
  final root = await Directory.systemTemp.createTemp('community-memory-');
  final db = CoreDatabase.forTesting(
    databaseFactory: databaseFactoryFfi,
    supportDirectoryProvider: () async => root,
  );
  addTearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  final core = PublicCore(database: db);
  await core.open();
  final service = await core.modelServices.createModelService({
    'name': '测试模型',
    'base_url': 'https://memory.example.test/v1',
    'api_key': 'test-key',
    'model': 'test-model',
    'protocol_type': ProtocolType.openaiChat,
  });
  final assistant = await core.ensureAssistantForService(service);
  final conversation = await core.conversations.createConversation(
    '记忆测试',
    assistantId: assistant.id,
  );
  return (
    core: core,
    database: db,
    assistant: assistant,
    conversationId: conversation.id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('记忆增改搜索、版本冲突和删除隔离在数据库重开后保留', () async {
    final f = await _fixture();
    final created = await f.core.memories.createUserMemory(
      assistantId: f.assistant.id,
      content: '用户喜欢茉莉花茶',
      sourceTime: DateTime.utc(2026, 10, 20),
    );
    expect(
      await f.core.memories.search(assistantId: f.assistant.id, query: '茉莉花茶'),
      hasLength(1),
    );
    final changed = await f.core.memories.update(
      memoryId: created.memoryId,
      assistantId: f.assistant.id,
      content: '用户喜欢桂花茶',
      expectedVersion: created.editVersion,
    );
    await expectLater(
      f.core.memories.update(
        memoryId: created.memoryId,
        assistantId: f.assistant.id,
        content: '过时的编辑',
        expectedVersion: created.editVersion,
      ),
      throwsStateError,
    );
    final other = await f.core.repository.createAssistant(name: '另一个助手');
    expect(
      await f.core.memories.search(assistantId: other.id, query: '桂花茶'),
      isEmpty,
    );
    await f.database.close();
    expect(
      (await f.core.memories.list(f.assistant.id)).single.content,
      changed.content,
    );
    await f.core.memories.delete(
      memoryId: created.memoryId,
      assistantId: f.assistant.id,
    );
    expect(
      await f.core.memories.search(assistantId: f.assistant.id, query: '桂花茶'),
      isEmpty,
    );
    expect(await f.core.memories.saveReviewed(f.assistant.id, ['用户喜欢桂花茶']), 0);
    expect(await f.core.memories.list(f.assistant.id), isEmpty);
  });

  test('记忆日期范围和关键字筛选不会把通配符当成查询表达式', () async {
    final f = await _fixture();
    await f.core.memories.createUserMemory(
      assistantId: f.assistant.id,
      content: '项目进度100%_完成',
      sourceTime: DateTime.utc(2026, 10, 20),
    );
    await f.core.memories.createUserMemory(
      assistantId: f.assistant.id,
      content: '项目进度1000完成',
      sourceTime: DateTime.utc(2026, 10, 19),
    );
    expect(
      (await f.core.memories.list(
        f.assistant.id,
        keyword: '%_',
      )).single.content,
      '项目进度100%_完成',
    );
    final selected = await f.core.memories.list(
      f.assistant.id,
      keyword: '项目 完成',
      dateRange: (
        start: DateTime.utc(2026, 10, 20),
        end: DateTime.utc(2026, 10, 21),
      ),
    );
    expect(selected.single.content, '项目进度100%_完成');
  });

  test('单聊检索本助手相关记忆，关闭后不再注入，工具保持禁用', () async {
    final f = await _fixture();
    await f.core.memories.createUserMemory(
      assistantId: f.assistant.id,
      content: '用户喜欢茉莉花茶',
    );
    final turn = await f.core.chatContext.compileTurnContext(
      conversationId: f.conversationId,
      query: '茉莉花茶',
    );
    expect(turn.context['all_system_parts'].toString(), contains('用户喜欢茉莉花茶'));
    expect(turn.context['tools_enabled'], false);
    final groupScope = await f.core.chatContext.compileTurnContext(
      conversationId: f.conversationId,
      query: '茉莉花茶',
      includeMemories: false,
    );
    expect(groupScope.context['all_system_parts'], isEmpty);
    await f.core.memories.setRetrievalEnabled(f.assistant.id, false);
    await f.database.close();
    final without = await f.core.chatContext.compileTurnContext(
      conversationId: f.conversationId,
      query: '茉莉花茶',
    );
    expect(without.context['all_system_parts'], isEmpty);
  });

  test('整理仅生成候选，确认后原子去重保存，旧预览和越界条目被拒绝', () async {
    final f = await _fixture();
    await f.core.repository.saveMessage(f.conversationId, 'user', '我喜欢茉莉花茶');
    Object? sent;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            sent = request.data;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'choices': [
                    {
                      'message': {
                        'content': jsonEncode({
                          'memories': ['用户喜欢茉莉花茶', '用户喜欢茉莉花茶'],
                        }),
                      },
                      'finish_reason': 'stop',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    addTearDown(() => dio.close(force: true));
    final memory = CommunityMemoryService(
      repository: f.core.repository,
      store: f.core.memories,
      client: ProtocolClient(dio: dio),
    );
    final proposal = await memory.prepare(
      assistantId: f.assistant.id,
      conversationId: f.conversationId,
    );
    expect(sent.toString(), contains('我喜欢茉莉花茶'));
    expect(proposal.items, ['用户喜欢茉莉花茶']);
    expect(await f.core.memories.list(f.assistant.id), isEmpty);
    await expectLater(
      memory.confirm(proposal, ['未预览的内容']),
      throwsArgumentError,
    );
    expect(await memory.confirm(proposal, proposal.items), 1);
    expect(await memory.confirm(proposal, proposal.items), 0);
    await f.core.repository.saveMessage(f.conversationId, 'user', '我的偏好改变了');
    await expectLater(
      memory.confirm(proposal, proposal.items),
      throwsStateError,
    );
  });

  test('整理确认批次校验失败时不写入任何条目', () async {
    final f = await _fixture();
    await expectLater(
      f.core.memories.saveReviewed(f.assistant.id, ['合法内容', '']),
      throwsArgumentError,
    );
    expect(await f.core.memories.list(f.assistant.id), isEmpty);
  });

  test('实际API请求包含相关记忆且不会读取其他助手的记忆', () async {
    final f = await _fixture();
    await f.core.memories.createUserMemory(
      assistantId: f.assistant.id,
      content: '用户喜欢茉莉花茶',
    );
    final other = await f.core.repository.createAssistant(name: '另一位助手');
    await f.core.memories.createUserMemory(
      assistantId: other.id,
      content: '茉莉花茶：另一个助手的独有资料',
    );
    Object? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options.data;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: ResponseBody.fromString(
                  'data: {"choices":[{"delta":{"content":"给你泡茶"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
                  200,
                  headers: {
                    Headers.contentTypeHeader: ['text/event-stream'],
                  },
                ),
              ),
            );
          },
        ),
      );
    addTearDown(() => dio.close(force: true));
    final core = PublicCore(database: f.database, chatDio: dio);
    await core.open();
    String? completion;
    await core.chat.send(
      conversationId: f.conversationId,
      content: '我想喝茉莉花茶',
      userAlreadyPersisted: false,
      onDelta: (_) {},
      onDone: ({String? error}) => completion = error,
    );
    expect(completion, isNull);
    expect(request.toString(), contains('用户喜欢茉莉花茶'));
    expect(request.toString(), isNot(contains('另一个助手的独有资料')));
    expect(
      (await core.messages.getMessages(f.conversationId)).last.content,
      '给你泡茶',
    );
    await core.memories.setRetrievalEnabled(f.assistant.id, false);
    await core.chat.send(
      conversationId: f.conversationId,
      content: '再来一杯茉莉花茶',
      userAlreadyPersisted: false,
      onDelta: (_) {},
      onDone: ({String? error}) => completion = error,
    );
    expect(completion, isNull);
    expect(request.toString(), isNot(contains('用户喜欢茉莉花茶')));
    expect(request.toString(), isNot(contains('另一个助手的独有资料')));
    await core.memories.setRetrievalEnabled(f.assistant.id, true);
    final saved = (await core.memories.list(f.assistant.id)).single;
    await core.memories.delete(
      memoryId: saved.memoryId,
      assistantId: f.assistant.id,
    );
    await core.chat.send(
      conversationId: f.conversationId,
      content: '还有茉莉花茶吗',
      userAlreadyPersisted: false,
      onDelta: (_) {},
      onDone: ({String? error}) => completion = error,
    );
    expect(completion, isNull);
    expect(request.toString(), isNot(contains('用户喜欢茉莉花茶')));
  });

  testWidgets('记忆页面提供新增、检索开关与前台整理入口', (tester) async {
    final f = (await tester.runAsync(_fixture))!;
    OpenCoreBinding.attach(f.core);
    await tester.pumpWidget(
      MaterialApp(home: CommunityMemoryPage(assistant: f.assistant)),
    );
    // SQLite replies arrive on real I/O turns, outside the widget fake clock.
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('记忆加载失败，请重试'), findsNothing);
    expect(find.text('聊天中使用记忆'), findsOneWidget);
    expect(find.text('从对话整理'), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-memory-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community-memory-content')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
