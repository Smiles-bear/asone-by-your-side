import 'message.dart';

class ConversationMessagePage {
  const ConversationMessagePage({
    required this.messages,
    required this.hasOlder,
    required this.hasNewer,
  });

  final List<Message> messages;
  final bool hasOlder;
  final bool hasNewer;
}
