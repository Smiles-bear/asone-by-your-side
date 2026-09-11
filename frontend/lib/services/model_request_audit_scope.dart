import 'dart:async';

/// Sensitive interactive requests retain references, never request/response bodies.
/// Zone scoping prevents concurrent ordinary chats from inheriting this policy.
class ModelRequestAuditScope {
  static final Object _key = Object();
  static Map<String, Object?>? get current =>
      Zone.current[_key] as Map<String, Object?>?;

  static Future<T> referencesOnly<T>(
    Map<String, Object?> references,
    Future<T> Function() operation,
  ) => runZoned(
    operation,
    zoneValues: {
      _key: Map<String, Object?>.unmodifiable({
        ...references,
        'references_only': true,
      }),
    },
  );
}
