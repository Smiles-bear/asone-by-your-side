import 'dart:convert';
import 'dart:io';
import 'package:asone_contracts/asone_contracts.dart';
import 'package:azruiyoi_community/features/world/world_entries.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/local_core/world/world_import_parser.dart';
import 'package:azruiyoi_community/services/provider_adapters/protocol_client.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:azruiyoi_community/community_world_page.dart';
import 'package:azruiyoi_community/community_world_document.dart';
import 'package:azruiyoi_community/community_world_service.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<
  ({PublicCore core, CoreDatabase db, Assistant assistant, String conversation})
>
fixture({Dio? dio}) async {
  final root = await Directory.systemTemp.createTemp('community-world-');
  final db = CoreDatabase.forTesting(
    databaseFactory: databaseFactoryFfi,
    supportDirectoryProvider: () async => root,
  );
  addTearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  final core = PublicCore(database: db, chatDio: dio);
  await core.open();
  final service = await core.modelServices.createModelService({
    'name': '测试模型',
    'base_url': 'https://world.example.test/v1',
    'api_key': 'test-key',
    'model': 'test-model',
    'protocol_type': ProtocolType.openaiChat,
  });
  final assistant = await core.ensureAssistantForService(service);
  final conversation = await core.repository.getOrCreatePrimaryConversation(
    assistant.id,
  );
  return (
    core: core,
    db: db,
    assistant: assistant,
    conversation: conversation.id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('所选文档在本机读取，保留正文并对超长内容给出错误', () async {
    final root = await Directory.systemTemp.createTemp('community-document-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/星港.md');
    await file.writeAsString('# 设定\r\n星港');
    final picked = PlatformFile(
      name: '星港.md',
      path: file.path,
      size: await file.length(),
    );
    expect((await readCommunityWorldDocument(picked)).text, '# 设定\n星港');
    await file.writeAsString(
      '甲' * (CommunityWorldService.maximumSourceLength + 1),
    );
    await expectLater(
      readCommunityWorldDocument(picked),
      throwsA(isA<WorldImportFailure>()),
    );
  });

  test('旧库增加条目结构保留原有世界正文，增改删、关键词及隔离持久化', () async {
    final f = await fixture();
    final db = await f.db.open();
    await db.insert('assistant_worlds', {
      'assistant_id': f.assistant.id,
      'visible_world_setting': '旧版原始世界正文',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    final other = await f.core.repository.createAssistant(name: '其他助手');
    await f.core.worlds.save(
      f.assistant.id,
      const WorldEntryDraft(
        title: '星港',
        content: '港口位于北方',
        category: '地点',
        keywords: ['星港'],
        usageMode: WorldUsageMode.always,
      ),
    );
    final rows = await f.core.worlds.list(f.assistant.id, '地点');
    expect(rows, hasLength(1));
    expect(await f.core.worlds.get(other.id, rows.single.id), isNull);
    expect(
      (await db.query('assistant_worlds')).single['visible_world_setting'],
      '旧版原始世界正文',
    );
    await f.core.worlds.save(
      f.assistant.id,
      const WorldEntryDraft(
        title: '星港',
        content: '港口位于南方',
        category: '地点',
        keywords: ['星港'],
      ),
      entryId: rows.single.id,
    );
    await expectLater(
      f.core.worlds.save(
        f.assistant.id,
        WorldEntryDraft(title: '坏条目', content: '正文', keywords: ['长' * 21]),
      ),
      throwsFormatException,
    );
    await f.db.close();
    expect(
      (await f.core.worlds.get(f.assistant.id, rows.single.id))!.content,
      '港口位于南方',
    );
    await f.core.worlds.setAllEnabled(f.assistant.id, false);
    expect(
      (await f.core.worlds.categories(f.assistant.id)).single.enabledCount,
      0,
    );
    await f.core.worlds.delete(other.id, rows.single.id);
    expect(await f.core.worlds.get(f.assistant.id, rows.single.id), isNotNull);
    await f.core.worlds.delete(f.assistant.id, rows.single.id);
    expect(await f.core.worlds.list(f.assistant.id, '地点'), isEmpty);
  });

  test('实际API使用当前助手每轮及相关条目，停用/删除后不注入，群聊不读私聊设定', () async {
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
                  '{"choices":[{"message":{"content":"已收到"},"finish_reason":"stop"}]}',
                  200,
                ),
              ),
            );
          },
        ),
      );
    addTearDown(() => dio.close(force: true));
    final f = await fixture(dio: dio);
    await f.core.worlds.save(
      f.assistant.id,
      const WorldEntryDraft(
        title: '称呼规则',
        content: '本助手每轮设定',
        usageMode: WorldUsageMode.always,
      ),
    );
    await f.core.worlds.save(
      f.assistant.id,
      const WorldEntryDraft(
        title: '星港',
        content: '只在相关时发出的港口资料',
        keywords: ['星港'],
      ),
    );
    final other = await f.core.repository.createAssistant(name: '别的助手');
    await f.core.worlds.save(
      other.id,
      const WorldEntryDraft(
        title: '星港',
        content: '其他助手独有条目',
        usageMode: WorldUsageMode.always,
      ),
    );
    Future<void> send(String text) async {
      String? failure;
      await f.core.chat.send(
        conversationId: f.conversation,
        content: text,
        userAlreadyPersisted: false,
        onDelta: (_) {},
        onDone: ({String? error}) => failure = error,
      );
      expect(failure, isNull);
    }

    await send('星港在哪里');
    expect(request.toString(), contains('本助手每轮设定'));
    expect(request.toString(), contains('只在相关时发出的港口资料'));
    expect(request.toString(), isNot(contains('其他助手独有条目')));
    await send('普通问候');
    expect(request.toString(), isNot(contains('只在相关时发出的港口资料')));
    final group = await f.core.chatContext.compileTurnContext(
      conversationId: f.conversation,
      query: '星港',
      includeMemories: false,
      includeAssistantSettings: false,
    );
    expect(group.context['all_system_parts'], isEmpty);
    await f.core.worlds.setAllEnabled(f.assistant.id, false);
    await send('星港在哪里');
    expect(request.toString(), isNot(contains('本助手每轮设定')));
    expect(request.toString(), isNot(contains('只在相关时发出的港口资料')));
  });

  test('整理使用正式提示与结构契约，确认前无写入、确认后保留原文且不覆盖手改条目', () async {
    final f = await fixture();
    await f.core.worlds.save(
      f.assistant.id,
      const WorldEntryDraft(title: '手写资料', content: '用户手动维护的原条目'),
    );
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.data.toString(), contains('提供的资料按主题整理'));
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'choices': [
                    {
                      'message': {
                        'content': jsonEncode({
                          'entries': [
                            {
                              'category': '地点',
                              'title': '星港',
                              'content': '星港禁止夜间通行',
                              'usage_mode': 'relevant',
                              'keywords': ['星港'],
                            },
                          ],
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
    final service = CommunityWorldService(
      repository: f.core.repository,
      store: f.core.worlds,
      client: ProtocolClient(dio: dio),
    );
    final proposal = await service.prepare(f.assistant.id, '原始资料：星港禁止夜间通行');
    expect(await f.core.worlds.sourceMaterials(f.assistant.id), isEmpty);
    expect(await f.core.worlds.list(f.assistant.id, '地点'), isEmpty);
    await Future.wait([service.confirm(proposal), service.confirm(proposal)]);
    await service.confirm(proposal);
    await f.db.close();
    expect(await f.core.worlds.sourceMaterials(f.assistant.id), [
      '原始资料：星港禁止夜间通行',
    ]);
    expect(await f.core.worlds.list(f.assistant.id, '地点'), hasLength(1));
    expect(await f.core.worlds.list(f.assistant.id, '其他资料'), hasLength(1));
    final token = CancelToken()..cancel();
    await expectLater(
      service.prepare(f.assistant.id, '已取消的资料', cancelToken: token),
      throwsA(isA<DioException>()),
    );
    expect(await f.core.worlds.sourceMaterials(f.assistant.id), hasLength(1));
  });

  testWidgets('世界设定页面能新增真实条目并重读显示', (tester) async {
    final f = (await tester.runAsync(fixture))!;
    OpenCoreBinding.attach(f.core);
    Future<void> drain() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      MaterialApp(home: CommunityWorldPage(assistant: f.assistant)),
    );
    await drain();
    await tester.tap(find.byTooltip('新增条目'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '界面条目');
    await tester.enterText(find.byType(TextField).at(2), '界面正文');
    await tester.tap(find.text('保存'));
    await drain();
    await tester.pumpAndSettle();
    expect(find.text('界面条目'), findsOneWidget);
    expect(
      (await tester.runAsync(
        () => f.core.worlds.categories(f.assistant.id),
      ))!.single.count,
      1,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
