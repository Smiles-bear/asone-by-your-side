import 'dart:io';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/community_chat_context_compiler.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PublicCore 重开后保留 API 配置、助手、会话和基础消息', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('public-core-');
    final database = CoreDatabase.forTesting(
      databaseFactory: databaseFactoryFfi,
      supportDirectoryProvider: () async => root,
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final first = PublicCore(
      database: database,
      fallback: DemoCore.withDemoSeed(),
    );
    await first.open();
    final service = await first.modelServices.createModelService({
      'name': '本地 API',
      'base_url': 'https://api.example.com/v1',
      'api_key': 'test-secret',
      'model': 'test-model',
      'protocol_type': ProtocolType.openaiChat,
    });
    final assistant = await first.assistants.createAssistant(name: '社区助手');
    final conversation = await first.conversations.createConversation(
      '持久化测试',
      assistantId: assistant.id,
    );
    await first.messages.saveMessage(conversation.id, 'user', '你好');
    await database.close();

    final reopened = PublicCore(
      database: database,
      fallback: DemoCore.withDemoSeed(),
    );
    await reopened.open();
    final conversations = await reopened.conversations.getConversations();
    final messages = await reopened.messages.getMessages(conversation.id);
    final services = await reopened.modelServices.getModelServices();

    expect(services.single.id, service.id);
    expect(services.single.apiKey, 'test-secret');
    expect(conversations.any((item) => item.id == conversation.id), isTrue);
    expect(messages.single.content, '你好');
    expect(messages.single.role, MessageRole.user);
  });

  test('社区聊天上下文只包含本对话基础文本且禁用工具', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('community-context-');
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
    final service = await core.modelServices.createModelService({
      'name': '社区 API',
      'base_url': 'https://api.example.com/v1',
      'api_key': 'test-secret',
      'model': 'test-model',
      'protocol_type': ProtocolType.openaiChat,
    });
    final assistant = await core.ensureAssistantForService(service);
    final conversation = await core.conversations.createConversation(
      '上下文测试',
      assistantId: assistant.id,
    );
    await core.messages.saveMessage(conversation.id, 'user', '只保留这条文本');

    final turn = await CommunityChatContextCompiler(
      repository: core.repository,
    ).compileTurnContext(conversationId: conversation.id, query: '测试');

    expect(turn.assistantId, assistant.id);
    expect(turn.modelSnapshot.modelServiceId, service.id);
    expect(turn.context['tools_enabled'], isFalse);
    expect(turn.context['all_system_parts'], isEmpty);
    final history = turn.context['all_recent_messages'] as List;
    expect(history, hasLength(1));
    expect((history.single as Map)['content'], '只保留这条文本');
  });
}
