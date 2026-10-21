import 'adapter_helpers.dart';
import 'protocol_types.dart';

/// Provider-reported cumulative counters. Missing fields remain unknown.
/// The protocol determines input accounting; a model's brand never does.
class ProviderUsage {
  ProviderUsage({this.protocol});
  final String? protocol;
  final Map<String, int> values = {};
  String source = 'unreported';
  final Set<String> anomalies = {};
  int? _baseInput;
  bool _exclusiveInput = false;

  void addPayload(Map payload) {
    final extracted = _extractUsage(payload);
    if (extracted == null) return;
    final (raw: raw, source: inputSource) = extracted;
    // Output-only message_delta must not erase the message_start semantics.
    if (source == 'unreported' || _hasInput(raw)) source = inputSource;
    final input = _count(raw, [
      'prompt_tokens',
      'input_tokens',
      'promptTokenCount',
      'inputTokenCount',
      'inputTokens',
      'total_input_tokens',
    ]);
    if (input != null) {
      _baseInput = input;
      _exclusiveInput =
          inputSource == 'anthropic_fields' || inputSource == 'bedrock_fields';
    }
    _readCacheUsage(raw);
    if (_baseInput != null) {
      values['prompt_tokens'] =
          _baseInput! +
          (_exclusiveInput
              ? (values['cache_read_tokens'] ?? 0) +
                    (values['cache_write_tokens'] ?? 0)
              : 0);
    }
    _put('completion_tokens', _outputTokens(raw));
    _put('reasoning_tokens', _count(raw, ['thoughtsTokenCount']));
    _put('cache_miss_tokens', _count(raw, ['prompt_cache_miss_tokens']));
    final total = _count(raw, [
      'total_tokens',
      'totalTokenCount',
      'totalTokens',
    ]);
    if (total != null) {
      _put('total_tokens', total);
    } else if (values['prompt_tokens'] != null &&
        values['completion_tokens'] != null) {
      _put(
        'total_tokens',
        values['prompt_tokens']! + values['completion_tokens']!,
      );
    }
    final totalInput = values['prompt_tokens'],
        cached = values['cache_read_tokens'];
    if (totalInput != null && cached != null && cached > totalInput) {
      anomalies.add('read_exceeds_input');
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
    final read = _aliases([
      if (details is Map) details['cached_tokens'],
      raw['cache_read_tokens'],
      raw['prompt_cache_hit_tokens'],
      raw['cache_read_input_tokens'],
      raw['cachedContentTokenCount'],
      raw['cached_tokens'],
      raw['cacheReadInputTokens'],
      raw['total_cached_tokens'],
    ], 'read_alias_conflict');
    final write = _aliases([
      if (details is Map) ...[
        details['cache_write_tokens'],
        details['cache_creation_input_tokens'],
      ],
      raw['cache_write_tokens'],
      raw['cache_creation_input_tokens'],
      raw['cacheWriteInputTokens'],
    ], 'write_alias_conflict');
    _put('cache_read_tokens', read);
    _put('cache_write_tokens', write);
  }

  int? _outputTokens(Map raw) {
    final visible = _count(raw, [
      'completion_tokens',
      'output_tokens',
      'candidatesTokenCount',
      'outputTokenCount',
      'outputTokens',
      'total_output_tokens',
    ]);
    final thoughts = raw.containsKey('candidatesTokenCount')
        ? (_count(raw, ['thoughtsTokenCount']) ?? 0)
        : 0;
    // Output accounting includes Gemini thinking once; the separate reasoning
    // counter is diagnostic and must not be added again to the turn total.
    return visible == null ? null : visible + thoughts;
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

  int? _count(Map raw, List<String> keys) =>
      _aliases([for (final key in keys) raw[key]], 'input_alias_conflict');

  int? _aliases(List<Object?> candidates, String conflict) {
    int? result;
    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (candidate is! num ||
          !candidate.isFinite ||
          candidate < 0 ||
          candidate != candidate.truncateToDouble()) {
        anomalies.add('invalid_counter');
        continue;
      }
      final value = candidate.toInt();
      if (result != null && result != value) anomalies.add(conflict);
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
      anomalies.add('read_exceeds_input');
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
    return usage.values;
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
