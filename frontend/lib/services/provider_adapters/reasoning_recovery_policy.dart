import 'protocol_types.dart';

/// Verified provider contracts, independent of changing model names. A custom
/// gateway does not inherit a contract merely by naming a model "deepseek".
abstract final class ReasoningRecoveryPolicy {
  static const _overrides = <String, Map<String, Object?>>{
    'deepseek': {
      'thinking': {'type': 'disabled'},
    },
  };

  static Map<String, Object?> payload(String provider, String protocol) =>
      protocol == ProtocolType.openaiChat
      ? _overrides[provider.trim().toLowerCase()] ?? const {}
      : const {};
}
