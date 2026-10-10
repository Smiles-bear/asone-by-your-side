import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/services/provider_adapters/adapter_helpers.dart';
import 'package:azruiyoi_community/services/provider_adapters/incremental_sse_decoder.dart';
import 'package:azruiyoi_community/services/provider_adapters/openai_chat_adapter.dart';
import 'package:azruiyoi_community/services/provider_adapters/protocol_client.dart';
import 'package:azruiyoi_community/services/user_facing_error_policy.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ScriptedChatAdapter implements HttpClientAdapter {
  _ScriptedChatAdapter(this.responses);
  final List<String> responses;
  final requests = <Map<String, Object?>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(Map<String, Object?>.from(options.data as Map));
    return ResponseBody.fromString(
      responses[(requests.length - 1).clamp(0, responses.length - 1)],
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _stream({
  String text = '',
  String reasoning = '',
  String? finish = 'stop',
}) {
  final frames = [
    {
      'choices': [
        {
          'delta': {'content': text, 'reasoning_content': reasoning},
        },
      ],
    },
    if (finish != null)
      {
        'choices': [
          {'delta': <String, Object?>{}, 'finish_reason': finish},
        ],
      },
  ];
  return '${frames.map((frame) => 'data: ${jsonEncode(frame)}\n\n').join()}'
      'data: [DONE]\n\n';
}

Future<
  ({
    PublicCore core,
    CoreDatabase database,
    String conversationId,
    _ScriptedChatAdapter adapter,
  })
>
_openChat(
  List<String> responses, {
  String providerId = 'openai',
  String model = 'test-model',
}) async {
  final root = await Directory.systemTemp.createTemp('community-sync-');
  final database = CoreDatabase.forTesting(
    databaseFactory: databaseFactoryFfi,
    supportDirectoryProvider: () async => root,
  );
  final adapter = _ScriptedChatAdapter(responses);
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() async {
    dio.close(force: true);
    await database.close();
    await root.delete(recursive: true);
  });
  final core = PublicCore(database: database, chatDio: dio);
  await core.open();
  final service = await core.modelServices.createModelService({
    'name': '回归服务',
    'base_url': 'https://api.example.test/v1',
    'api_key': 'test-key',
    'model': model,
    'provider_id': providerId,
    'protocol_type': ProtocolType.openaiChat,
  });
  final assistant = await core.ensureAssistantForService(service);
  final conversation = await core.conversations.createConversation(
    '回归对话',
    assistantId: assistant.id,
  );
  return (
    core: core,
    database: database,
    conversationId: conversation.id,
    adapter: adapter,
  );
}

Future<String?> _send(
  PublicCore core,
  String conversationId, {
  void Function(String)? onDelta,
}) async {
  String? failure;
  await core.chat.send(
    conversationId: conversationId,
    content: '请回复',
    userAlreadyPersisted: false,
    onDelta: onDelta ?? (_) {},
    onDone: ({String? error}) => failure = error,
  );
  return failure;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('社区实际聊天累计全文只展示和持久化一次', () async {
    final fixture = await _openChat([
      'data: {"choices":[{"message":{"content":"第一段"}}]}\n\n'
          'data: {"choices":[{"message":{"content":"第一段第二段"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
    ]);
    final deltas = StringBuffer();
    expect(
      await _send(fixture.core, fixture.conversationId, onDelta: deltas.write),
      isNull,
    );
    expect(deltas.toString(), '第一段第二段');
    final messages = await fixture.core.messages.getMessages(
      fixture.conversationId,
    );
    expect(messages.last.content, '第一段第二段');
    expect(messages.last.answerStatus, MessageAnswerStatus.completed);
  });

  for (final shape in ['partial', 'reasoning', 'empty']) {
    test('输出上限 $shape 保留正确提示并在重开数据库后仍为失败', () async {
      final text = shape == 'partial' ? '已经收到的正文' : '';
      final fixture = await _openChat(
        [
          _stream(
            text: text,
            reasoning: shape == 'reasoning' ? '思考内容' : '',
            finish: 'length',
          ),
        ],
        providerId: 'deepseek',
        model: 'deepseek-flash',
      );
      final error = await _send(fixture.core, fixture.conversationId);
      expect(error, contains('finish_reason:length'));
      expect(fixture.adapter.requests, hasLength(1));
      final hint = switch (shape) {
        'partial' => UserFacingErrorPolicy.outputLengthLimited,
        'reasoning' => UserFacingErrorPolicy.reasoningLengthLimited,
        _ => UserFacingErrorPolicy.outputLengthWithoutBody,
      };
      expect(UserFacingErrorPolicy.failureHintFor(error), hint);
      await fixture.database.close();
      final database = await fixture.database.open();
      final stored = await database.query(
        'messages',
        where: 'conversation_id = ? AND role = ?',
        whereArgs: [fixture.conversationId, 'assistant'],
      );
      expect(stored, hasLength(1));
      expect(stored.single['content'], text);
      expect(stored.single['answer_status'], 'failed');
      expect(stored.single['failure_hint'], hint);
    });
  }

  test('DeepSeek 正常结束但仅有思考时恢复一次，保留成功正文', () async {
    final fixture = await _openChat(
      [_stream(reasoning: '第一次思考'), _stream(text: '恢复后的正文')],
      providerId: 'deepseek',
      model: 'deepseek-flash',
    );
    expect(await _send(fixture.core, fixture.conversationId), isNull);
    expect(fixture.adapter.requests, hasLength(2));
    expect(fixture.adapter.requests.first.containsKey('thinking'), isFalse);
    expect(fixture.adapter.requests.last['thinking'], {'type': 'disabled'});
    final messages = await fixture.core.messages.getMessages(
      fixture.conversationId,
    );
    expect(messages.last.content, '恢复后的正文');
    expect(messages.last.reasoning, isNot(contains('第一次思考')));
  });

  for (final finish in [null, 'content_filter']) {
    test('DeepSeek 未确认正常结束 $finish 时不自动恢复', () async {
      final fixture = await _openChat([
        _stream(reasoning: '思考内容', finish: finish),
      ], providerId: 'deepseek');
      expect(await _send(fixture.core, fixture.conversationId), isNotNull);
      expect(fixture.adapter.requests, hasLength(1));
    });
  }

  test('自定义服务不会仅因模型名是 DeepSeek 就应用原生恢复参数', () {
    expect(
      reasoningOnlyRecoveryPayload(
        providerId: 'custom',
        modelId: 'deepseek-flash',
        protocolType: ProtocolType.openaiChat,
      ),
      isEmpty,
    );
    expect(
      reasoningOnlyRecoveryPayload(
        providerId: 'deepseek',
        modelId: 'future-name',
        protocolType: ProtocolType.openaiChat,
      ),
      {
        'thinking': {'type': 'disabled'},
      },
    );
    expect(
      reasoningOnlyRecoveryPayload(
        providerId: 'deepseek',
        modelId: 'deepseek-flash',
        protocolType: ProtocolType.gemini,
      ),
      isEmpty,
    );
  });

  test('SSE 的 DONE 保留正常终态和最后一帧正文', () async {
    final adapter = OpenAIChatAdapter();
    final result = await decodeIncrementalSse(
      adapter: adapter,
      stream: Stream.value(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"最后一段"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
        ),
      ),
    );
    expect(result.receivedDone, isTrue);
    expect(result.terminal.reason, 'finish_reason:stop');
    expect(adapter.streamTextChunkFromFrame(result.frames.single).text, '最后一段');
  });

  test('端点成功后复用，配置变化独立探测，缓存端点404后重新发现', () async {
    final paths = <String>[];
    var changedRoute = false;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            paths.add(request.path);
            final isVersioned = request.path.contains('/v1/');
            if (isVersioned != changedRoute) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  response: Response(
                    requestOptions: request,
                    statusCode: 404,
                    data: {
                      'error': {'message': 'missing'},
                    },
                  ),
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: {
                    'choices': [
                      {
                        'message': {'content': 'OK'},
                      },
                    ],
                  },
                ),
              );
            }
          },
        ),
      );
    addTearDown(() => dio.close(force: true));
    Future<void> send({
      String model = 'test-model',
      String scope = '',
      String key = 'test-key',
      String? routeHeader,
    }) async {
      final result = await ProtocolClient(dio: dio, configurationScope: scope)
          .completeWithPayload(
            adapter: OpenAIChatAdapter(),
            baseUrl: 'https://api.example.test',
            apiKey: key,
            modelId: model,
            payload: {'model': model, 'messages': <Object>[]},
            requestHeaders: {
              'Idempotency-Key': '${paths.length}',
              if (routeHeader != null) 'X-Route': routeHeader,
            },
          );
      expect(result.success, isTrue);
    }

    await send();
    expect(paths, hasLength(2));
    await send();
    expect(paths, hasLength(3));
    expect(paths.last, paths[1]);
    for (final change in ['model', 'scope', 'key', 'header']) {
      final before = paths.length;
      await send(
        model: change == 'model' ? 'other-model' : 'test-model',
        scope: change == 'scope' ? 'other-service' : '',
        key: change == 'key' ? 'other-key' : 'test-key',
        routeHeader: change == 'header' ? 'other-route' : null,
      );
      expect(paths.length, before + 2);
    }
    changedRoute = true;
    final before = paths.length;
    await send();
    expect(paths.length, before + 2);
    expect(paths.last, contains('/v1/'));
    await send();
    expect(paths.length, before + 3);
  });
}
