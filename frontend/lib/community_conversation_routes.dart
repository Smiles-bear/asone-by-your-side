import 'models/assistant.dart';
import 'models/conversation.dart';
import 'local_core/group_chat/group_models.dart';
import 'pages/conversation_list_data_source.dart';
import 'pages/conversation_list_routes.dart';
import 'services/config_service.dart';

import 'community_chat_page.dart';
import 'community_group_page.dart';
import 'public_core.dart';

/// 将正式版会话列表的导航接到社区版公开聊天实现。
///
/// 列表页、搜索/新建入口和布局保持正式版；具体聊天与群聊页面仍由社区
/// 核心提供，私有版的语音、记忆、工具和后台能力不会进入公共闭包。
void attachCommunityConversationRoutes() {
  ConversationListRoutes.buildChatPage =
      ({
        required AppConfig config,
        required Conversation conversation,
        required Assistant? assistant,
      }) => CommunityChatPage(
        initialConversation: conversation,
        initialAssistant: assistant,
      );
  ConversationListRoutes.buildGroupPage =
      ({required String roomId, required List<Assistant> assistants}) =>
          CommunityGroupPage(initialRoomId: roomId);
  ConversationListRoutes.buildGroupCreatePage = ({required assistants}) =>
      const CommunityGroupPage();
  ConversationListRoutes.groupDataSource = _CommunityGroupDataSource();
}

/// 正式版列表页只需要这三个公开群聊查询，不接触私有群聊生命周期。
final class _CommunityGroupDataSource
    implements ConversationListGroupDataSource {
  PublicCore? get _core {
    final core = OpenCoreBinding.instance;
    return core is PublicCore ? core : null;
  }

  @override
  Future<List<GroupRoom>> listRooms() async =>
      _core?.groupChat.listRooms() ?? const <GroupRoom>[];

  @override
  Future<List<GroupParticipant>> getParticipants(String roomId) async =>
      _core?.groupChat.participantsForRoom(roomId) ??
      const <GroupParticipant>[];

  @override
  Future<int> unreadCount(String roomId) async =>
      _core == null ? 0 : await _core!.groupRooms.unreadCount(roomId);
}
