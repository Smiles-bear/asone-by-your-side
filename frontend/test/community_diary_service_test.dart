import 'dart:io';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('社区日记只将近期基础文本写入日记表', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('community-diary-');
    final database = CoreDatabase.forTesting(
      databaseFactory: databaseFactoryFfi,
      supportDirectoryProvider: () async => root,
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final core = PublicCore(
      database: database,
      fallback: DemoCore.withDemoSeed(),
    );
    await core.open();
    final configuredService = await core.modelServices.createModelService({
      'name': '日记 API',
      'base_url': 'https://api.example.com/v1',
      'api_key': 'test-secret',
      'model': 'test-model',
      'protocol_type': ProtocolType.openaiChat,
    });
    final assistant = await core.ensureAssistantForService(configuredService);
    final conversation = await core.conversations.createConversation(
      '日记测试',
      assistantId: assistant.id,
    );
    await core.messages.saveMessage(conversation.id, 'user', '今天完成了社区版');
    await core.messages.saveMessage(conversation.id, 'assistant', '这是很好的进展');

    final entry = await core.diary.generate(
      conversationId: conversation.id,
      generator: ({required service, required messages}) async {
        expect(service.id, configuredService.id);
        expect(messages.map((message) => message['content']), [
          '今天完成了社区版',
          '这是很好的进展',
        ]);
        return {'title': '今日进展', 'content': '完成了社区版的基础功能。'};
      },
    );

    expect(entry.title, '今日进展');
    expect(entry.content, '完成了社区版的基础功能。');
    final saved = await core.diary.listForConversation(conversation.id);
    expect(saved.single.diaryId, entry.diaryId);
  });
}
