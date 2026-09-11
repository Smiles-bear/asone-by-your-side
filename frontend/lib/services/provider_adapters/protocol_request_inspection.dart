part of 'protocol_client.dart';

extension on ProtocolClient {
  List<Map<String, dynamic>> _inspectableMessages(
    Map<String, Object?> payload,
  ) {
    for (final key in const ['messages', 'input', 'contents']) {
      final value = payload[key];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList(growable: false);
      }
    }
    return const [];
  }

  Map<String, Object?>? _requestMetadata(Map<String, Object?> payload) {
    final metadata = <String, Object?>{
      if (payload['tools'] != null) 'tools': payload['tools'],
      if (payload['tool_choice'] != null) 'tool_choice': payload['tool_choice'],
      if (payload['toolConfig'] != null) 'tool_choice': payload['toolConfig'],
    };
    return metadata.isEmpty ? null : metadata;
  }

  List<Map<String, Object?>> _inspectableToolCalls(
    List<ProviderToolCall> toolCalls,
  ) => toolCalls
      .map(
        (call) => {
          'id': call.id,
          'name': call.name,
          'arguments': call.arguments,
        },
      )
      .toList(growable: false);
}
