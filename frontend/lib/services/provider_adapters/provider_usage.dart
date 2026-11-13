import 'adapter_helpers.dart';
import 'protocol_types.dart';

/// Provider-reported cumulative counters. Missing fields remain unknown.
/// The protocol determines input accounting; a model's brand never does.
class ProviderUsage {
  ProviderUsage({this.protocol});
  final String? protocol;
  final Map<String, int> values = {};
  String source = 'unreported';
  final Set<String> _parseAnomalies = {};
  final Set<String> _invalid = {};
  int? _baseInput;
  int? _explicitTotal;
  int? _geminiVisibleOutput;
  bool _exclusiveInput = false;

  /// Raw counters remain available for evidence. Only this view is consumable.
  /// Mathematical checks use the current cumulative snapshot, so an early
  /// partial snapshot cannot permanently invalidate a later complete one.
  Map<String, int> get validatedValues {
    final invalid = {..._invalid};
    final math = _mathAnomalies;
    if (math.contains('read_exceeds_input')) {
      invalid.addAll(['prompt_tokens', 'cache_read_tokens']);
    }
    if (math.contains('write_exceeds_input')) {
      invalid.addAll(['prompt_tokens', 'cache_write_tokens']);
    }
    if (math.contains('cache_partition_conflict')) {
      invalid.addAll([
        'prompt_tokens',
        'cache_read_tokens',
        'cache_miss_tokens',
      ]);
    }
    if (math.contains('total_conflict') ||
        math.contains('input_total_conflict')) {
      invalid.addAll(['prompt_tokens', 'completion_tokens', 'total_tokens']);
    }
    if (_exclusiveInput &&
        (invalid.contains('cache_read_tokens') ||
            invalid.contains('cache_write_tokens'))) {
      invalid.add('prompt_tokens');
    }
    if (invalid.contains('tool_prompt_tokens')) invalid.add('prompt_tokens');
    if (invalid.contains('reasoning_tokens')) invalid.add('completion_tokens');
    if (invalid.contains('prompt_tokens') ||
        invalid.contains('completion_tokens')) {
      invalid.add('total_tokens');
    }
    return Map.fromEntries(
      values.entries.where((e) => !invalid.contains(e.key)),
    );
  }

  Set<String> get anomalies => {..._parseAnomalies, ..._mathAnomalies};

  Set<String> get _mathAnomalies {
    final result = <String>{};
    final input = values['prompt_tokens'], output = values['completion_tokens'];
    final read = values['cache_read_tokens'],
        write = values['cache_write_tokens'];
    final miss = values['cache_miss_tokens'];
    if (input != null && !_invalid.contains('prompt_tokens')) {
      if (read != null &&
          !_invalid.contains('cache_read_tokens') &&
          read > input) {
        result.add('read_exceeds_input');
      }
      if (write != null &&
          !_invalid.contains('cache_write_tokens') &&
          write > input) {
        result.add('write_exceeds_input');
      }
      if (read != null &&
          miss != null &&
          !_invalid.contains('cache_read_tokens') &&
          !_invalid.contains('cache_miss_tokens') &&
          read + miss != input) {
        result.add('cache_partition_conflict');
      }
      if (output != null &&
          _explicitTotal != null &&
          !_invalid.contains('total_tokens') &&
          !_invalid.contains('completion_tokens') &&
          input + output != _explicitTotal) {
        result.add('total_conflict');
      }
    }
    return result;
  }

  void addPayload(Map payload) {
    final extracted = _extractUsage(payload);
    if (extracted == null) return;
    final (raw: raw, source: inputSource) = extracted;
    // Output-only message_delta must not erase the message_start semantics.
    if (source == 'unreported' || _hasInput(raw)) source = inputSource;
    final exclusive =
        inputSource == 'anthropic_fields' || inputSource == 'bedrock_fields';
    final input = _count(raw, 'prompt_tokens', [
      'prompt_tokens',
      'input_tokens',
      'promptTokenCount',
      'inputTokenCount',
      'inputTokens',
      if (!exclusive ||
          !raw.containsKey('input_tokens') && !raw.containsKey('inputTokens'))
        'total_input_tokens',
    ]);
    if (input != null) {
      _baseInput = input;
      _exclusiveInput =
          exclusive &&
          (raw.containsKey('input_tokens') || raw.containsKey('inputTokens'));
    }
    _readCacheUsage(raw);
    if (inputSource == 'gemini_fields' || protocol == ProtocolType.gemini) {
      _put(
        'tool_prompt_tokens',
        _count(raw, 'tool_prompt_tokens', ['toolUsePromptTokenCount']),
      );
    }
    if (_baseInput != null) {
      values['prompt_tokens'] =
          _baseInput! +
          (_exclusiveInput
              ? (values['cache_read_tokens'] ?? 0) +
                    (values['cache_write_tokens'] ?? 0)
              : 0) +
          (values['tool_prompt_tokens'] ?? 0);
    }
    _put('completion_tokens', _outputTokens(raw));
    _put(
      'reasoning_tokens',
      _count(raw, 'reasoning_tokens', ['thoughtsTokenCount']),
    );
    _put(
      'cache_miss_tokens',
      _count(raw, 'cache_miss_tokens', ['prompt_cache_miss_tokens']),
    );
    final total = _count(raw, 'total_tokens', [
      'total_tokens',
      'totalTokenCount',
      'totalTokens',
    ]);
    if (total != null) {
      _explicitTotal = total;
      values['total_tokens'] = total;
    } else if (values['prompt_tokens'] != null &&
        values['completion_tokens'] != null) {
      if (_explicitTotal == null) {
        values['total_tokens'] =
            values['prompt_tokens']! + values['completion_tokens']!;
      }
    }
    if (_exclusiveInput && raw.containsKey('total_input_tokens')) {
      final declared = _count(raw, 'prompt_tokens', ['total_input_tokens']);
      if (declared != null && declared != values['prompt_tokens']) {
        _invalid.add('prompt_tokens');
        _parseAnomalies.add('input_total_conflict');
      }
    }
  }

  ({Map raw, String source})? _extractUsage(Map payload) {
    final nested = payload['response'] ?? payload['message'];
    final groq = payload['x_groq'];
    final groqUsage = groq is Map ? groq['usage'] : null;
    final raw =
        payload['usage'] ??
        payload['usageMetadata'] ??
        (nested is Map ? nested['usage'] ?? nested['usageMetadata'] : null) ??
        groqUsage;
    if (raw is! Map) return null;
    final inputSource = identical(raw, groqUsage)
        ? 'groq_fields'
        : raw.containsKey('promptTokenCount')
        ? 'gemini_fields'
        : raw.containsKey('inputTokens')
        ? 'bedrock_fields'
        : raw.containsKey('prompt_cache_hit_tokens')
        ? 'deepseek_fields'
        : _anthropic(raw)
        ? 'anthropic_fields'
        : 'compatible_fields';
    return (raw: raw, source: inputSource);
  }

  void _readCacheUsage(Map raw) {
    final details = raw['prompt_tokens_details'] ?? raw['input_tokens_details'];
    final read = _aliases(
      [
        if (details is Map) details['cached_tokens'],
        raw['cache_read_tokens'],
        raw['prompt_cache_hit_tokens'],
        raw['cache_read_input_tokens'],
        raw['cachedContentTokenCount'],
        raw['cached_tokens'],
        raw['cacheReadInputTokens'],
        raw['total_cached_tokens'],
      ],
      'cache_read_tokens',
      'read_alias_conflict',
    );
    final write = _aliases(
      [
        if (details is Map) ...[
          details['cache_write_tokens'],
          details['cache_creation_input_tokens'],
        ],
        raw['cache_write_tokens'],
        raw['cache_creation_input_tokens'],
        raw['cacheWriteInputTokens'],
      ],
      'cache_write_tokens',
      'write_alias_conflict',
    );
    _put('cache_read_tokens', read);
    _put('cache_write_tokens', write);
  }

  int? _outputTokens(Map raw) {
    final visible = _count(raw, 'completion_tokens', [
      'completion_tokens',
      'output_tokens',
      'candidatesTokenCount',
      'outputTokenCount',
      'outputTokens',
      'total_output_tokens',
    ]);
    if (raw.containsKey('candidatesTokenCount')) _geminiVisibleOutput = visible;
    final gemini =
        _geminiVisibleOutput != null &&
        (raw.containsKey('candidatesTokenCount') ||
            raw.containsKey('thoughtsTokenCount'));
    final thoughts = gemini
        ? (_count(raw, 'reasoning_tokens', ['thoughtsTokenCount']) ??
              values['reasoning_tokens'] ??
              0)
        : 0;
    // Output accounting includes Gemini thinking once; the separate reasoning
    // counter is diagnostic and must not be added again to the turn total.
    final output = gemini ? _geminiVisibleOutput : visible;
    return output == null ? null : output + thoughts;
  }

  bool _anthropic(Map raw) =>
      !raw.containsKey('prompt_tokens') &&
      raw['prompt_tokens_details'] == null &&
      raw['input_tokens_details'] == null &&
      (protocol == ProtocolType.anthropicMessages ||
          protocol == null &&
              (raw.containsKey('cache_read_input_tokens') ||
                  raw.containsKey('cache_creation_input_tokens')));

  static bool _hasInput(Map raw) => const [
    'prompt_tokens',
    'input_tokens',
    'promptTokenCount',
    'inputTokenCount',
    'inputTokens',
    'total_input_tokens',
  ].any(raw.containsKey);

  int? _count(Map raw, String field, List<String> keys) => _aliases(
    [for (final key in keys) raw[key]],
    field,
    '${field}_alias_conflict',
  );

  int? _aliases(List<Object?> candidates, String field, String conflict) {
    int? result;
    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (candidate is! num ||
          !candidate.isFinite ||
          candidate < 0 ||
          candidate > 9007199254740991 ||
          candidate != candidate.truncateToDouble()) {
        _parseAnomalies.add('invalid_counter');
        _invalid.add(field);
        continue;
      }
      final value = candidate.toInt();
      if (result != null && result != value) {
        _parseAnomalies.add(conflict);
        _invalid.add(field);
      }
      result ??= value;
    }
    return result;
  }

  void _put(String key, int? value) {
    if (value != null && value >= (values[key] ?? 0)) values[key] = value;
  }

  /// Dedicated Fireworks deployments expose numeric counters in these headers.
  /// Never persist arbitrary response headers or apply this to unknown hosts.
  void addHeaders(
    Map<String, List<String>> headers, {
    required String baseUrl,
  }) {
    if (Uri.tryParse(baseUrl)?.host.toLowerCase() != 'api.fireworks.ai') return;
    int? header(String name) {
      final value = headers.entries
          .where((e) => e.key.toLowerCase() == name)
          .firstOrNull
          ?.value
          .firstOrNull;
      return value != null && RegExp(r'^[0-9]{1,15}$').hasMatch(value)
          ? int.tryParse(value)
          : null;
    }

    final input = header('fireworks-prompt-tokens'),
        read = header('fireworks-cached-prompt-tokens');
    if (input == null && read == null) return;
    source = 'fireworks_headers';
    _put('prompt_tokens', input);
    _put('cache_read_tokens', read);
    if (input != null && read != null && read > input) {
      _parseAnomalies.add('read_exceeds_input');
      _invalid.addAll(['prompt_tokens', 'cache_read_tokens']);
    }
  }

  static Map<String, int> fromFrames(
    List<SseFrame> frames, {
    String? protocol,
  }) {
    final usage = ProviderUsage(protocol: protocol);
    for (final frame in frames) {
      usage.addPayload(frame.data);
    }
    return usage.validatedValues;
  }
}

/// A turn total is unknown when any constituent request omitted that field.
class CacheUsageTotals {
  int? read = 0;
  int? write = 0;
  void add(Map<String, int>? usage) {
    final nextRead = usage?['cache_read_tokens'];
    final nextWrite = usage?['cache_write_tokens'];
    read = read == null || nextRead == null ? null : read! + nextRead;
    write = write == null || nextWrite == null ? null : write! + nextWrite;
  }
}
