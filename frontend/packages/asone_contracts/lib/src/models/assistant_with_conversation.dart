import 'assistant.dart';
import 'conversation.dart';

/// Assistant and its primary conversation.
class AssistantWithConversation {
  const AssistantWithConversation({
    required this.assistant,
    required this.conversation,
  });

  final Assistant assistant;
  final Conversation conversation;

  @override
  String toString() =>
      'AssistantWithConversation(assistant: ${assistant.id}, conversation: ${conversation.id})';
}
