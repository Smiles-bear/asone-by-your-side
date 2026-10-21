import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:azruiyoi_community/services/provider_adapters/adapter_helpers.dart';
import 'package:azruiyoi_community/services/provider_adapters/adapter_registry.dart';
import 'package:azruiyoi_community/services/provider_adapters/adapter_types.dart';
import 'package:azruiyoi_community/services/provider_adapters/incremental_sse_decoder.dart';
import 'package:azruiyoi_community/services/provider_adapters/protocol_types.dart';
import 'package:azruiyoi_community/services/provider_adapters/provider_response_aggregation.dart';
import 'package:azruiyoi_community/services/provider_adapters/tool_argument_parser.dart';

void main() {
  final registry = AdapterRegistry.instance;
  for (final protocol in ProtocolType.allProtocols) {
    test(
      '$protocol native JSON and byte-split SSE have identical results',
      () async {
        final adapter = registry.get(protocol);
        final payload = _native(protocol);
        final jsonAggregate = ProviderResultAggregator(adapter: adapter);
        final native = await decodeIncrementalSse(
          adapter: adapter,
          stream: Stream.fromIterable(
            utf8.encode('\ufeff ${jsonEncode(payload)}').map((b) => [b]),
          ),
          onFrame: jsonAggregate.addFrame,
        );
        final fromJson = jsonAggregate.finish(terminal: native.terminal);
        final sseAggregate = ProviderResultAggregator(adapter: adapter);
        final sse = await decodeIncrementalSse(
          adapter: adapter,
          stream: Stream.fromIterable(
            utf8
                .encode(
                  'data: ${jsonEncode(payload)}\r\n\r\ndata: [DONE]\r\n\r\n',
                )
                .map((b) => [b]),
          ),
          onFrame: sseAggregate.addFrame,
        );
        final fromSse = sseAggregate.finish(terminal: sse.terminal);
        expect(fromJson.text, '回答');
        expect(fromJson.reasoning, '思考');
        expect(fromJson.terminalState, ProviderTerminalState.toolRequired);
        expect(fromJson.canDispatchTools, isTrue);
        expect(fromJson.toolCalls.single.arguments, isEmpty);
        expect(fromJson.nativeContinuation, fromSse.nativeContinuation);
        expect(fromJson.usage, fromSse.usage);
        expect(fromJson.usage, containsPair('completion_tokens', 5));
        expect(fromJson.terminalState, fromSse.terminalState);
        expect(fromJson.parsingIssues, isEmpty);
        expect(
          fromJson.nativeContinuation.toString(),
          contains('opaque-synthetic-signature'),
        );
        final replay = adapter.textPayload('test-model', [
          {
            'role': 'assistant',
            'content': fromJson.text,
            '_provider_continuation': fromJson.nativeContinuation,
          },
          {
            'role': 'tool',
            'tool_call_id': fromJson.toolCalls.single.id,
            'tool_name': fromJson.toolCalls.single.name,
            'content': 'synthetic-success',
          },
        ]);
        expect(jsonEncode(replay), contains('opaque-synthetic-signature'));
        expect(jsonEncode(replay), contains('synthetic-success'));
      },
    );
  }

  test(
    'Chat delta and full message complete text, reasoning and tools once',
    () {
      final result = ProviderResultAggregator(
        adapter: registry.get(ProtocolType.openaiChat),
      );
      expect(
        result
            .addFrame(
              _chatDelta({
                'content': '回',
                'reasoning_content': '思',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call',
                    'function': {'name': 'lookup', 'arguments': '{'},
                  },
                ],
              }),
            )
            .textDelta,
        '回',
      );
      result.addFrame(
        _chatDelta({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '}'},
            },
          ],
        }),
      );
      final completion = result.addPayload(_native(ProtocolType.openaiChat));
      expect(completion.textDelta, '答');
      expect(completion.reasoningDelta, '考');
      expect(
        result.addPayload(_native(ProtocolType.openaiChat)).textDelta,
        isEmpty,
      );
      final response = result.finish();
      expect(response.text, '回答');
      expect(response.toolCalls, hasLength(1));
      expect(
        (response.nativeContinuation!['items'] as List).single['tool_calls'],
        hasLength(1),
      );
    },
  );

  test('Chat cumulative rewrite is a conflict and never dispatches tools', () {
    final result = ProviderResultAggregator(
      adapter: registry.get(ProtocolType.openaiChat),
    );
    result.addFrame(_chatDelta({'content': '已展示'}));
    result.addPayload(_native(ProtocolType.openaiChat));
    final response = result.finish();
    expect(response.text, '已展示');
    expect(response.terminalState, ProviderTerminalState.failed);
    expect(response.parsingIssues, contains('content_snapshot_conflict'));
    expect(response.toolCalls, isEmpty);
  });

  test('Chat opaque reasoning details merge by index and replay once', () {
    final result = ProviderResultAggregator(
      adapter: registry.get(ProtocolType.openaiChat),
    );
    result.addFrame(
      _chatDelta({
        'reasoning_details': [
          {'index': 0, 'type': 'reasoning.encrypted', 'data': 'opaque-'},
        ],
      }),
    );
    result.addFrame(
      _chatDelta({
        'reasoning_details': [
          {'index': 0, 'type': 'reasoning.encrypted', 'data': 'signature'},
        ],
      }),
    );
    result.addPayload({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {
            'content': 'done',
            'reasoning_details': [
              {
                'index': 0,
                'type': 'reasoning.encrypted',
                'data': 'opaque-signature',
              },
            ],
          },
        },
      ],
    });
    final response = result.finish();
    final details =
        (response.nativeContinuation!['items'] as List)
                .single['reasoning_details']
            as List;
    expect(details, hasLength(1));
    expect(details.single['data'], 'opaque-signature');
    expect(response.parsingIssues, isEmpty);
  });

  test(
    'Responses preserves identical text in distinct items and fills snapshots',
    () {
      final adapter = registry.get(ProtocolType.openaiResponses);
      final result = ProviderResultAggregator(adapter: adapter);
      final first = _responseMessage('m0', '同');
      result.addFrame(
        _event('response.output_item.added', {
          'output_index': 0,
          'item': {...first, 'content': []},
        }),
      );
      result.addFrame(
        _event('response.output_text.delta', {
          'item_id': 'm0',
          'output_index': 0,
          'content_index': 0,
          'delta': '同',
        }),
      );
      expect(
        result
            .addFrame(
              _event('response.output_text.done', {
                'item_id': 'm0',
                'output_index': 0,
                'content_index': 0,
                'text': '同',
              }),
            )
            .textDelta,
        '',
      );
      expect(
        result
            .addFrame(
              _event('response.completed', {
                'response': {
                  'status': 'completed',
                  'output': [first, _responseMessage('m1', '同')],
                },
              }),
            )
            .textDelta,
        '同',
      );
      final response = result.finish();
      expect(response.text, '同同');
      expect(response.terminalState, ProviderTerminalState.completed);
      expect(response.nativeContinuation!['items'], hasLength(2));
    },
  );

  test(
    'Responses partial arguments + done + completed preserve a single call',
    () {
      final result = ProviderResultAggregator(
        adapter: registry.get(ProtocolType.openaiResponses),
      );
      result.addFrame(
        _event('response.output_item.added', {
          'output_index': 0,
          'item': {
            'type': 'function_call',
            'id': 'item',
            'call_id': 'call',
            'name': 'lookup',
            'arguments': '',
          },
        }),
      );
      result.addFrame(
        _event('response.function_call_arguments.delta', {
          'item_id': 'item',
          'output_index': 0,
          'delta': '{"q":',
        }),
      );
      result.addFrame(
        _event('response.function_call_arguments.done', {
          'item_id': 'item',
          'output_index': 0,
          'arguments': '{"q":1}',
        }),
      );
      result.addFrame(
        _event('response.completed', {
          'response': {
            'status': 'completed',
            'output': [
              {
                'type': 'function_call',
                'id': 'item',
                'call_id': 'call',
                'name': 'lookup',
                'arguments': '{"q":1}',
              },
            ],
          },
        }),
      );
      final response = result.finish();
      expect(response.toolCalls.single.arguments, {'q': 1});
      expect(response.nativeContinuation!['items'], hasLength(1));
      expect(response.canDispatchTools, isTrue);
    },
  );

  test('Responses arguments snapshot cannot overwrite conflicting deltas', () {
    final result = ProviderResultAggregator(
      adapter: registry.get(ProtocolType.openaiResponses),
    );
    result.addFrame(
      _event('response.output_item.added', {
        'output_index': 0,
        'item': {
          'type': 'function_call',
          'id': 'item',
          'call_id': 'call',
          'name': 'lookup',
        },
      }),
    );
    result.addFrame(
      _event('response.function_call_arguments.delta', {
        'item_id': 'item',
        'delta': '{"q":1}',
      }),
    );
    result.addFrame(
      _event('response.function_call_arguments.done', {
        'item_id': 'item',
        'arguments': '{"q":2}',
      }),
    );
    result.addFrame(_event('response.completed', {}));
    final response = result.finish();
    expect(response.toolCalls, isEmpty);
    expect(
      response.toolReceptions.single.state,
      ProviderToolArgumentState.conflict,
    );
  });

  test('Anthropic truncation preserves root cause, input and output usage', () {
    final result = ProviderResultAggregator(
      adapter: registry.get(ProtocolType.anthropicMessages),
    );
    result.addFrame(
      _event('message_start', {
        'message': {
          'usage': {'input_tokens': 23},
        },
      }),
    );
    result.addFrame(
      _event('content_block_start', {
        'index': 4,
        'content_block': {
          'type': 'tool_use',
          'id': 'call',
          'name': 'lookup',
          'input': {},
        },
      }),
    );
    result.addFrame(
      _event('content_block_delta', {
        'index': 4,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"q":'},
      }),
    );
    result.addFrame(
      _event('message_delta', {
        'delta': {'stop_reason': 'max_tokens'},
        'usage': {'output_tokens': 5},
      }),
    );
    result.addFrame(_event('message_stop', {}));
    final response = result.finish(
      terminal: const ProviderStreamTerminal.success('[DONE]'),
    );
    expect(response.terminalState, ProviderTerminalState.truncated);
    expect(response.finishReason, 'stop_reason:max_tokens');
    expect(response.usage, containsPair('prompt_tokens', 23));
    expect(response.usage, containsPair('completion_tokens', 5));
    expect(
      response.toolReceptions.single.state,
      ProviderToolArgumentState.incomplete,
    );
    expect(response.toolCalls, isEmpty);
    expect(
      (response.nativeContinuation!['items'] as List).single['input'],
      '{"q":',
    );
  });

  test(
    'Anthropic uses global block indexes for thinking signatures and tools',
    () {
      final result = ProviderResultAggregator(
        adapter: registry.get(ProtocolType.anthropicMessages),
      );
      result.addFrame(
        _event('content_block_start', {
          'index': 0,
          'content_block': {'type': 'thinking', 'thinking': ''},
        }),
      );
      result.addFrame(
        _event('content_block_delta', {
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': '思考'},
        }),
      );
      result.addFrame(
        _event('content_block_delta', {
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'opaque-'},
        }),
      );
      result.addFrame(
        _event('content_block_delta', {
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'signature'},
        }),
      );
      result.addFrame(
        _event('content_block_start', {
          'index': 2,
          'content_block': {
            'type': 'tool_use',
            'id': 'call',
            'name': 'lookup',
            'input': {},
          },
        }),
      );
      result.addFrame(
        _event('content_block_delta', {
          'index': 2,
          'delta': {'type': 'input_json_delta', 'partial_json': '{}'},
        }),
      );
      result.addFrame(_event('content_block_stop', {'index': 2}));
      result.addFrame(
        _event('message_delta', {
          'delta': {'stop_reason': 'tool_use'},
        }),
      );
      final response = result.finish();
      expect(response.reasoning, '思考');
      expect(response.canDispatchTools, isTrue);
      final items = response.nativeContinuation!['items'] as List;
      expect(items[0]['signature'], 'opaque-signature');
      expect(items[1]['id'], 'call');
      expect(items[1]['input'], isEmpty);
    },
  );

  test('Anthropic explicit stop_reason works with omitted message type', () {
    final payload = _native(ProtocolType.anthropicMessages)..remove('type');
    final response = aggregateProviderPayload(
      registry.get(ProtocolType.anthropicMessages),
      payload,
    );
    expect(response.canDispatchTools, isTrue);
    payload.remove('stop_reason');
    final missing = aggregateProviderPayload(
      registry.get(ProtocolType.anthropicMessages),
      payload,
    );
    expect(missing.canDispatchTools, isFalse);
    expect(missing.toolCalls, isEmpty);
  });

  test('unsigned Anthropic thinking cannot authorize a tool round', () {
    final payload = _native(ProtocolType.anthropicMessages);
    ((payload['content'] as List).first as Map).remove('signature');
    final response = aggregateProviderPayload(
      registry.get(ProtocolType.anthropicMessages),
      payload,
    );
    expect(response.toolCalls, isEmpty);
    expect(response.parsingIssues, contains('missing_thinking_signature'));
    expect(response.text, '回答');
  });

  test(
    'duplicate Gemini ID with conflicting opaque signatures blocks the round',
    () {
      final response = aggregateProviderPayload(
        registry.get(ProtocolType.gemini),
        {
          'candidates': [
            {
              'finishReason': 'STOP',
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'id': 'same',
                      'name': 'lookup',
                      'args': {},
                    },
                    'thoughtSignature': 'one',
                  },
                  {
                    'functionCall': {
                      'id': 'same',
                      'name': 'lookup',
                      'args': {},
                    },
                    'thoughtSignature': 'two',
                  },
                ],
              },
            },
          ],
        },
      );
      expect(response.toolCalls, isEmpty);
      expect(response.parsingIssues, contains('duplicate_tool_id_conflict'));
    },
  );

  for (final reason in ['max_output_tokens', 'content_filter']) {
    test('nested Responses $reason survives later completion and usage', () {
      final result = ProviderResultAggregator(
        adapter: registry.get(ProtocolType.openaiResponses),
      );
      result.addFrame(
        _event('response.incomplete', {
          'response': {
            'status': 'incomplete',
            'incomplete_details': {'reason': reason},
            'usage': {'input_tokens': 13, 'output_tokens': 5},
            'output': [_responseMessage('msg', '部分内容')],
          },
        }),
      );
      result.addFrame(
        _event('response.completed', {
          'response': {
            'status': 'completed',
            'usage': {'input_tokens': 13, 'output_tokens': 5},
          },
        }),
      );
      final response = result.finish();
      expect(response.finishReason, contains(reason));
      expect(
        response.terminalState,
        reason == 'max_output_tokens'
            ? ProviderTerminalState.truncated
            : ProviderTerminalState.refused,
      );
      expect(response.usage, containsPair('prompt_tokens', 13));
      expect(response.usage, containsPair('completion_tokens', 5));
      expect(response.text, '部分内容');
      expect(response.toolCalls, isEmpty);
    });
  }

  test(
    'Gemini no-ID concurrent same-name calls keep local association off wire',
    () {
      final adapter = registry.get(ProtocolType.gemini);
      final response = aggregateProviderPayload(adapter, {
        'candidates': [
          {
            'finishReason': 'STOP',
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'name': 'lookup',
                    'args': {'q': 1},
                  },
                  'thoughtSignature': 'signed-one',
                },
                {
                  'functionCall': {
                    'name': 'lookup',
                    'args': {'q': 2},
                  },
                  'thoughtSignature': 'signed-two',
                },
              ],
            },
          },
        ],
      });
      expect(response.toolCalls, hasLength(2));
      expect(response.toolCalls[0].id, isNot(response.toolCalls[1].id));
      expect(response.toolCalls.every((call) => call.nativeId == null), isTrue);
      final replay = adapter.textPayload('test', [
        {
          'role': 'assistant',
          '_provider_continuation': response.nativeContinuation,
        },
        for (final call in response.toolCalls)
          {
            'role': 'tool',
            'tool_call_id': call.id,
            'content': 'synthetic-success',
          },
      ]);
      final contents = replay['contents'] as List;
      final responses = [
        contents[1]['parts'][0]['functionResponse'],
        contents[2]['parts'][0]['functionResponse'],
      ];
      expect(
        responses.every(
          (value) => value['name'] == 'lookup' && !value.containsKey('id'),
        ),
        isTrue,
      );
      expect(jsonEncode(replay), isNot(contains('candidate:0:part:')));
      expect(jsonEncode(replay), contains('signed-one'));
      expect(jsonEncode(replay), contains('signed-two'));
    },
  );

  for (final conflict in [false, true]) {
    test(
      'duplicate native ID ${conflict ? 'conflict blocks the round' : 'merges once'}',
      () {
        final response = aggregateProviderPayload(
          registry.get(ProtocolType.gemini),
          {
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {
                      'functionCall': {
                        'id': 'same',
                        'name': 'lookup',
                        'args': {'q': 1},
                      },
                    },
                    {
                      'functionCall': {
                        'id': 'same',
                        'name': 'lookup',
                        'args': {'q': conflict ? 2 : 1},
                      },
                    },
                  ],
                },
              },
            ],
          },
        );
        expect(response.toolCalls, hasLength(conflict ? 0 : 1));
        expect(response.canDispatchTools, !conflict);
        if (conflict) {
          expect(
            response.parsingIssues,
            contains('duplicate_tool_id_conflict'),
          );
        } else {
          expect(response.nativeContinuation!['items'], hasLength(1));
        }
      },
    );
  }

  for (final raw in ['{"q":', '[1]', 'null', null, '{"q":1,"q":2}']) {
    test(
      'one malformed tool $raw closes the entire round without erasing text',
      () {
        final payload = _native(ProtocolType.openaiChat);
        final message = (payload['choices'] as List).first['message'] as Map;
        (message['tool_calls'] as List).add({
          'id': 'bad',
          'type': 'function',
          'function': {'name': 'lookup', 'arguments': raw},
        });
        final response = aggregateProviderPayload(
          registry.get(ProtocolType.openaiChat),
          payload,
        );
        expect(response.toolCalls, isEmpty);
        expect(response.canDispatchTools, isFalse);
        expect(response.toolReceptions, hasLength(2));
        expect(
          response.toolReceptions.first.state,
          ProviderToolArgumentState.valid,
        );
        expect(
          response.toolReceptions.last.state,
          isNot(ProviderToolArgumentState.valid),
        );
        expect(response.text, '回答');
      },
    );
  }

  for (final terminal in [
    const ProviderStreamTerminal.failure('cancelled'),
    const ProviderStreamTerminal.failure('finish_reason:length'),
    const ProviderStreamTerminal.failure('upstream_error:quota_exceeded'),
  ]) {
    test('late ${terminal.reason} blocks even a fully received tool', () {
      final result = ProviderResultAggregator(
        adapter: registry.get(ProtocolType.openaiChat),
      );
      result.addPayload(_native(ProtocolType.openaiChat));
      final response = result.finish(terminal: terminal);
      expect(response.toolCalls, isEmpty);
      expect(response.finishReason, terminal.reason);
      expect(response.usage, containsPair('completion_tokens', 5));
      expect(response.text, '回答');
    });
  }

  test(
    'strict JSON accepts equal duplicate values and rejects conflicting keys',
    () {
      expect(decodeStrictProviderJson('{"x":{"q":1},"x":{"q":1}}'), {
        'x': {'q': 1},
      });
      for (final source in ['{"x":1,"x":2}', '{"x":', '{"x":"unterminated']) {
        expect(
          () => decodeStrictProviderJson(source),
          throwsA(
            isA<FormatException>().having(
              (error) => error.source,
              'redacted',
              isNull,
            ),
          ),
        );
      }
    },
  );

  test(
    'cancel checks run while response is silent and cancel the upstream',
    () async {
      final cancelled = Completer<void>();
      var shouldCancel = false;
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled.complete(),
      );
      final result = decodeIncrementalSse(
        adapter: registry.get(ProtocolType.openaiChat),
        stream: stream.stream,
        checkCancelled: () {
          if (shouldCancel) throw StateError('synthetic-cancel');
        },
        policy: const IncrementalSsePolicy(
          cancellationPollInterval: Duration(milliseconds: 5),
        ),
      );
      final expectation = expectLater(result, throwsStateError);
      shouldCancel = true;
      await expectation.timeout(const Duration(seconds: 1));
      await cancelled.future.timeout(const Duration(seconds: 1));
      await stream.close();
    },
  );

  test(
    'failed terminal drains bounded usage trailer without losing its root',
    () async {
      final adapter = registry.get(ProtocolType.openaiChat);
      final aggregate = ProviderResultAggregator(adapter: adapter);
      final decoded = await decodeIncrementalSse(
        adapter: adapter,
        stream: Stream.fromIterable([
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"部分"},"finish_reason":"length"}]}\n\n',
          ),
          utf8.encode(
            'data: {"choices":[],"usage":{"completion_tokens":9}}\n\n',
          ),
          utf8.encode('data: [DONE]\n\n'),
        ]),
        onFrame: aggregate.addFrame,
      );
      final response = aggregate.finish(terminal: decoded.terminal);
      expect(response.terminalState, ProviderTerminalState.truncated);
      expect(response.finishReason, 'finish_reason:length');
      expect(response.usage, containsPair('completion_tokens', 9));
      expect(response.text, '部分');
    },
  );

  test(
    'framing rejects mismatched arrays, HTML and bounded oversized events',
    () async {
      final adapter = registry.get(ProtocolType.openaiChat);
      for (final body in [
        '<html>not a response</html>',
        '[{"choices":[]}]',
        'not json',
      ]) {
        await expectLater(
          decodeIncrementalSse(
            adapter: adapter,
            stream: Stream.value(utf8.encode(body)),
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        decodeIncrementalSse(
          adapter: adapter,
          stream: Stream.value(
            utf8.encode(
              'data: ${jsonEncode(_native(ProtocolType.openaiChat))}\n\n',
            ),
          ),
          policy: const IncrementalSsePolicy(maximumEventBytes: 10),
        ),
        throwsFormatException,
      );
    },
  );
}

SseFrame _event(String type, Map<String, Object?> values) =>
    SseFrame(eventType: type, data: {'type': type, ...values});
SseFrame _chatDelta(Map<String, Object?> delta) => SseFrame(
  data: {
    'choices': [
      {'delta': delta},
    ],
  },
);
Map<String, Object?> _responseMessage(String id, String text) => {
  'id': id,
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'output_text', 'text': text},
  ],
};

Map<String, Object?> _native(String protocol) => switch (protocol) {
  ProtocolType.openaiChat => {
    'model': 'test',
    'choices': [
      {
        'finish_reason': 'tool_calls',
        'message': {
          'role': 'assistant',
          'content': '回答',
          'reasoning_content': '思考',
          'reasoning_details': [
            {
              'type': 'reasoning.encrypted',
              'data': 'opaque-synthetic-signature',
            },
          ],
          'tool_calls': [
            {
              'id': 'call',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{}'},
            },
          ],
        },
      },
    ],
    'usage': {'prompt_tokens': 13, 'completion_tokens': 5},
  },
  ProtocolType.openaiResponses => {
    'object': 'response',
    'status': 'completed',
    'model': 'test',
    'output': [
      {
        'id': 'reasoning',
        'type': 'reasoning',
        'encrypted_content': 'opaque-synthetic-signature',
        'summary': [
          {'type': 'summary_text', 'text': '思考'},
        ],
      },
      _responseMessage('message', '回答'),
      {
        'id': 'item',
        'type': 'function_call',
        'call_id': 'call',
        'name': 'lookup',
        'arguments': '{}',
      },
    ],
    'usage': {'input_tokens': 13, 'output_tokens': 5},
  },
  ProtocolType.anthropicMessages => {
    'type': 'message',
    'stop_reason': 'tool_use',
    'model': 'test',
    'content': [
      {
        'type': 'thinking',
        'thinking': '思考',
        'signature': 'opaque-synthetic-signature',
      },
      {'type': 'text', 'text': '回答'},
      {'type': 'tool_use', 'id': 'call', 'name': 'lookup', 'input': {}},
    ],
    'usage': {'input_tokens': 13, 'output_tokens': 5},
  },
  ProtocolType.gemini => {
    'modelVersion': 'test',
    'candidates': [
      {
        'finishReason': 'STOP',
        'content': {
          'role': 'model',
          'parts': [
            {'text': '思考', 'thought': true},
            {'text': '回答'},
            {
              'functionCall': {'id': 'call', 'name': 'lookup', 'args': {}},
              'thoughtSignature': 'opaque-synthetic-signature',
            },
          ],
        },
      },
    ],
    'usageMetadata': {'promptTokenCount': 13, 'candidatesTokenCount': 5},
  },
  _ => throw StateError('unsupported test protocol'),
};
