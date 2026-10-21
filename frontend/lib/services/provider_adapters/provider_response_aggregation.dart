import 'dart:convert';

import 'adapter_helpers.dart';
import 'adapter_types.dart';
import 'model_protocol_adapter.dart';
import 'protocol_types.dart';
import 'provider_usage.dart';
import 'response_framing.dart';
import 'tool_argument_parser.dart';

/// One response, one owner. Both streaming and JSON callers use this API.
/// No dispatch occurs here; only [ProviderResponse.toolCalls] is dispatchable.
class ProviderResultAggregator {
  ProviderResultAggregator({
    required this.adapter,
    this.maximumBytes = 32 * 1024 * 1024,
  }) : _usage = ProviderUsage(protocol: adapter.protocolType);

  final ModelProtocolAdapter adapter;
  final int maximumBytes;
  final ProviderUsage _usage;
  final _texts = <String, String>{};
  final _thoughts = <String, String>{};
  final _tools = <String, _ToolBuffer>{};
  final _items = <String, Map<String, Object?>>{};
  final _responseIds = <String, String>{};
  final _responseOrder = <String, int>{};
  final _issues = <String>{};
  final _chat = <String, Object?>{};
  final _chatDetails = <String, Map<String, Object?>>{};
  final _localToolIds = <String, String>{};
  ProviderStreamTerminal _terminal = const ProviderStreamTerminal.none();
  String _model = '';
  int _bytes = 0;
  int _geminiPart = 0;
  bool _sealed = false;

  String get text => _joinContent(_texts);
  String get reasoning => _joinContent(_thoughts);
  ProviderStreamTerminal get terminal => _terminal;

  String _joinContent(Map<String, String> parts) {
    final keys = parts.keys.toList();
    final originalOrder = {for (var i = 0; i < keys.length; i++) keys[i]: i};
    int position(String key) {
      for (final entry in _responseOrder.entries) {
        if (key.startsWith('${entry.key}:')) return entry.value;
      }
      if (key.startsWith('block:') || key.startsWith('output:')) {
        return int.tryParse(key.split(':')[1]) ?? 0;
      }
      return originalOrder[key]!;
    }

    keys.sort((a, b) {
      final outer = position(a).compareTo(position(b));
      if (outer != 0) return outer;
      final ai = int.tryParse(a.split(':').last);
      final bi = int.tryParse(b.split(':').last);
      return ai != null && bi != null ? ai.compareTo(bi) : 0;
    });
    return keys.map((key) => parts[key]!).join();
  }

  StreamEvent addPayload(Map payload) {
    if (!isProviderJsonPayload(adapter.protocolType, payload)) {
      _issues.add('incompatible_response_json');
      _accept(
        const ProviderStreamTerminal.failure('incompatible_response_json'),
      );
    }
    return addFrame(SseFrame(data: payload));
  }

  StreamEvent addFrame(SseFrame frame) {
    if (_sealed) throw StateError('provider_response_already_finished');
    _bytes += utf8.encode(jsonEncode(frame.data)).length;
    if (_bytes > maximumBytes) {
      _issues.add('aggregation_limit');
      _accept(const ProviderStreamTerminal.failure('aggregation_limit'));
      throw const FormatException('provider_aggregation_limit');
    }
    final beforeText = text;
    final beforeThought = reasoning;
    _usage.addPayload(frame.data);
    final nested = frame.data['response'] ?? frame.data['message'];
    final model =
        frame.data['model'] ??
        frame.data['modelVersion'] ??
        (nested is Map ? nested['model'] : null);
    if (model is String && model.isNotEmpty) _model = model;
    _accept(adapter.streamTerminalFromFrame(frame));
    switch (adapter.protocolType) {
      case ProtocolType.openaiChat:
        _addChat(frame.data);
      case ProtocolType.openaiResponses:
        _addResponses(frame);
      case ProtocolType.anthropicMessages:
        _addAnthropic(frame);
      case ProtocolType.gemini:
        _addGemini(frame.data);
      default:
        _issues.add('unsupported_protocol');
    }
    // An item received later can precede an existing item in native order.
    // Such protocols normally announce items before deltas; fail closed if an
    // upstream snapshot would rewrite already displayed text.
    final afterText = text;
    final afterThought = reasoning;
    if (!afterText.startsWith(beforeText)) {
      _issues.add('content_order_conflict');
    }
    if (!afterThought.startsWith(beforeThought)) {
      _issues.add('reasoning_order_conflict');
    }
    return StreamEvent(
      textDelta: afterText.startsWith(beforeText)
          ? afterText.substring(beforeText.length)
          : '',
      reasoningDelta: afterThought.startsWith(beforeThought)
          ? afterThought.substring(beforeThought.length)
          : '',
      usage: Map.unmodifiable(_usage.values),
      finishReason: _terminal.reason,
      resolvedModelId: _model,
    );
  }

  void _accept(ProviderStreamTerminal next) {
    if (!next.isTerminal || _terminal.isFailure) return;
    if (next.reason == '[DONE]' && _terminal.isTerminal) return;
    if (next.reason == 'message_stop' && _terminal.isTerminal) return;
    _terminal = next;
  }

  void _content(
    String key,
    Object? value, {
    bool snapshot = false,
    bool thought = false,
  }) {
    if (value is! String) return;
    final target = thought ? _thoughts : _texts;
    final old = target[key] ?? '';
    if (snapshot && !value.startsWith(old)) {
      _issues.add(
        thought ? 'reasoning_snapshot_conflict' : 'content_snapshot_conflict',
      );
      return;
    }
    target[key] = snapshot ? value : old + value;
  }

  _ToolBuffer _tool(
    String key,
    Map raw, {
    required bool snapshot,
    required String argumentsKey,
  }) {
    final tool = _tools.putIfAbsent(key, () => _ToolBuffer(key));
    tool.identify(
      raw['name'],
      adapter.protocolType == ProtocolType.openaiResponses
          ? raw['call_id']
          : raw['id'],
    );
    if (raw.containsKey(argumentsKey)) {
      tool.add(raw[argumentsKey], snapshot: snapshot);
    }
    return tool;
  }

  void _addChat(Map data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return;
    final choice = choices.first as Map;
    final message = choice['message'];
    final delta = choice['delta'];
    final snapshot = message is Map;
    final raw = snapshot ? message : delta;
    if (raw is! Map) {
      _content('chat', choice['text']);
      return;
    }
    if (raw.containsKey('content')) {
      _content('chat', contentText(raw['content']), snapshot: snapshot);
      if (snapshot && raw['content'] is! String) {
        _chat['content'] = raw['content'];
      }
    }
    for (final key in ['reasoning_content', 'reasoning', 'thinking']) {
      if (raw[key] is String) {
        _content('chat:$key', raw[key], snapshot: snapshot, thought: true);
        _chat[key] = _thoughts['chat:$key'];
      }
    }
    for (final entry in raw.entries) {
      if ([
        'content',
        'tool_calls',
        'function_call',
        'reasoning_content',
        'reasoning',
        'thinking',
      ].contains(entry.key)) {
        continue;
      }
      if (entry.key == 'reasoning_details' && entry.value is List) {
        _addChatDetails(entry.value as List, snapshot);
      } else {
        _chat[entry.key as String] = entry.value;
      }
    }
    final calls = raw['tool_calls'];
    if (calls is List) {
      for (var i = 0; i < calls.length; i++) {
        final call = calls[i];
        if (call is! Map) {
          _issues.add('unknown_tool_block');
          continue;
        }
        if (call['type'] != null && call['type'] != 'function') {
          _issues.add('unknown_tool_block');
          continue;
        }
        final function = call['function'];
        if (function is! Map) {
          _issues.add('invalid_tool_block');
          continue;
        }
        final index = call['index'] ?? (snapshot ? i : null);
        if (index == null) {
          _issues.add('missing_tool_index');
          continue;
        }
        _tool(
          'chat:$index',
          {...function, 'id': call['id']},
          snapshot: snapshot,
          argumentsKey: 'arguments',
        );
      }
    }
    final legacy = raw['function_call'];
    if (legacy is Map) {
      _tool(
        'chat:legacy',
        legacy,
        snapshot: snapshot,
        argumentsKey: 'arguments',
      );
    }
    final refusal = raw['refusal'];
    if (refusal is String && refusal.isNotEmpty) {
      _accept(const ProviderStreamTerminal.failure('refusal'));
    }
  }

  void _addChatDetails(List details, bool snapshot) {
    for (var i = 0; i < details.length; i++) {
      final detail = details[i];
      if (detail is! Map) {
        _issues.add('invalid_reasoning_details');
        continue;
      }
      final key =
          detail['index']?.toString() ??
          detail['id']?.toString() ??
          (snapshot ? i.toString() : _chatDetails.length.toString());
      final target = _chatDetails.putIfAbsent(key, () => <String, Object?>{});
      for (final entry in detail.entries) {
        final field = entry.key as String;
        final value = entry.value;
        if (['text', 'data', 'signature'].contains(field) && value is String) {
          final previous = target[field];
          if (previous is String) {
            if (snapshot && !value.startsWith(previous)) {
              _issues.add('reasoning_snapshot_conflict');
              continue;
            }
            target[field] = snapshot ? value : previous + value;
          } else {
            target[field] = value;
          }
        } else if (target.containsKey(field) &&
            !sameProviderValue(target[field], value)) {
          _issues.add('reasoning_identity_conflict');
        } else {
          target[field] = value;
        }
      }
    }
    _chat['reasoning_details'] = _chatDetails.values.toList(growable: false);
  }

  String _responseKey(Map data, [Map? item, int? index]) {
    final identities = [
      item?['id'],
      data['item_id'],
      item?['call_id'],
      data['call_id'],
    ];
    if (identities.any((id) => id != null && id is! String)) {
      _issues.add('invalid_response_identity');
    }
    final ids = identities
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final id = ids.isEmpty ? null : ids.first;
    final outputIndex = index ?? data['output_index'];
    if (outputIndex != null && outputIndex is! int) {
      _issues.add('invalid_response_index');
    }
    String? existing;
    for (final alias in ids) {
      final known = _responseIds[alias];
      if (known != null && existing != null && known != existing) {
        _issues.add('response_identity_conflict');
      }
      existing ??= known;
    }
    final key =
        existing ??
        (outputIndex != null
            ? 'output:$outputIndex'
            : id is String
            ? 'item:$id'
            : 'output:0');
    for (final alias in ids) {
      _responseIds[alias] = key;
    }
    if (outputIndex is int) _responseOrder[key] = outputIndex;
    return key;
  }

  void _addResponses(SseFrame frame) {
    final data = frame.data;
    final type = frame.eventType.isNotEmpty
        ? frame.eventType
        : data['type'] ?? '';
    final response = data['response'] is Map ? data['response'] as Map : data;
    if (data['response'] is Map &&
        data['output'] != null &&
        !sameProviderValue(data['output'], response['output'])) {
      _issues.add('conflicting_response_envelopes');
    }
    final output = response['output'];
    if (output is List) {
      for (var i = 0; i < output.length; i++) {
        if (output[i] is Map) {
          _responseItem(
            _responseKey(data, output[i] as Map, i),
            output[i] as Map,
            true,
          );
        } else {
          _issues.add('invalid_output_item');
        }
      }
    } else if (response['output_text'] is String) {
      _content('output:0:text:0', response['output_text'], snapshot: true);
    }
    final item = data['item'];
    final key = _responseKey(data, item is Map ? item : null);
    if (item is Map) {
      _responseItem(key, item, type != 'response.output_item.added');
    }
    if (type == 'response.output_text.delta' ||
        type == 'response.output_text.done') {
      _content(
        '$key:text:${data['content_index'] ?? 0}',
        type.endsWith('.delta') ? data['delta'] : data['text'],
        snapshot: type.endsWith('.done'),
      );
    } else if (type == 'response.reasoning_summary_text.delta' ||
        type == 'response.reasoning_summary_text.done' ||
        type == 'response.reasoning_text.delta' ||
        type == 'response.reasoning_text.done') {
      final section = type.toString().contains('summary')
          ? 'summary'
          : 'content';
      _content(
        '$key:$section:${data['summary_index'] ?? data['content_index'] ?? 0}',
        type.endsWith('.delta') ? data['delta'] : data['text'],
        snapshot: type.endsWith('.done'),
        thought: true,
      );
    } else if (type == 'response.content_part.done' ||
        type == 'response.content_part.added') {
      final part = data['part'];
      if (part is Map) {
        _responsePart(key, part, data['content_index'] ?? 0, true, 'content');
      }
    } else if (type == 'response.function_call_arguments.delta' ||
        type == 'response.function_call_arguments.done') {
      _tool(
        key,
        {
          if (data['name'] != null) 'name': data['name'],
          if (data['call_id'] != null) 'call_id': data['call_id'],
          'arguments': type.endsWith('.delta')
              ? data['delta']
              : data['arguments'],
        },
        snapshot: type.endsWith('.done'),
        argumentsKey: 'arguments',
      );
    } else if (type == 'response.refusal.delta' ||
        type == 'response.refusal.done') {
      _accept(const ProviderStreamTerminal.failure('refusal'));
    }
  }

  void _responseItem(String key, Map item, bool snapshot) {
    final type = item['type'];
    final native = _items.putIfAbsent(key, () => <String, Object?>{});
    _mergeNative(native, item, ignore: {'content', 'summary', 'arguments'});
    if (item['status'] == 'failed' ||
        item['status'] == 'incomplete' ||
        item['error'] != null) {
      _accept(
        ProviderStreamTerminal.failure(
          streamFailureReason(item, fallback: 'item_${item['status']}'),
        ),
      );
    }
    if (type == 'function_call' || type == 'tool_call') {
      _tool(key, item, snapshot: true, argumentsKey: 'arguments');
    } else if (type != 'message' && type != 'reasoning') {
      _issues.add('unknown_output_item');
    }
    for (final section in ['content', 'summary']) {
      final parts = item[section];
      if (parts is! List) continue;
      final previous = native[section];
      final combined = previous is List
          ? List<Object?>.from(previous)
          : <Object?>[];
      for (var i = 0; i < parts.length; i++) {
        if (parts[i] is Map) {
          _responsePart(key, parts[i] as Map, i, true, section);
        } else {
          _issues.add('invalid_content_part');
        }
        if (i < combined.length) {
          combined[i] = parts[i];
        } else {
          combined.add(parts[i]);
        }
      }
      native[section] = combined;
    }
  }

  void _responsePart(
    String key,
    Map part,
    Object index,
    bool snapshot,
    String section,
  ) {
    final type = part['type'];
    if (type == 'refusal') {
      _accept(const ProviderStreamTerminal.failure('refusal'));
    }
    final thought =
        type == 'reasoning_text' ||
        type == 'summary_text' ||
        section == 'summary' ||
        _items[key]?['type'] == 'reasoning';
    if (part['text'] is String) {
      _content(
        thought ? '$key:$section:$index' : '$key:text:$index',
        part['text'],
        snapshot: snapshot,
        thought: thought,
      );
    }
    final native = _items.putIfAbsent(key, () => <String, Object?>{});
    final parts = List<Object?>.from(native[section] as List? ?? const []);
    if (index is int) {
      while (parts.length <= index) {
        parts.add(null);
      }
      parts[index] = Map<String, Object?>.from(part);
      native[section] = parts;
    }
  }

  void _addAnthropic(SseFrame frame) {
    final data = frame.data;
    final type = frame.eventType.isNotEmpty ? frame.eventType : data['type'];
    final message = data['message'] is Map ? data['message'] as Map : data;
    final content = message['content'];
    if (content is List) {
      for (var i = 0; i < content.length; i++) {
        if (content[i] is Map) {
          _anthropicBlock('block:$i', content[i] as Map, true);
        } else {
          _issues.add('invalid_content_block');
        }
      }
    }
    final index = data['index'];
    if (type == 'content_block_start') {
      if (index is! int || data['content_block'] is! Map) {
        _issues.add('invalid_block_start');
        return;
      }
      _anthropicBlock('block:$index', data['content_block'] as Map, false);
    } else if (type == 'content_block_delta') {
      final key = 'block:$index';
      final block = _items[key];
      final delta = data['delta'];
      if (block == null || delta is! Map) {
        _issues.add('orphan_block_delta');
        return;
      }
      final expectedBlock = switch (delta['type']) {
        'text_delta' => 'text',
        'thinking_delta' || 'signature_delta' => 'thinking',
        'input_json_delta' => 'tool_use',
        _ => null,
      };
      if (expectedBlock == null || block['type'] != expectedBlock) {
        _issues.add('invalid_block_delta_type');
        return;
      }
      final deltaValue = switch (delta['type']) {
        'text_delta' => delta['text'],
        'thinking_delta' => delta['thinking'],
        'signature_delta' => delta['signature'] ?? delta['text'],
        'input_json_delta' => delta['partial_json'],
        _ => null,
      };
      if (deltaValue is! String) {
        _issues.add('invalid_block_delta_value');
        return;
      }
      switch (delta['type']) {
        case 'text_delta':
          _content(key, delta['text']);
          block['text'] = _texts[key];
        case 'thinking_delta':
          _content(key, delta['thinking'], thought: true);
          block['thinking'] = _thoughts[key];
        case 'signature_delta':
          final previous = block['signature'];
          if (previous != null && previous is! String) {
            _issues.add('invalid_thinking_signature');
          } else {
            block['signature'] = (previous as String? ?? '') + deltaValue;
          }
        case 'input_json_delta':
          _tools[key]?.add(
            delta['partial_json'],
            snapshot: false,
            replaceInitialObject: true,
          );
        default:
          _issues.add('unknown_block_delta');
      }
    } else if (type == 'content_block_stop' && index is int) {
      _tools['block:$index']?.complete = true;
    }
  }

  void _anthropicBlock(String key, Map block, bool snapshot) {
    final native = _items.putIfAbsent(key, () => <String, Object?>{});
    _mergeNative(native, block, ignore: {'text', 'thinking', 'input'});
    switch (block['type']) {
      case 'text':
        _content(key, block['text'], snapshot: snapshot);
        native['text'] = _texts[key] ?? '';
      case 'thinking':
        _content(key, block['thinking'], snapshot: snapshot, thought: true);
        native['thinking'] = _thoughts[key] ?? '';
      case 'tool_use':
        final tool = _tool(key, block, snapshot: true, argumentsKey: 'input');
        tool.complete = snapshot;
      case 'redacted_thinking':
        break;
      default:
        _issues.add('unknown_content_block');
    }
  }

  void _addGemini(Map data) {
    final feedback = data['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      _accept(
        ProviderStreamTerminal.failure(
          'prompt_block:${feedback['blockReason']}',
        ),
      );
    }
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      return;
    }
    // The selected response is candidate zero. Other candidates are alternatives,
    // never additional calls to execute.
    final candidate = candidates.first as Map;
    final content = candidate['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) return;
    for (final part in parts) {
      if (part is! Map) {
        _issues.add('invalid_gemini_part');
        continue;
      }
      final key = 'candidate:${candidate['index'] ?? 0}:part:${_geminiPart++}';
      if (part.length == 1 && part['text'] == '') continue;
      _items[key] = Map<String, Object?>.from(part);
      _content(key, part['text'], thought: part['thought'] == true);
      if (part.containsKey('functionCall')) {
        final call = part['functionCall'];
        if (call is Map) {
          _tool(key, call, snapshot: true, argumentsKey: 'args').complete =
              true;
        } else {
          _issues.add('invalid_function_call');
        }
      }
      if (part.containsKey('executableCode') ||
          part.containsKey('codeExecutionResult') ||
          part.containsKey('functionResponse')) {
        _issues.add('unknown_execution_block');
      }
    }
  }

  void _mergeNative(
    Map<String, Object?> target,
    Map source, {
    Set<String> ignore = const {},
  }) {
    for (final entry in source.entries) {
      if (ignore.contains(entry.key)) continue;
      final key = entry.key as String;
      final signatureExtension =
          key == 'signature' &&
          target[key] is String &&
          entry.value is String &&
          (entry.value as String).startsWith(target[key] as String);
      if (target.containsKey(key) &&
          !sameProviderValue(target[key], entry.value) &&
          key != 'status' &&
          !signatureExtension) {
        _issues.add('native_identity_conflict');
        continue;
      }
      target[key] = entry.value;
    }
  }

  ProviderResponse finish({ProviderStreamTerminal? terminal, int? statusCode}) {
    if (terminal != null) _accept(terminal);
    _sealed = true;
    final receptions = <ProviderToolReception>[];
    final ids = <String, ProviderToolReception>{};
    final signatures = <String, Object?>{};
    // Local associations must not collide with any upstream ID, even one
    // deliberately chosen to look like our positional key.
    final reservedIds = _tools.values
        .map((tool) => tool.nativeId)
        .whereType<String>()
        .toSet();
    for (final tool in _tools.values.where((tool) => tool.nativeId == null)) {
      var localId = tool.key;
      while (!reservedIds.add(localId)) {
        localId = 'local:$localId';
      }
      _localToolIds[tool.key] = localId;
    }
    if (_tools.isNotEmpty &&
        adapter.protocolType == ProtocolType.anthropicMessages &&
        _items.values.any(
          (block) =>
              block['type'] == 'thinking' &&
              (block['signature'] is! String ||
                  (block['signature'] as String).isEmpty),
        )) {
      _issues.add('missing_thinking_signature');
    }
    for (final tool in _tools.values) {
      var reception = receiveToolArguments(
        id: tool.nativeId ?? _localToolIds[tool.key]!,
        nativeId: tool.nativeId,
        name: tool.name,
        raw: tool.raw,
        conflict: tool.conflict,
        provided: tool.hasArguments,
      );
      final idRequired =
          adapter.protocolType != ProtocolType.gemini &&
          tool.key != 'chat:legacy';
      if (idRequired && tool.nativeId == null) {
        reception = ProviderToolReception(
          id: reception.id,
          name: reception.name,
          state: ProviderToolArgumentState.malformed,
          rawArguments: tool.raw,
        );
      }
      if (adapter.protocolType == ProtocolType.anthropicMessages &&
          !tool.complete &&
          reception.state == ProviderToolArgumentState.valid) {
        reception = ProviderToolReception(
          id: reception.id,
          nativeId: reception.nativeId,
          name: reception.name,
          state: ProviderToolArgumentState.incomplete,
          rawArguments: reception.rawArguments,
        );
      }
      final identity = tool.nativeId == null
          ? 'local:${tool.key}'
          : 'native:${tool.nativeId}';
      final previous = ids[identity];
      final signature = _items[tool.key]?['thoughtSignature'];
      final signatureConflict =
          signatures.containsKey(identity) &&
          !sameProviderValue(signatures[identity], signature);
      signatures[identity] = signature;
      if (previous != null) {
        if (!signatureConflict &&
            previous.name == reception.name &&
            previous.state == reception.state &&
            sameProviderValue(previous.arguments, reception.arguments) &&
            (previous.arguments != null ||
                sameProviderValue(
                  previous.rawArguments,
                  reception.rawArguments,
                ))) {
          continue;
        }
        _issues.add('duplicate_tool_id_conflict');
        reception = ProviderToolReception(
          id: reception.id,
          nativeId: reception.nativeId,
          name: reception.name,
          state: ProviderToolArgumentState.conflict,
          rawArguments: reception.rawArguments,
        );
      }
      ids[identity] = reception;
      receptions.add(reception);
      if (reception.state != ProviderToolArgumentState.valid) {
        _issues.add('tool_arguments_${reception.state.name}');
      }
    }
    var state = _state(_terminal);
    final toolsAllowed = switch (adapter.protocolType) {
      ProtocolType.openaiChat => [
        'finish_reason:tool_calls',
        'finish_reason:function_call',
      ].contains(_terminal.reason),
      ProtocolType.openaiResponses => _terminal.reason == 'response.completed',
      ProtocolType.anthropicMessages =>
        _terminal.reason == 'stop_reason:tool_use',
      ProtocolType.gemini => _terminal.reason == 'finish_reason:STOP',
      _ => false,
    };
    if (_issues.isNotEmpty &&
        (state == ProviderTerminalState.completed ||
            state == ProviderTerminalState.unknown)) {
      state = ProviderTerminalState.failed;
    }
    if (receptions.isNotEmpty && state == ProviderTerminalState.completed) {
      state = toolsAllowed
          ? ProviderTerminalState.toolRequired
          : ProviderTerminalState.unknown;
    }
    final calls = state == ProviderTerminalState.toolRequired && _issues.isEmpty
        ? receptions
              .map(
                (tool) => ProviderToolCall(
                  id: tool.id,
                  nativeId: tool.nativeId,
                  name: tool.name,
                  arguments: tool.arguments!,
                ),
              )
              .toList(growable: false)
        : <ProviderToolCall>[];
    return ProviderResponse(
      text: text,
      reasoning: reasoning,
      usage: Map.unmodifiable(_usage.values),
      usageSource: _usage.source,
      finishReason: _terminal.reason,
      terminalState: state,
      resolvedModelId: _model,
      statusCode: statusCode,
      toolCalls: List.unmodifiable(calls),
      toolReceptions: List.unmodifiable(receptions),
      parsingIssues: List.unmodifiable(_issues),
      nativeContinuation: _native(),
    );
  }

  Map<String, Object?>? _native() {
    if (adapter.protocolType == ProtocolType.openaiChat) {
      if (_texts.containsKey('chat') && !_chat.containsKey('content')) {
        _chat['content'] = _texts['chat'];
      }
      if (_tools.isNotEmpty) {
        final nativeIds = <String>{};
        _chat['tool_calls'] = [
          for (final tool in _tools.values)
            if (tool.key != 'chat:legacy' &&
                (tool.nativeId == null || nativeIds.add(tool.nativeId!)))
              {
                if (tool.nativeId != null) 'id': tool.nativeId,
                'type': 'function',
                'function': {'name': tool.name, 'arguments': tool.raw},
              },
        ];
        final legacy = _tools['chat:legacy'];
        if (legacy != null) {
          _chat['function_call'] = {
            'name': legacy.name,
            'arguments': legacy.raw,
          };
          if ((_chat['tool_calls'] as List).isEmpty) _chat.remove('tool_calls');
        }
      }
      return _chat.isEmpty
          ? null
          : {
              'protocol': adapter.protocolType,
              'items': [Map<String, Object?>.from(_chat)],
            };
    }
    if (adapter.protocolType == ProtocolType.anthropicMessages) {
      for (final tool in _tools.values) {
        final native = _items[tool.key];
        if (native != null) {
          final reception = receiveToolArguments(
            id: tool.key,
            name: tool.name,
            raw: tool.raw,
          );
          native['input'] = reception.arguments ?? tool.raw;
        }
      }
    }
    if (adapter.protocolType == ProtocolType.openaiResponses) {
      for (final tool in _tools.values) {
        final native = _items.putIfAbsent(
          tool.key,
          () => {'type': 'function_call', 'name': tool.name},
        );
        native['arguments'] = tool.raw;
        if (tool.nativeId != null) native['call_id'] = tool.nativeId;
      }
      // Reconstruct native text when a server sends deltas without item.done.
      for (final entry in _texts.entries) {
        final marker = entry.key.lastIndexOf(':text:');
        if (marker < 0) continue;
        final key = entry.key.substring(0, marker);
        final index = int.parse(entry.key.substring(marker + 6));
        final native = _items.putIfAbsent(
          key,
          () => {'type': 'message', 'role': 'assistant'},
        );
        final parts = List<Object?>.from(
          native['content'] as List? ?? const [],
        );
        while (parts.length <= index) {
          parts.add(null);
        }
        parts[index] = {
          ...?parts[index] as Map?,
          'type': 'output_text',
          'text': entry.value,
        };
        native['content'] = parts;
      }
      for (final entry in _thoughts.entries) {
        final marker = entry.key.lastIndexOf(':');
        final sectionMarker = entry.key.lastIndexOf(':', marker - 1);
        final key = entry.key.substring(0, sectionMarker);
        final section = entry.key.substring(sectionMarker + 1, marker);
        final index = int.parse(entry.key.substring(marker + 1));
        final native = _items.putIfAbsent(key, () => {'type': 'reasoning'});
        final parts = List<Object?>.from(native[section] as List? ?? const []);
        while (parts.length <= index) {
          parts.add(null);
        }
        parts[index] = {
          ...?parts[index] as Map?,
          'type': section == 'summary' ? 'summary_text' : 'reasoning_text',
          'text': entry.value,
        };
        native[section] = parts;
      }
    }
    final keys = _items.keys.toList();
    if (adapter.protocolType == ProtocolType.anthropicMessages) {
      keys.sort(
        (a, b) =>
            int.parse(a.split(':')[1]).compareTo(int.parse(b.split(':')[1])),
      );
    } else if (adapter.protocolType == ProtocolType.openaiResponses) {
      keys.sort(
        (a, b) => (_responseOrder[a] ?? 0).compareTo(_responseOrder[b] ?? 0),
      );
    }
    final seenCalls = <String, Map<String, Object?>>{};
    final nativeItems = <Map<String, Object?>>[];
    for (final key in keys) {
      final item = _items[key]!;
      final tool = _tools[key];
      if (tool?.nativeId != null) {
        final previous = seenCalls[tool!.nativeId!];
        if (previous != null && sameProviderValue(previous, item)) continue;
        seenCalls[tool.nativeId!] = item;
      }
      nativeItems.add(item);
    }
    return nativeItems.isEmpty
        ? null
        : {
            'protocol': adapter.protocolType,
            'items': nativeItems,
            if (adapter.protocolType == ProtocolType.gemini &&
                _tools.isNotEmpty)
              'tool_associations': [
                for (final tool in _tools.values)
                  {
                    'id': tool.nativeId ?? _localToolIds[tool.key],
                    'native_id': tool.nativeId,
                    'name': tool.name,
                  },
              ],
          };
  }
}

ProviderResponse aggregateProviderFrames(
  ModelProtocolAdapter adapter,
  List<SseFrame> frames, {
  ProviderStreamTerminal? terminal,
  int? statusCode,
}) {
  final result = ProviderResultAggregator(adapter: adapter);
  for (final frame in frames) {
    result.addFrame(frame);
  }
  return result.finish(terminal: terminal, statusCode: statusCode);
}

ProviderResponse aggregateProviderPayload(
  ModelProtocolAdapter adapter,
  Map payload, {
  int? statusCode,
}) {
  final result = ProviderResultAggregator(adapter: adapter)
    ..addPayload(payload);
  return result.finish(statusCode: statusCode);
}

ProviderTerminalState _state(ProviderStreamTerminal terminal) {
  if (!terminal.isTerminal) return ProviderTerminalState.unknown;
  if (terminal.isSuccess) return ProviderTerminalState.completed;
  final reason = terminal.reason.toLowerCase();
  if (reason.contains('cancel')) return ProviderTerminalState.cancelled;
  if ([
    'max_tokens',
    'max_output_tokens',
    'length',
    'max_completion_tokens',
  ].any(reason.contains)) {
    return ProviderTerminalState.truncated;
  }
  if ([
    'refus',
    'content_filter',
    'safety',
    'block',
    'recitation',
    'prohibited',
  ].any(reason.contains)) {
    return ProviderTerminalState.refused;
  }
  return ProviderTerminalState.failed;
}

class _ToolBuffer {
  _ToolBuffer(this.key);
  final String key;
  String name = '';
  String? nativeId;
  Object? raw;
  bool conflict = false;
  bool complete = false;
  bool _hasDelta = false;
  bool hasArguments = false;

  void identify(Object? newName, Object? id) {
    if ((newName != null && newName is! String) ||
        (id != null && id is! String)) {
      conflict = true;
    }
    if (newName is String && newName.isNotEmpty) {
      if (name.isNotEmpty && name != newName) conflict = true;
      name = newName;
    }
    if (id is String && id.isNotEmpty) {
      if (nativeId != null && nativeId != id) conflict = true;
      nativeId = id;
    }
  }

  void add(
    Object? incoming, {
    required bool snapshot,
    bool replaceInitialObject = false,
  }) {
    hasArguments = true;
    if (!snapshot) {
      if (incoming is! String) {
        conflict = true;
        return;
      }
      if (incoming.isEmpty) return;
      if (!_hasDelta && replaceInitialObject) raw = null;
      _hasDelta = true;
      raw = '${raw ?? ''}$incoming';
      return;
    }
    if (raw != null && raw != '' && !sameProviderValue(raw, incoming)) {
      final prior = receiveToolArguments(id: key, name: name, raw: raw);
      final next = receiveToolArguments(id: key, name: name, raw: incoming);
      final equivalent =
          prior.arguments != null &&
          next.arguments != null &&
          sameProviderValue(prior.arguments, next.arguments);
      final prefix =
          raw is String &&
          incoming is String &&
          (incoming).startsWith(raw as String);
      if (!equivalent && !prefix) {
        conflict = true;
        return;
      }
    }
    raw = incoming;
  }
}
