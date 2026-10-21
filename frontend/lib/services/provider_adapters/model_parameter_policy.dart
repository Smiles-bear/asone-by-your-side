import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../provider_registry.dart';
import 'protocol_types.dart';

/// Endpoint-specific request dialect. Unknown optional controls are omitted;
/// deterministic parameter errors can teach a bounded, configuration-local rule.
class ModelParameterPolicy {
  ModelParameterPolicy._(this._key, this.protocol, this.host, this.model);

  factory ModelParameterPolicy.forEndpoint({
    required String baseUrl,
    required String modelId,
    required String protocol,
    String apiKey = '',
    String requestPath = '',
  }) => ModelParameterPolicy._(
    sha256
        .convert(
          utf8.encode(
            jsonEncode([
              baseUrl.trim(),
              requestPath.trim(),
              modelId.trim(),
              protocol,
              apiKey,
            ]),
          ),
        )
        .toString(),
    protocol,
    Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '',
    modelId.trim().toLowerCase(),
  );

  static const version = 1;
  static final _learned = <String, _ParameterDialect>{};
  final String _key;
  final String protocol;
  final String host;
  final String model;

  bool get _officialQwen =>
      host == 'dashscope.aliyuncs.com' ||
      host == 'dashscope-us.aliyuncs.com' ||
      host.endsWith('.maas.aliyuncs.com');

  bool get _modernQwen => _officialQwen && model == 'qwen3.8-max';
  bool get _officialGrok => host == 'api.x.ai';

  String get tokenField =>
      _learned[_key]?.tokenField ??
      switch (protocol) {
        ProtocolType.openaiChat
            when host == 'api.openai.com' || _officialGrok || _modernQwen =>
          'max_completion_tokens',
        ProtocolType.openaiChat => 'max_tokens',
        ProtocolType.openaiResponses => 'max_output_tokens',
        ProtocolType.anthropicMessages => 'max_tokens',
        ProtocolType.gemini => 'maxOutputTokens',
        _ => '',
      };

  void apply(Map<String, Object?> payload, {required bool directResponse}) {
    if (protocol == ProtocolType.openaiChat) {
      final old = tokenField == 'max_tokens'
          ? 'max_completion_tokens'
          : 'max_tokens';
      if (payload.containsKey(old)) {
        final value = payload.remove(old);
        if (payload.containsKey(tokenField) && payload[tokenField] != value) {
          throw const FormatException('Conflicting output token limits');
        }
        payload[tokenField] = value;
      }
    }
    // Preserve the established compatible-provider temperature contract. An
    // arbitrary gateway or a new reasoning family does not inherit it by name.
    final knownTemperature =
        protocol == ProtocolType.gemini &&
            host == 'generativelanguage.googleapis.com' ||
        protocol == ProtocolType.anthropicMessages &&
            host == 'api.anthropic.com' ||
        protocol == ProtocolType.openaiChat &&
            ProviderRegistry.instance.matchByHost(host) != null;
    if (!knownTemperature || _officialGrok) {
      _omit(
        payload,
        protocol == ProtocolType.gemini
            ? 'generationConfig.temperature'
            : 'temperature',
      );
    }
    for (final field in _learned[_key]?.omitted ?? const <String>{}) {
      _omit(payload, field);
    }
    if (_modernQwen &&
        directResponse &&
        !payload.containsKey('enable_thinking') &&
        !(_learned[_key]?.omitted.contains('reasoning_effort') ?? false)) {
      payload.putIfAbsent('reasoning_effort', () => 'low');
    }
  }

  /// Change only a named, explicitly rejected parameter. Never remove the
  /// output budget, infer credentials, or change the endpoint/model.
  bool adjustAfterRejection({
    required int? statusCode,
    required Object? response,
    required Map<String, Object?> payload,
  }) {
    if (statusCode != 400 && statusCode != 422) return false;
    final raw = response is String ? response : jsonEncode(response);
    if (raw.length > 16 * 1024) return false;
    final text = raw.toLowerCase();
    if (!RegExp(
      r'not supported|unsupported|does not support|not compatible|unrecognized|unknown parameter|not allowed|not permitted|only supported|invalid parameter|不支持|未知参数|不允许',
    ).hasMatch(text)) {
      return false;
    }
    if (RegExp(
      r'quota|billing|balance|api.?key|permission|content.policy|无可用渠道|额度|余额|审核',
    ).hasMatch(text)) {
      return false;
    }
    if (protocol == ProtocolType.openaiChat) {
      for (final rejected in const ['max_completion_tokens', 'max_tokens']) {
        if (!text.contains(rejected) || !payload.containsKey(rejected)) {
          continue;
        }
        final alternate = rejected == 'max_tokens'
            ? 'max_completion_tokens'
            : 'max_tokens';
        final value = payload[rejected];
        if (value is! int || value <= 0 || payload.containsKey(alternate)) {
          return false;
        }
        payload.remove(rejected);
        payload[alternate] = value;
        return true;
      }
    }
    for (final field in const [
      'temperature',
      'reasoning_effort',
      'enable_thinking',
      'thinking',
      'reasoning',
      'output_config.effort',
      'generationConfig.temperature',
      'generationConfig.thinkingConfig',
    ]) {
      final mentioned = field == 'output_config.effort'
          ? text.contains('output_config') && text.contains('effort')
          : RegExp(
              '(?<![a-z_])${RegExp.escape(field.toLowerCase())}(?![a-z_])',
            ).hasMatch(text);
      final path = field == 'temperature' && protocol == ProtocolType.gemini
          ? 'generationConfig.temperature'
          : field;
      if (mentioned && _omit(payload, path)) {
        _dialect.omitted.add(path);
        return true;
      }
    }
    return false;
  }

  void rememberSuccess(Map<String, Object?> payload) {
    if (protocol == ProtocolType.openaiChat) {
      for (final field in const ['max_tokens', 'max_completion_tokens']) {
        if (payload[field] is int) _dialect.tokenField = field;
      }
    }
  }

  Map<String, Object?> get evidence => {
    'version': version,
    'token_field': tokenField,
    'omitted': List<String>.of(_learned[_key]?.omitted ?? const {}),
  };

  /// The caller must first match the persisted configuration fingerprint.
  /// Unknown future evidence versions are ignored, not guessed.
  void restoreEvidence(Map<String, Object?> evidence) {
    if (evidence['version'] != version) return;
    final field = evidence['token_field'];
    if (protocol == ProtocolType.openaiChat &&
        const ['max_tokens', 'max_completion_tokens'].contains(field)) {
      _dialect.tokenField ??= field as String;
    }
    final omitted = evidence['omitted'];
    if (omitted is List) {
      _dialect.omitted.addAll(
        omitted.whereType<String>().where(
          const {
            'temperature',
            'reasoning_effort',
            'enable_thinking',
            'thinking',
            'reasoning',
            'output_config.effort',
            'generationConfig.temperature',
            'generationConfig.thinkingConfig',
          }.contains,
        ),
      );
    }
  }

  _ParameterDialect get _dialect {
    if (!_learned.containsKey(_key) && _learned.length >= 64) {
      _learned.remove(_learned.keys.first);
    }
    return _learned.putIfAbsent(_key, _ParameterDialect.new);
  }

  static bool _omit(Map<String, Object?> payload, String field) {
    final separator = field.indexOf('.');
    if (separator >= 0) {
      final parent = field.substring(0, separator);
      final child = field.substring(separator + 1);
      final config = payload[parent];
      if (config is! Map || !config.containsKey(child)) return false;
      final copy = Map<String, Object?>.from(config)..remove(child);
      if (copy.isEmpty) {
        payload.remove(parent);
      } else {
        payload[parent] = copy;
      }
      return true;
    }
    if (!payload.containsKey(field)) return false;
    payload.remove(field);
    return true;
  }
}

class _ParameterDialect {
  String? tokenField;
  final omitted = <String>{};
}
