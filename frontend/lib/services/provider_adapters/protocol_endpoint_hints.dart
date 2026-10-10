part of 'protocol_client.dart';

// Route hints live only with the Dio client; no credentials are persisted.
final _successfulEndpointHints = Expando<Map<String, String>>();

extension _ProtocolEndpointHints on ProtocolClient {
  ({Map<String, String> hints, String key, List<String> endpoints})
  _endpointRoute({
    required String protocol,
    required String baseUrl,
    required String modelId,
    required String apiKey,
    required Map<String, Object?> headers,
    required List<String> candidates,
  }) {
    final hints = _successfulEndpointHints[_dio] ??= {};
    final stableHeaders =
        headers.entries
            .where((entry) => entry.key.toLowerCase() != 'idempotency-key')
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final key = jsonEncode([
      configurationScope,
      protocol,
      baseUrl,
      modelId,
      apiKey,
      {for (final header in stableHeaders) header.key: header.value},
    ]);
    final preferred = hints[key];
    return (
      hints: hints,
      key: key,
      endpoints: [
        if (preferred != null && candidates.contains(preferred)) preferred,
        ...candidates.where((endpoint) => endpoint != preferred),
      ],
    );
  }

  void _rememberEndpoint(
    Map<String, String> hints,
    String key,
    String endpoint,
    int? status,
  ) {
    if (status == null || status < 200 || status >= 300) return;
    if (hints.length >= 32 && !hints.containsKey(key)) {
      hints.remove(hints.keys.first);
    }
    hints[key] = endpoint;
  }
}
