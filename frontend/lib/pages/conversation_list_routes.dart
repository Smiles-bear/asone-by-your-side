import 'package:flutter/widgets.dart';

import '../models/assistant.dart';
import '../models/conversation.dart';
import '../services/config_service.dart';
import 'conversation_list_data_source.dart';

typedef ConversationListChatPageBuilder =
    Widget Function({
      required AppConfig config,
      required Conversation conversation,
      required Assistant? assistant,
    });

typedef ConversationListGroupPageBuilder =
    Widget Function({
      required String roomId,
      required List<Assistant> assistants,
    });

typedef ConversationListGroupCreatePageBuilder =
    Widget Function({required List<Assistant> assistants});

typedef ConversationListGroupRefreshFactory =
    ConversationListGroupRefreshHandle Function(
      Future<void> Function() refresh,
    );

abstract interface class ConversationListGroupRefreshHandle {
  Future<void> dispose();
}

/// 会话列表的可选页面宿主。
///
/// 列表页只保留展示和公开数据契约；私有版将完整聊天、群聊和刷新事件
/// 挂载到这里，社区版可以不挂载或换成自己的公开页面。
final class ConversationListRoutes {
  ConversationListRoutes._();

  static ConversationListGroupDataSource? groupDataSource;
  static ConversationListChatPageBuilder? buildChatPage;
  static ConversationListGroupPageBuilder? buildGroupPage;
  static ConversationListGroupCreatePageBuilder? buildGroupCreatePage;
  static Widget Function()? buildSearchPage;
  static ConversationListGroupRefreshFactory? createGroupRefresh;
}
