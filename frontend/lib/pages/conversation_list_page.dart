import 'dart:async';

import 'package:flutter/material.dart';

import '../models/assistant.dart';
import '../models/conversation.dart';
import '../local_core/chat_generation_events.dart';
import '../local_core/group_chat/group_models.dart';
import '../services/config_service.dart';
import '../services/conversation_message_events.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_avatar.dart';
import '../widgets/asone_bottom_sheet.dart';
import '../widgets/asone_button.dart';
import '../widgets/asone_dialog.dart';
import '../widgets/asone_empty_state.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import '../widgets/assistant_picker_sheet.dart';
import '../widgets/anchored_popup_menu.dart';
import 'conversation_list_data_source.dart';
import 'conversation_list_routes.dart';

class ConversationListPage extends StatefulWidget {
  const ConversationListPage({
    super.key,
    this.refreshToken = 0,
    this.dataSource,
    this.groupDataSource,
  });

  final int refreshToken;
  final ConversationListDataSource? dataSource;
  final ConversationListGroupDataSource? groupDataSource;

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  late final ConversationListDataSource _dataSource =
      widget.dataSource ?? OpenCoreConversationListDataSource();
  final _addMenuKey = GlobalKey();
  List<Conversation> _conversations = [];
  List<Assistant> _assistants = [];
  Map<String, Assistant> _assistantMap = {};
  bool _loading = true;
  String? _loadError;
  AppConfig? _config;
  bool _isSearching = false;
  final _searchController = TextEditingController();
  List<Conversation> _filteredConversations = [];
  List<GroupRoom> _groups = [];
  List<GroupRoom> _filteredGroups = [];
  Map<String, List<GroupParticipant>> _groupParticipants = {};
  Map<String, int> _groupUnreadCounts = {};
  StreamSubscription<ChatGenerationEvent>? _generationSubscription;
  StreamSubscription<ConversationMessageEvent>? _messageSubscription;
  StreamSubscription<String>? _readSubscription;
  ConversationListGroupRefreshHandle? _groupRefresh;
  Future<void>? _conversationLoadFuture;
  Timer? _groupLoadTimeoutTimer;
  bool _conversationLoadPending = false;
  String? _deletingConversationId;
  final Set<String> _locallyDeletedConversationIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _generationSubscription = ChatGenerationEventBus.instance.events.listen(
      _onGenerationEvent,
    );
    _messageSubscription = ConversationMessageEvents.changes.listen((_) {
      _loadConversations();
    });
    _readSubscription = ConversationReadEvents.changes.listen(
      _clearConversationUnread,
    );
    _groupRefresh = ConversationListRoutes.createGroupRefresh?.call(
      _loadGroups,
    );
    _init();
  }

  @override
  void didUpdateWidget(covariant ConversationListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refreshData();
    }
  }

  @override
  void dispose() {
    _generationSubscription?.cancel();
    _messageSubscription?.cancel();
    _readSubscription?.cancel();
    final groupRefresh = _groupRefresh;
    if (groupRefresh != null) unawaited(groupRefresh.dispose());
    _groupLoadTimeoutTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onGenerationEvent(ChatGenerationEvent event) {
    if (!mounted) return;
    if (event is ChatGenerationDelta || event is ChatGenerationBoundary) {
      setState(() {});
      return;
    }
    _loadConversations();
  }

  void _onSearchChanged() {
    final keyword = _searchController.text.trim().toLowerCase();
    setState(() {
      if (keyword.isEmpty) {
        _filteredConversations = _conversations;
        _filteredGroups = _groups;
      } else {
        _filteredConversations = _conversations
            .where((c) => c.title.toLowerCase().contains(keyword))
            .toList();
        _filteredGroups = _groups
            .where((room) => room.title.toLowerCase().contains(keyword))
            .toList();
      }
    });
  }

  Future<void> _init() async {
    _config = await AppConfig.load();
    if (!mounted) return;
    await _refreshData();
  }

  Future<void> _refreshData() => _refreshDataOnce();

  Future<void> _refreshDataOnce() async {
    final config = await AppConfig.load();
    if (!mounted) return;
    setState(() => _config = config);
    await Future.wait([
      _loadAssistants(),
      _loadConversationsOnce(),
      _loadGroups(),
    ]);
  }

  Future<void> _loadAssistants() async {
    try {
      final list = await _dataSource.getAssistants().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() {
        _assistants = list;
        _assistantMap = {for (var a in list) a.id: a};
      });
    } catch (_) {
      // 加载失败不影响对话列表，助手名显示「助手」
    }
  }

  Future<void> _loadConversations() async {
    final active = _conversationLoadFuture;
    if (active != null) {
      _conversationLoadPending = true;
      await active;
      if (_conversationLoadPending && mounted) {
        _conversationLoadPending = false;
        await _loadConversationsOnce();
      }
      return;
    }
    final load = _loadConversationsLoop();
    _conversationLoadFuture = load;
    try {
      await load;
    } finally {
      if (identical(_conversationLoadFuture, load)) {
        _conversationLoadFuture = null;
      }
    }
  }

  Future<void> _loadConversationsLoop() async {
    do {
      _conversationLoadPending = false;
      await _loadConversationsOnce();
    } while (_conversationLoadPending && mounted);
  }

  Future<void> _loadConversationsOnce() async {
    setState(() {
      _loading = _conversations.isEmpty;
      _loadError = null;
    });
    try {
      final list = await _dataSource.getConversations().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      final visible = list
          .where((item) => !_locallyDeletedConversationIds.contains(item.id))
          .toList(growable: false);
      setState(() {
        _conversations = visible;
        _filteredConversations = visible;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '暂时无法读取对话，请确认当前构建模式后重试';
      });
      if (_conversations.isNotEmpty) _toast('刷新失败，已保留手机中的现有对话');
    }
  }

  void _clearConversationUnread(String conversationId) {
    if (!mounted) return;
    Conversation clear(Conversation item) =>
        item.id == conversationId ? item.copyWith(unreadCount: 0) : item;
    setState(() {
      _conversations = _conversations.map(clear).toList(growable: false);
      _filteredConversations = _filteredConversations
          .map(clear)
          .toList(growable: false);
    });
  }

  Future<void> _openConversation(
    Conversation conversation,
    Assistant? assistant,
  ) async {
    if (_config == null) return;
    final buildChatPage = ConversationListRoutes.buildChatPage;
    if (buildChatPage == null) {
      _toast('聊天页面尚未挂载');
      return;
    }
    _clearConversationUnread(conversation.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => buildChatPage(
          config: _config!,
          conversation: conversation,
          assistant: assistant,
        ),
      ),
    );
    if (!mounted) return;
    await _loadConversations();
  }

  Future<void> _loadGroups() async {
    final groupDataSource =
        widget.groupDataSource ?? ConversationListRoutes.groupDataSource;
    if (groupDataSource == null) {
      if (mounted) {
        setState(() {
          _groups = [];
          _filteredGroups = [];
          _groupParticipants = {};
          _groupUnreadCounts = {};
        });
      }
      return;
    }
    try {
      final rooms = await _waitForGroupLoad(groupDataSource.listRooms());
      final participants = <String, List<GroupParticipant>>{};
      final unreadCounts = <String, int>{};
      for (final room in rooms) {
        final details = await Future.wait<Object>([
          groupDataSource
              .getParticipants(room.roomId)
              .timeout(const Duration(seconds: 5)),
          groupDataSource
              .unreadCount(room.roomId)
              .timeout(const Duration(seconds: 5)),
        ]);
        participants[room.roomId] = details[0] as List<GroupParticipant>;
        unreadCounts[room.roomId] = details[1] as int;
      }
      if (!mounted) return;
      setState(() {
        _groups = rooms;
        _filteredGroups = rooms;
        _groupParticipants = participants;
        _groupUnreadCounts = unreadCounts;
      });
    } catch (_) {
      if (mounted && _groups.isNotEmpty) {
        _toast('群聊列表暂时无法刷新，已保留现有内容');
      }
    }
  }

  Future<T> _waitForGroupLoad<T>(Future<T> operation) {
    final completer = Completer<T>();
    _groupLoadTimeoutTimer?.cancel();
    _groupLoadTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('群聊列表加载超时', const Duration(seconds: 12)),
        );
      }
    });
    operation.then(
      (value) {
        _groupLoadTimeoutTimer?.cancel();
        _groupLoadTimeoutTimer = null;
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        _groupLoadTimeoutTimer?.cancel();
        _groupLoadTimeoutTimer = null;
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  Future<void> _createConversation() async {
    await _refreshData();
    if (!mounted) return;
    final boundAssistantIds = _conversations
        .map((conversation) => conversation.assistantId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final availableAssistants = _assistants
        .where((assistant) => !boundAssistantIds.contains(assistant.id))
        .toList(growable: false);
    if (availableAssistants.isEmpty) {
      _toast(_assistants.isEmpty ? '请先创建助手' : '每个助手只能有一个对话，请先新建助手或打开现有对话');
      return;
    }
    final selected = await showAssistantPicker<Assistant>(
      context,
      options: [
        for (final assistant in availableAssistants)
          AssistantPickerOption(assistant: assistant, value: assistant),
      ],
      emptyMessage: '每个助手只能有一个对话，请先新建助手或打开现有对话',
    );
    final selectedAssistant = selected?.value;

    if (selectedAssistant == null) return;

    try {
      final conv = await _dataSource.createConversation(
        selectedAssistant.name,
        assistantId: selectedAssistant.id,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) {
            final buildChatPage = ConversationListRoutes.buildChatPage;
            if (buildChatPage == null) return const SizedBox.shrink();
            return buildChatPage(
              config: _config!,
              conversation: conv,
              assistant: selectedAssistant,
            );
          },
        ),
      );
      if (!mounted) return;
      await _loadConversations();
    } catch (e) {
      if (!mounted) return;
      _toast(_friendlyOperationError(e, '暂时无法创建对话，请稍后重试'));
    }
  }

  Future<void> _deleteConversation(Conversation conv) async {
    if (_deletingConversationId != null) return;
    _deletingConversationId = conv.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AsOneDialog(
        icon: asOneIconData(AsOneIconName.delete),
        iconColor: AsOneTheme.danger,
        title: '删除对话',
        content: const Text('确定删除吗？该对话产生的其他内容也会被删除。'),
        actions: [
          AsOneButton(
            label: '取消',
            tone: AsOneButtonTone.secondary,
            onPressed: () => Navigator.pop(context, false),
          ),
          AsOneButton(
            label: '删除',
            tone: AsOneButtonTone.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      _deletingConversationId = null;
      return;
    }

    try {
      await _dataSource.deleteConversation(conv.id);
      if (!mounted) return;
      setState(() {
        _locallyDeletedConversationIds.add(conv.id);
        _conversations.removeWhere((item) => item.id == conv.id);
        _filteredConversations.removeWhere((item) => item.id == conv.id);
      });
      _toast('已删除');
      unawaited(_loadConversations());
    } catch (e) {
      if (!mounted) return;
      _toast(_friendlyOperationError(e, '暂时无法删除对话，请稍后重试'));
    } finally {
      _deletingConversationId = null;
    }
  }

  Future<void> _toggleConversationPinned(Conversation conv) async {
    try {
      await _dataSource.setConversationPinned(conv.id, pinned: !conv.isPinned);
      await _loadConversations();
    } catch (e) {
      if (!mounted) return;
      _toast(
        _friendlyOperationError(
          e,
          conv.isPinned ? '暂时无法取消置顶，请稍后重试' : '暂时无法置顶，请稍后重试',
        ),
      );
    }
  }

  Future<void> _showConversationMenu(Conversation conv) async {
    if (_deletingConversationId != null) return;
    final action = await AsOneBottomSheet.showActions<String>(
      context,
      title: _buildTitle(conv),
      actions: [
        AsOneSheetAction(
          value: 'pin',
          label: conv.isPinned ? '取消置顶' : '置顶',
          icon: AsOneIconName.pin,
        ),
        const AsOneSheetAction(
          value: 'delete',
          label: '删除',
          icon: AsOneIconName.delete,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    if (action == 'pin') {
      await _toggleConversationPinned(conv);
    } else if (action == 'delete') {
      await _deleteConversation(conv);
    }
  }

  void _toast(String msg) {
    AsOneToast.show(context, msg);
  }

  String _friendlyOperationError(Object error, String fallback) {
    if (error is StateError) return error.message.toString();
    return fallback;
  }

  String _buildSubtitle(Conversation conv) {
    final generation = ChatGenerationEventBus.instance.snapshotForConversation(
      conv.id,
    );
    if (generation != null) {
      if (generation.toolName != null) {
        return '正在使用工具...';
      }
      final content = generation.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      return content.isEmpty ? '正在输入...' : content;
    }
    if (conv.hasDraft) {
      final preview = conv.draftText.replaceAll(RegExp(r'\s+'), ' ').trim();
      return '[草稿]$preview';
    }
    final preview = conv.lastMessage;
    if (preview != null && preview.isNotEmpty) {
      return preview;
    }
    final assistantId = conv.assistantId;
    if (assistantId == null || assistantId.isEmpty) {
      return '未选择助手';
    }
    return '';
  }

  String _buildTitle(Conversation conv) {
    if (conv.hasDraft || conv.lastMessage?.isNotEmpty == true) {
      return conv.title;
    }
    final assistant = _assistantMap[conv.assistantId];
    if (assistant != null && conv.title.trim() == '与 ${assistant.name} 的对话') {
      return assistant.name;
    }
    final title = conv.title.trim();
    if (title.startsWith('与') && title.endsWith('的对话') && title.length > 4) {
      return title.substring(1, title.length - 3).trim();
    }
    return conv.title;
  }

  String _formatLastMessageTime(DateTime? value) {
    if (value == null) return '';
    final time = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(time.year, time.month, time.day);
    final days = today.difference(date).inDays;
    if (days == 0) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (days == 1) return '\u6628\u5929';
    if (days > 1 && days < 7) {
      const weekdays = [
        '\u5468\u4e00',
        '\u5468\u4e8c',
        '\u5468\u4e09',
        '\u5468\u56db',
        '\u5468\u4e94',
        '\u5468\u516d',
        '\u5468\u65e5',
      ];
      return weekdays[time.weekday - 1];
    }
    if (time.year == now.year) {
      return '${time.month}\u6708${time.day}\u65e5';
    }
    return '${time.year}/${time.month}/${time.day}';
  }

  Future<void> _showAddMenu() async {
    final selected = await showAnchoredPopupMenu<String>(
      context: context,
      anchorKey: _addMenuKey,
      rowHeight: 48,
      entries: const [
        AnchoredPopupMenuEntry(
          value: 'new_chat',
          label: '新建对话',
          icon: AsOneIconName.message,
        ),
        AnchoredPopupMenuEntry(
          value: 'new_group',
          label: '新建群聊',
          icon: AsOneIconName.users,
        ),
      ],
    );
    if (selected == 'new_chat' && mounted) {
      await _createConversation();
    } else if (selected == 'new_group' && mounted) {
      await _loadAssistants();
      if (!mounted) return;
      if (_assistants.length < 2) {
        _toast('请先创建至少两名助手');
        return;
      }
      final buildGroupCreatePage = ConversationListRoutes.buildGroupCreatePage;
      if (buildGroupCreatePage == null) {
        _toast('群聊创建页面尚未挂载');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => buildGroupCreatePage(assistants: _assistants),
        ),
      );
      if (mounted) await _loadGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = <Object>[..._filteredConversations, ..._filteredGroups]
      ..sort((a, b) {
        final pinnedOrder = (b is Conversation && b.isPinned ? 1 : 0).compareTo(
          a is Conversation && a.isPinned ? 1 : 0,
        );
        if (pinnedOrder != 0) return pinnedOrder;
        final aTime = a is Conversation
            ? a.listActivityAt
            : (a as GroupRoom).listActivityAt;
        final bTime = b is Conversation
            ? b.listActivityAt
            : (b as GroupRoom).listActivityAt;
        return (bTime ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          aTime ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
    return Scaffold(
      backgroundColor: AsOneTheme.mainPageBg,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索对话...',
                  border: InputBorder.none,
                ),
              )
            : const Text('对话'),
        automaticallyImplyLeading: false,
        backgroundColor: AsOneTheme.mainHeaderBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 55,
        actions: [
          if (_isSearching)
            AsOneIconButton(
              icon: AsOneIconName.close,
              tooltip: '退出搜索',
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _filteredConversations = _conversations;
                });
              },
            )
          else ...[
            AsOneIconButton(
              icon: AsOneIconName.search,
              tooltip: '搜索',
              onPressed: () {
                final buildSearchPage = ConversationListRoutes.buildSearchPage;
                if (buildSearchPage == null) {
                  _toast('搜索页面尚未挂载');
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => buildSearchPage()),
                );
              },
            ),
            AsOneIconButton(
              key: _addMenuKey,
              icon: AsOneIconName.add,
              tooltip: '新建对话',
              onPressed: _showAddMenu,
            ),
          ],
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AsOneTheme.mainHeaderDivider),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _conversations.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  AsOneButton(
                    label: '重新加载',
                    tone: AsOneButtonTone.secondary,
                    onPressed: _loadConversations,
                  ),
                ],
              ),
            )
          : entries.isEmpty
          ? AsOneEmptyState(
              icon: asOneIconData(AsOneIconName.message),
              title: _isSearching ? '没有找到匹配的对话' : '还没有对话',
              description: _isSearching ? null : '点右上角加号开始一段对话',
            )
          : RefreshIndicator(
              onRefresh: _refreshData,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                separatorBuilder: (_, index) => const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 76,
                  color: Color(0x80D9D9D9),
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  if (entry is GroupRoom) {
                    final buildGroupPage =
                        ConversationListRoutes.buildGroupPage;
                    final participantIds =
                        (_groupParticipants[entry.roomId] ??
                                const <GroupParticipant>[])
                            .map((item) => item.assistantId)
                            .toList(growable: false);
                    return _GroupConversationTile(
                      key: ValueKey('group-tile-${entry.roomId}'),
                      room: entry,
                      assistants: participantIds
                          .map((id) => _assistantMap[id])
                          .whereType<Assistant>()
                          .toList(),
                      time: _formatLastMessageTime(entry.listActivityAt),
                      unreadCount: _groupUnreadCounts[entry.roomId] ?? 0,
                      onTap: () async {
                        if (buildGroupPage == null) {
                          _toast('群聊页面尚未挂载');
                          return;
                        }
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => buildGroupPage(
                              roomId: entry.roomId,
                              assistants: _assistants,
                            ),
                          ),
                        );
                        if (mounted) await _loadGroups();
                      },
                    );
                  }
                  final conv = entry as Conversation;
                  return _ConversationDesignTile(
                    key: ValueKey('conversation-tile-${conv.id}'),
                    title: _buildTitle(conv),
                    subtitle: _buildSubtitle(conv),
                    time: _formatLastMessageTime(conv.listActivityAt),
                    assistant: _assistantMap[conv.assistantId],
                    unreadCount: conv.unreadCount,
                    onTap: () => _openConversation(
                      conv,
                      _assistantMap[conv.assistantId],
                    ),
                    onLongPress: () => _showConversationMenu(conv),
                  );
                },
              ),
            ),
    );
  }
}

class _GroupConversationTile extends StatelessWidget {
  const _GroupConversationTile({
    super.key,
    required this.room,
    required this.assistants,
    required this.time,
    required this.unreadCount,
    required this.onTap,
  });

  final GroupRoom room;
  final List<Assistant> assistants;
  final String time;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 76,
        child: Row(
          children: [
            const SizedBox(width: 14),
            SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                children: [
                  for (
                    var index = 0;
                    index < assistants.take(3).length;
                    index++
                  )
                    Positioned(
                      left: index * 12,
                      top: index.isEven ? 0 : 17,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFFFE1D8),
                        child: Text(
                          assistants[index].name.isEmpty
                              ? '?'
                              : assistants[index].name[0],
                          style: const TextStyle(
                            fontSize: 12,
                            color: AsOneTheme.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AsOneTheme.listTitleStyle,
                        ),
                      ),
                      Text(time, style: AsOneTheme.captionStyle),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.draftText.isNotEmpty
                              ? '[草稿]${room.draftText}'
                              : room.lastMessagePreview?.isNotEmpty == true
                              ? room.lastMessagePreview!
                              : '${assistants.length} 名助手',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AsOneTheme.secondaryStyle,
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(count: unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    ),
  );
}

class _ConversationDesignTile extends StatelessWidget {
  const _ConversationDesignTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.assistant,
    required this.unreadCount,
    required this.onTap,
    required this.onLongPress,
  });

  final String title;
  final String subtitle;
  final String time;
  final Assistant? assistant;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        highlightColor: const Color(0xFFFFEDE7),
        splashColor: Colors.transparent,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              const SizedBox(width: 14),
              AsOneAvatar.assistant(
                imagePath: assistant?.avatar ?? '',
                name: assistant?.name ?? '助手',
                size: 50,
                borderRadius: 14,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AsOneTheme.listTitleStyle,
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: AsOneTheme.captionStyle.copyWith(
                              color: AsOneTheme.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: AsOneTheme.secondaryStyle,
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Semantics(
      label: '$count 条未读消息',
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AsOneTheme.notificationBadge,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
