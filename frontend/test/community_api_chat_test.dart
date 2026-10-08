import 'dart:io';
import 'dart:typed_data';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/services/provider_adapters/adapter_helpers.dart';
import 'package:azruiyoi_community/services/model_endpoint.dart';
import 'package:azruiyoi_community/services/provider_adapters/gemini_adapter.dart';
import 'package:azruiyoi_community/services/provider_adapters/model_output_contract.dart';
import 'package:azruiyoi_community/services/provider_adapters/model_protocol_adapter.dart';
import 'package:azruiyoi_community/services/provider_adapters/openai_chat_adapter.dart';
import 'package:azruiyoi_community/services/provider_adapters/protocol_client.dart';
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

  test('社区 API 将 HTTP 402 归类为服务商额度异常', () {
    final error = normalizeHttpError(402, {
      'error': {'message': 'insufficient balance'},
    }, 'payment required');

    expect(error.code, 'ACCOUNT_BILLING');
    expect(error.message, '服务商账户、余额或额度异常');
  });

  test('Gemini 自定义地址会自动切换到原生 v1beta 端点', () {
    final adapter = GeminiAdapter();
    for (final baseUrl in [
      'https://relay.example',
      'https://relay.example/v1',
      'https://relay.example/proxy/v1',
    ]) {
      final expectedPrefix = baseUrl.contains('/proxy/')
          ? 'https://relay.example/proxy/v1beta'
          : 'https://relay.example/v1beta';
      expect(
        adapter.generateContentEndpoint(baseUrl, 'gemini-test'),
        '$expectedPrefix/models/gemini-test:generateContent',
      );
    }
    expect(
      protocolModelBaseUrl('https://relay.example/v1beta', ProtocolType.gemini),
      'https://relay.example/v1beta',
    );
  });

  test('Gemini Schema 保留数组项和字段说明，原生工具结果保留调用 ID', () {
    final adapter = GeminiAdapter();
    final payload = adapter.textPayload(
      'gemini-test',
      [
        {'role': 'user', 'content': 'query'},
        {
          'role': 'assistant',
          'content': '',
          '_provider_continuation': {
            'protocol': ProtocolType.gemini,
            'items': [
              {
                'functionCall': {
                  'id': 'native-7',
                  'name': 'query_note',
                  'args': {'keyword': 'blue'},
                },
                'thoughtSignature': 'opaque',
              },
            ],
          },
        },
        {
          'role': 'tool',
          'tool_call_id': 'native-7',
          'content': 'blue',
        },
      ],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'query_note',
            'description': '查询纸条',
            'parameters': {
              'type': 'object',
              'properties': {
                'items': {
                  'type': 'array',
                  'description': '关键词列表',
                  'items': {'type': 'string'},
                },
              },
            },
          },
        },
      ],
    );
    final contents = payload['contents'] as List;
    final response = ((contents.last as Map)['parts'] as List).single as Map;
    expect((response['functionResponse'] as Map)['id'], 'native-7');
    expect((response['functionResponse'] as Map)['name'], 'query_note');
    final functions = ((payload['tools'] as List).single
        as Map)['functionDeclarations'] as List;
    final properties = (functions.single as Map)['parameters']['properties'];
    expect(properties['items']['description'], '关键词列表');
    expect(properties['items']['items'], {'type': 'STRING'});
  });

  test('OpenRouter 直接结果使用 reasoning 对象，普通聊天保持默认', () {
    final direct = <String, Object?>{'reasoning_effort': 'low'};
    applyModelRequestPolicy(
      direct,
      baseUrl: 'https://openrouter.ai/api/v1',
      modelId: 'test-model',
      protocolType: ProtocolType.openaiChat,
      directResponse: true,
    );
    expect(direct, {
      'reasoning': {'effort': 'low'},
    });

    final chat = <String, Object?>{'reasoning_effort': 'low'};
    applyModelRequestPolicy(
      chat,
      baseUrl: 'https://openrouter.ai/api/v1',
      modelId: 'test-model',
      protocolType: ProtocolType.openaiChat,
      directResponse: false,
    );
    expect(chat, {'reasoning_effort': 'low'});
  });

  test('仅在网关明确拒绝结构化参数时降级为提示词 JSON', () {
    const contract = ModelOutputContract.structuredJson(
      schemaName: 'community_result',
      schema: {'type': 'object'},
    );
    const profile = ModelCapabilityProfile(
      structuredVerdict: 'supported',
      structuredTransport: StructuredOutputTransport.geminiSchema,
      textVerdict: 'supported',
    );
    ProtocolCallResult failed(String detail) => ProtocolCallResult(
      success: false,
      text: '',
      diagnosis: ProtocolDiagnosis(
        protocol: ProtocolType.gemini,
        endpoint: '',
        requestSent: true,
        elapsedMs: 1,
        statusCode: 503,
        detail: detail,
      ),
    );
    expect(
      canFallbackToPromptJson(
        failed('upstream status 400: JSON Schema 参数无效，需要 Build 通道'),
        transport: StructuredOutputTransport.geminiSchema,
        profile: profile,
        contract: contract,
      ),
      isTrue,
    );
    expect(
      canFallbackToPromptJson(
        failed('服务暂时不可用'),
        transport: StructuredOutputTransport.geminiSchema,
        profile: profile,
        contract: contract,
      ),
      isFalse,
    );
  });
}
