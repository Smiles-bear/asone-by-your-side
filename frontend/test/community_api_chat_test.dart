import 'dart:io';
import 'dart:typed_data';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/services/provider_adapters/adapter_helpers.dart';
import 'package:azruiyoi_community/services/provider_adapters/model_protocol_adapter.dart';
import 'package:azruiyoi_community/services/provider_adapters/openai_chat_adapter.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SseAdapter implements HttpClientAdapter {
  _SseAdapter(this.body);

  final String body;
  Object? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options.data;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('社区聊天通过 OpenAI 兼容协议持久化真实流式回复', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('community-api-chat-');
    final database = CoreDatabase.forTesting(
      databaseFactory: databaseFactoryFfi,
      supportDirectoryProvider: () async => root,
    );
    final adapter = _SseAdapter(
      'data: {"choices":[{"delta":{"content":"来自 API 的回复"}}]}\n\n'
      'data: [DONE]\n\n',
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final core = PublicCore(
      database: database,
      fallback: DemoCore.withDemoSeed(),
      chatDio: Dio()..httpClientAdapter = adapter,
    );
    await core.open();
    final service = await core.modelServices.createModelService({
      'name': '本地 OpenAI 兼容服务',
      'base_url': 'https://api.example.test/v1',
      'api_key': 'test-key',
      'model': 'test-model',
      'protocol_type': ProtocolType.openaiChat,
    });
    final assistant = await core.ensureAssistantForService(service);
    final conversation = await core.conversations.createConversation(
      '真实协议回归',
      assistantId: assistant.id,
    );
    String? completionError;

    await core.chat.send(
      conversationId: conversation.id,
      content: '你好，API',
      userAlreadyPersisted: false,
      onDelta: (_) {},
      onDone: ({String? error}) => completionError = error,
    );

    expect(completionError, isNull);
    expect(adapter.request, isA<Map>());
    expect(adapter.request.toString(), contains('你好，API'));
    final messages = await core.messages.getMessages(conversation.id);
    expect(messages.map((message) => message.content), [
      '你好，API',
      '来自 API 的回复',
    ]);
    expect(messages.last.answerStatus, MessageAnswerStatus.completed);
  });

  test('社区 API 兼容累计全文流不会重复拼接', () {
    final adapter = OpenAIChatAdapter();
    final accumulator = ProviderStreamTextAccumulator();
    final first = adapter.streamTextChunkFromFrame(
      const SseFrame(
        data: {
          'choices': [
            {
              'message': {'content': '第一段'},
            },
          ],
        },
      ),
    );
    final second = adapter.streamTextChunkFromFrame(
      const SseFrame(
        data: {
          'choices': [
            {
              'message': {'content': '第一段第二段'},
            },
          ],
        },
      ),
    );

    expect(accumulator.add(first), '第一段');
    expect(accumulator.add(second), '第二段');
    expect(accumulator.text, '第一段第二段');
  });
}
