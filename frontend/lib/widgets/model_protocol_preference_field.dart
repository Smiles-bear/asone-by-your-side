import 'package:flutter/material.dart';
import '../services/provider_adapters/protocol_types.dart';

const modelProtocolLabels = {
  ProtocolType.auto: '自动',
  ProtocolType.openaiChat: 'OpenAI Chat',
  ProtocolType.openaiResponses: 'OpenAI Responses',
  ProtocolType.anthropicMessages: 'Anthropic Messages',
  ProtocolType.gemini: 'Gemini',
};

class ModelProtocolPreferenceField extends StatelessWidget {
  const ModelProtocolPreferenceField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('高级设置'),
    subtitle: Text(
      value == ProtocolType.auto
          ? '接口协议默认自动匹配'
          : '接口协议：${modelProtocolLabels[value] ?? value}',
    ),
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('model-protocol-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '接口协议'),
          items: [
            for (final entry in modelProtocolLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (selection) {
            if (selection != null) onChanged(selection);
          },
        ),
      ),
    ],
  );
}
