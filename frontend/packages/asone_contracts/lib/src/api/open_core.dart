import 'assistant_repository_api.dart';
import 'calendar_repository_api.dart';
import 'capability_detection_api.dart';
import 'conversation_repository_api.dart';
import 'feature_unread_api.dart';
import 'message_board_repository_api.dart';
import 'model_discovery_api.dart';
import 'model_service_repository_api.dart';
import 'sticky_note_repository_api.dart';
import 'token_usage_api.dart';

/// Aggregate of the public core capability contracts.
///
/// Each edition attaches its own implementation at startup: the private
/// edition attaches its full core, community builds attach a demo core.
abstract interface class OpenCore {
  AssistantRepositoryApi get assistants;

  ConversationRepositoryApi get conversations;

  ModelServiceRepositoryApi get modelServices;

  ModelDiscoveryApi get modelDiscovery;

  CapabilityDetectionApi get capabilityDetection;

  CalendarRepositoryApi get calendar;

  StickyNoteRepositoryApi get stickyNotes;

  MessageBoardRepositoryApi get messageBoard;

  FeatureUnreadApi get featureUnread;

  TokenUsageApi get tokenUsage;
}

/// Process-wide binding point that connects UI code to the active [OpenCore].
final class OpenCoreBinding {
  OpenCoreBinding._();

  static OpenCore? _instance;

  /// The attached core; throws [StateError] before [attach] is called.
  static OpenCore get instance {
    final core = _instance;
    if (core == null) {
      throw StateError('OpenCoreBinding.instance accessed before attach().');
    }
    return core;
  }

  static void attach(OpenCore core) {
    _instance = core;
  }

  static void detach() {
    _instance = null;
  }
}
