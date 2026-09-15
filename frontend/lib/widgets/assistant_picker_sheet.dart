import 'package:flutter/material.dart';

import '../models/assistant.dart';
import '../models/conversation.dart';
import '../theme/asone_theme.dart';
import 'asone_bottom_sheet.dart';
import 'asone_feedback.dart';
import 'live_assistant_avatar.dart';

class AssistantPickerOption<T> {
  const AssistantPickerOption({required this.assistant, required this.value});

  final Assistant assistant;
  final T value;
}

class AssistantConversationSelection {
  const AssistantConversationSelection({
    required this.assistant,
    required this.conversation,
  });

  final Assistant assistant;
  final Conversation conversation;
}

/// Resolves the single active conversation that belongs to each assistant.
/// Ambiguous historical data is excluded instead of silently binding a
/// different conversation.
List<AssistantConversationSelection> eligibleAssistantConversations(
  List<Assistant> assistants,
  List<Conversation> conversations,
) {
  final byAssistant = <String, List<Conversation>>{};
  for (final conversation in conversations) {
    final assistantId = conversation.assistantId;
    if (assistantId == null ||
        conversation.kind != 'single' ||
        conversation.status != 'active') {
      continue;
    }
    byAssistant.putIfAbsent(assistantId, () => []).add(conversation);
  }
  return [
    for (final assistant in assistants)
      if (byAssistant[assistant.id] case final matches?
          when matches.length == 1)
        AssistantConversationSelection(
          assistant: assistant,
          conversation: matches.single,
        ),
  ];
}

Future<AssistantPickerOption<T>?> showAssistantPicker<T>(
  BuildContext context, {
  required List<AssistantPickerOption<T>> options,
  String emptyMessage = '还没有可用对话，请先与助手开始聊天',
  Future<Assistant?> Function(String id)? loadAssistant,
}) {
  if (options.isEmpty) {
    AsOneToast.show(context, emptyMessage);
    return Future.value(null);
  }
  final screenHeight = MediaQuery.sizeOf(context).height;
  final desiredHeight = 78.0 + options.length * 58.0;
  final heightFactor = (desiredHeight / screenHeight).clamp(0.24, 0.82);
  return AsOneBottomSheet.showContent<AssistantPickerOption<T>>(
    context,
    heightFactor: heightFactor,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text('选择助手', style: AsOneTheme.sectionTitleStyle),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              final assistant = option.assistant;
              return LiveAssistantAvatar(
                assistantId: assistant.id,
                initialPath: assistant.avatar,
                initialName: assistant.name,
                size: 42,
                borderRadius: 8,
                loadAssistant: loadAssistant,
                builder: (context, avatar, name) => ListTile(
                  key: ValueKey('assistant-picker-${assistant.id}'),
                  leading: avatar,
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
