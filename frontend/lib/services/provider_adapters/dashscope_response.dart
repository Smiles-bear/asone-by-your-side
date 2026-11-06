/// DashScope's native envelope shares message/tool semantics with Chat, but
/// incremental SSE messages are deltas, not cumulative message snapshots.
Map<String, Object?> dashscopeChatPayload(Map data, {bool streaming = false}) {
  final output = data['output'];
  final choices = output is Map ? output['choices'] : null;
  return {
    ...data.cast<String, Object?>(),
    if (data['code'] is String &&
        data['code'] != '' &&
        data['code'] != 'Success')
      'error': {'code': data['code'], 'message': data['message']},
    if (choices is List)
      'choices': [
        for (final value in choices)
          if (value is! Map)
            value
          else
            {
              ...value.cast<String, Object?>(),
              if (value['finish_reason'] == 'null') 'finish_reason': null,
              if (value['message'] is Map)
                streaming ? 'delta' : 'message': _message(
                  value['message'] as Map,
                ),
            }..removeWhere((key, _) => streaming && key == 'message'),
      ],
  };
}

Map<String, Object?> _message(Map message) => {
  ...message.cast<String, Object?>(),
  if (message['content'] is List)
    'content': [
      for (final part in message['content'] as List)
        if (part is Map && part['text'] is String && part['type'] == null)
          {...part, 'type': 'text'}
        else
          part,
    ],
};
