import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'pages/model_service_list_page.dart';
import 'theme/asone_theme.dart';
import 'widgets/anchored_popup_menu.dart';
import 'widgets/asone_avatar.dart';
import 'widgets/asone_bottom_sheet.dart';
import 'widgets/asone_chat_composer_parts.dart';
import 'widgets/asone_dialog.dart';
import 'widgets/asone_feedback.dart';
import 'widgets/asone_icons.dart';

import 'community_chat_search_page.dart';
import 'community_group_page.dart';
import 'public_core.dart';

/// 社区版基础 API 聊天。
///
/// 页面结构、输入栏、消息操作和错误反馈与正式版保持一致；社区版只执行
/// 公开的文字 API 聊天，不加载语音、工具、记忆或后台主动能力。
class CommunityChatPage extends StatefulWidget {
  const CommunityChatPage({
    super.key,
    this.initialConversation,
    this.initialAssistant,
  });

  final Conversation? initialConversation;
  final Assistant? initialAssistant;

  @override
  State<CommunityChatPage> createState() => _CommunityChatPageState();
}

class _CommunityChatPageState extends State<CommunityChatPage> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  final _attachmentMenuKey = GlobalKey();
  final _chatMoreMenuKey = GlobalKey();
  List<ModelService> _services = const [];
  List<MessageContract> _messages = const [];
  ModelService? _service;
  Assistant? _assistant;
  Conversation? _conversation;
  String _streamedReply = '';
  String? _error;
  bool _loading = true;
  bool _sending = false;
  int? _expandedMessageIndex;
  CancelToken? _cancelToken;
  Timer? _draftTimer;
  bool _draftLoaded = false;

  List<ModelService> get _chatServices => _services
      .where((service) {
        final endpoint = service.baseUrl.trim();
        return endpoint.isNotEmpty &&
            !endpoint.contains('example.invalid') &&
            service.model.trim().isNotEmpty;
      })
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onDraftChanged);
    _load();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    unawaited(_persistDraft());
    _cancelToken?.cancel('页面已关闭');
    _composer.removeListener(_onDraftChanged);
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final core = OpenCoreBinding.instance;
      final services = await core.modelServices.getModelServices();
      final conversation = widget.initialConversation;
      Assistant? assistant = widget.initialAssistant;
      final assistantId = conversation?.assistantId;
      if (assistant == null && assistantId != null && assistantId.isNotEmpty) {
        assistant = await core.assistants.getAssistant(assistantId);
      }
      ModelService? service;
      if (assistant != null) {
        final matches = services.where(
          (item) => item.id == assistant!.modelServiceId,
        );
        if (matches.isNotEmpty) service = matches.first;
      }

      var messages = const <MessageContract>[];
      var draft = '';
      if (conversation != null) {
        messages = await core.messages.getMessages(conversation.id);
        draft = await core.conversations.getConversationDraft(conversation.id);
        await core.conversations.markConversationRead(conversation.id);
      }
      if (!mounted) return;
      final usableService = service != null &&
          services.any((item) => item.id == service!.id) &&
          service!.baseUrl.trim().isNotEmpty &&
          !service!.baseUrl.contains('example.invalid') &&
          service!.model.trim().isNotEmpty;
      setState(() {
        _services = services;
        _assistant = assistant;
        _service = usableService ? service : null;
        _conversation = conversation;
        _messages = messages;
        _loading = false;
      });
      if (draft.isNotEmpty) _composer.text = draft;
      _draftLoaded = true;
      _scrollToBottom(force: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '聊天初始化失败，请稍后重试：${error.toString()}';
      });
    }
  }

  void _onDraftChanged() {
    if (!_draftLoaded || _conversation == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 420), _persistDraft);
  }

  Future<void> _persistDraft() async {
    final conversation = _conversation;
    if (!_draftLoaded || conversation == null) return;
    try {
      await OpenCoreBinding.instance.conversations.saveConversationDraft(
        conversation.id,
        _composer.text,
      );
    } catch (_) {
      // 草稿保存失败不影响当前聊天。
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (force) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _reloadMessages() async {
    final conversation = _conversation;
    if (conversation == null) return;
    try {
      final messages = await OpenCoreBinding.instance.messages.getMessages(
        conversation.id,
      );
      if (!mounted) return;
      setState(() => _messages = messages);
    } catch (_) {
      if (mounted) _toast('消息加载失败，请稍后重试');
    }
  }

  Future<void> _openModelServices() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ModelServiceListPage()),
    );
    await _load();
  }

  Future<void> _showChatMenu() async {
    _collapseMessageActions();
    final selected = await showAnchoredPopupMenu<String>(
      context: context,
      anchorKey: _chatMoreMenuKey,
      rowHeight: 48,
      entries: const [
        AnchoredPopupMenuEntry(
          value: 'search',
          label: '搜索聊天记录',
          icon: AsOneIconName.search,
        ),
        AnchoredPopupMenuEntry(
          value: 'model',
          label: '模型服务',
          icon: AsOneIconName.settings,
        ),
        AnchoredPopupMenuEntry(
          value: 'group',
          label: 'API 群聊',
          icon: AsOneIconName.users,
        ),
      ],
    );
    if (!mounted) return;
    switch (selected) {
      case 'search':
        final conversation = _conversation;
        if (conversation == null) {
          _toast('当前还没有可搜索的对话');
          return;
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CommunityChatSearchPage(
              conversationId: conversation.id,
              conversationTitle: conversation.title,
            ),
          ),
        );
      case 'model':
        await _openModelServices();
      case 'group':
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const CommunityGroupPage()),
        );
    }
  }

  Future<void> _showAttachmentMenu() async {
    if (_sending) return;
    final selected = await showAnchoredPopupMenu<String>(
      context: context,
      anchorKey: _attachmentMenuKey,
      direction: AnchoredPopupDirection.above,
      rowHeight: 40,
      showDividers: true,
      entries: const [
        AnchoredPopupMenuEntry(
          value: '相机',
          label: '相机',
          icon: AsOneIconName.camera,
        ),
        AnchoredPopupMenuEntry(
          value: '链接',
          label: '链接',
          icon: AsOneIconName.link,
        ),
        AnchoredPopupMenuEntry(
          value: '文件',
          label: '文件',
          icon: AsOneIconName.document,
        ),
        AnchoredPopupMenuEntry(
          value: '图片',
          label: '图片',
          icon: AsOneIconName.image,
        ),
      ],
    );
    if (selected != null && mounted) _toast('$selected 暂未开放，敬请期待');
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final conversation = _conversation;
    final core = OpenCoreBinding.instance;
    if (text.isEmpty || _sending) return;
    if (conversation == null || _service == null || core is! PublicCore) {
      _toast('请先从助手页面创建对话并配置可用的模型服务');
      return;
    }
    _draftTimer?.cancel();
    await _persistDraft();
    _cancelToken = CancelToken();
    if (!mounted) return;
    setState(() {
      _composer.clear();
      _streamedReply = '';
      _error = null;
      _sending = true;
      _expandedMessageIndex = null;
    });
    unawaited(_persistDraft());
    _scrollToBottom();

    try {
      String? failure;
      await core.chat.send(
        conversationId: conversation.id,
        content: text,
        userAlreadyPersisted: false,
        cancelToken: _cancelToken,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() => _streamedReply += delta);
          _scrollToBottom();
        },
        onDone: ({String? error}) => failure = error,
      );
      final messages = await core.messages.getMessages(conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _streamedReply = '';
        _error = failure == null ? null : _failureMessage(failure!);
      });
      _scrollToBottom();
    } catch (error) {
      if (mounted) setState(() => _error = _failureMessage(error.toString()));
    } finally {
      _cancelToken = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stopSending() async {
    if (!_sending) return;
    _cancelToken?.cancel('用户停止生成');
  }

  String _failureMessage(String detail) {
    final normalized = detail.trim();
    if (normalized.isEmpty) return '模型服务未返回可用内容，请检查配置后重试。';
    return '模型服务调用失败：$normalized';
  }

  void _collapseMessageActions() {
    if (_expandedMessageIndex != null && mounted) {
      setState(() => _expandedMessageIndex = null);
    }
  }

  void _toggleMessageActions(int index) {
    setState(() {
      _expandedMessageIndex = _expandedMessageIndex == index ? null : index;
    });
  }

  List<String> _actionsFor(MessageContract message) => [
    'copy',
    'quote',
    if (message.role == MessageRole.user) 'edit',
    if (message.role == MessageRole.assistant) 'regenerate',
    'delete',
  ];

  Future<void> _showMessageMenu(MessageContract message) async {
    final action = await AsOneBottomSheet.showActions<String>(
      context,
      title: '消息操作',
      actions: [
        for (final value in _actionsFor(message))
          AsOneSheetAction(
            value: value,
            label: _actionLabel(value),
            icon: _actionIcon(value),
            destructive: value == 'delete',
          ),
      ],
    );
    if (action != null && mounted) await _performMessageAction(message, action);
  }

  String _actionLabel(String action) => switch (action) {
    'copy' => '复制',
    'quote' => '引用',
    'edit' => '编辑',
    'regenerate' => '重新生成',
    'delete' => '删除',
    _ => action,
  };

  AsOneIconName _actionIcon(String action) => switch (action) {
    'copy' => AsOneIconName.copy,
    'quote' => AsOneIconName.message,
    'edit' => AsOneIconName.edit,
    'regenerate' => AsOneIconName.refresh,
    'delete' => AsOneIconName.delete,
    _ => AsOneIconName.info,
  };

  Future<void> _performMessageAction(
    MessageContract message,
    String action,
  ) async {
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.content));
        if (mounted) _toast('已复制');
      case 'quote':
        final quoted = '> ${message.content.replaceAll('\n', '\n> ')}\n\n';
        _composer.text = quoted + _composer.text;
        _composer.selection = TextSelection.fromPosition(
          TextPosition(offset: _composer.text.length),
        );
        if (mounted) _toast('已引用');
      case 'edit':
        await _editMessage(message);
      case 'regenerate':
        _toast('重新生成暂未开放，敬请期待');
      case 'delete':
        await _deleteMessage(message);
    }
  }

  Future<void> _editMessage(MessageContract message) async {
    final controller = TextEditingController(text: message.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AsOneDialog(
        icon: asOneIconData(AsOneIconName.edit),
        title: '编辑消息',
        content: TextField(
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入消息内容',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || result == message.content) return;
    try {
      await OpenCoreBinding.instance.messages.updateMessage(message.id, result);
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((item) => item.id == message.id);
        if (index >= 0) {
          _messages = [
            ..._messages.sublist(0, index),
            MessageContract(
              id: message.id,
              conversationId: message.conversationId,
              role: message.role,
              content: result,
              createdAt: message.createdAt,
              answerStatus: message.answerStatus,
              failureHint: message.failureHint,
              elapsedMs: message.elapsedMs,
              hasToolTrace: message.hasToolTrace,
              reasoning: message.reasoning,
              attachments: message.attachments,
            ),
            ..._messages.sublist(index + 1),
          ];
        }
      });
      _toast('已更新');
    } catch (_) {
      if (mounted) _toast('消息更新失败，请稍后重试');
    }
  }

  Future<void> _deleteMessage(MessageContract message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AsOneDialog(
        icon: asOneIconData(AsOneIconName.delete),
        iconColor: AsOneTheme.danger,
        title: '删除消息',
        content: const Text('删除这条消息？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: AsOneTheme.dangerConfirmStyle(),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await OpenCoreBinding.instance.messages.deleteMessage(message.id);
      if (!mounted) return;
      setState(
        () => _messages = _messages
            .where((item) => item.id != message.id)
            .toList(),
      );
      _toast('已删除');
    } catch (_) {
      if (mounted) _toast('暂时无法删除消息，请稍后重试');
    }
  }

  void _toast(String message) => AsOneToast.show(context, message);

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    final hasService = _service != null;
    return Scaffold(
      backgroundColor: AsOneTheme.chatBgFor('default'),
      appBar: AppBar(
        backgroundColor: AsOneTheme.pageBg,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: AsOneTheme.pageBg,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: AsOneTheme.pageBg,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 64,
        centerTitle: true,
        leading: AsOneIconButton(
          icon: AsOneIconName.back,
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              conversation?.title ?? '对话',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AsOneTheme.pageTitleStyle,
            ),
            const SizedBox(height: 2),
            const Text(
              '内容由AI生成，请注意甄别',
              style: TextStyle(fontSize: 10, color: AsOneTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          AsOneIconButton(
            key: _chatMoreMenuKey,
            icon: AsOneIconName.more,
            tooltip: '更多',
            onPressed: _showChatMenu,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !hasService
                ? _buildConfigureState()
                : _buildMessages(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFC94D45),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          KeyedSubtree(
            key: const Key('community-chat-composer'),
            child: AsOneChatInputBar(
              controller: _composer,
              busy: _sending,
              voiceEnabled: false,
              attachmentMenuOpen: false,
              onSend: _send,
              onStop: _stopSending,
              onAdd: _showAttachmentMenu,
              onVoiceStart: () async => false,
              onVoiceFinish: () async {},
              onVoiceToText: () async {},
              onVoiceCancel: () async {},
              onVoiceAmplitude: () => const Stream<double>.empty(),
              addButtonKey: _attachmentMenuKey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigureState() {
    final noConversation = _conversation == null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(noConversation ? '请先从助手页面创建对话' : '请先配置可用的模型服务'),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('community-chat-configure-model'),
            onPressed: noConversation ? null : _openModelServices,
            icon: const Icon(Icons.tune_outlined),
            label: const Text('配置模型服务'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    final items = [..._messages];
    if (_streamedReply.isNotEmpty) {
      items.add(
        MessageContract(
          id: '_streaming',
          conversationId: _conversation?.id ?? '',
          role: MessageRole.assistant,
          content: _streamedReply,
          createdAt: DateTime.now(),
          answerStatus: MessageAnswerStatus.streaming,
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Text('开始对话吧', style: TextStyle(color: AsOneTheme.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _reloadMessages,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _collapseMessageActions,
        child: ListView.builder(
          key: const Key('community-chat-messages'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final message = items[index];
            final streaming =
                message.answerStatus == MessageAnswerStatus.streaming;
            return _CommunityMessageBubble(
              message: message,
              assistant: _assistant,
              actionsExpanded: !streaming && _expandedMessageIndex == index,
              onTap: streaming ? null : () => _toggleMessageActions(index),
              onLongPress: streaming ? null : () => _showMessageMenu(message),
              actions: streaming ? const [] : _actionsFor(message),
              actionLabel: _actionLabel,
              actionIcon: _actionIcon,
              onAction: (action) => _performMessageAction(message, action),
            );
          },
        ),
      ),
    );
  }
}

class _CommunityMessageBubble extends StatelessWidget {
  const _CommunityMessageBubble({
    required this.message,
    required this.assistant,
    required this.actionsExpanded,
    required this.onTap,
    required this.onLongPress,
    required this.actions,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final MessageContract message;
  final Assistant? assistant;
  final bool actionsExpanded;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<String> actions;
  final String Function(String) actionLabel;
  final AsOneIconName Function(String) actionIcon;
  final Future<void> Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final bubbleColor = isUser ? AsOneTheme.userBubble : AsOneTheme.aiBubble;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.attachments.isNotEmpty) ...[
          for (final attachment in message.attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AsOneIcon(
                    attachment.isLink
                        ? AsOneIconName.link
                        : AsOneIconName.document,
                    size: 17,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      attachment.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (message.reasoning?.trim().isNotEmpty == true) ...[
          const Text(
            '思考',
            style: TextStyle(fontSize: 13, color: AsOneTheme.textSecondary),
          ),
          const SizedBox(height: 5),
        ],
        if (message.content.trim().isEmpty && message.streaming)
          const _TypingIndicator()
        else
          _CommunityChatMessageContent(
            content: message.content,
            isUser: isUser,
          ),
        if (!isUser && message.answerStatus == MessageAnswerStatus.cancelled)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '回复已中断',
              style: TextStyle(fontSize: 11, color: AsOneTheme.textSecondary),
            ),
          ),
        if (!isUser && message.failureHint?.trim().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              message.failureHint!,
              style: const TextStyle(fontSize: 11, color: Color(0xFFC94D45)),
            ),
          ),
      ],
    );
    final bubble = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.69,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Color(isUser ? 0x0C000000 : 0x14000000),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: content,
      ),
    );
    final actionBar = actionsExpanded
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 2,
              alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
              children: [
                for (final action in actions)
                  IconButton(
                    tooltip: actionLabel(action),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: () => unawaited(onAction(action)),
                    icon: AsOneIcon(actionIcon(action), size: 18),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();
    final child = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              AsOneAvatar.assistant(
                imagePath: assistant?.avatar ?? '',
                name: assistant?.name ?? '助手',
                size: 36,
                borderRadius: 10,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(child: bubble),
            if (isUser) ...[
              const SizedBox(width: 4),
              const AsOneAvatar(
                imagePath: '',
                size: 36,
                borderRadius: 10,
                fallbackIcon: Icons.person,
                fallbackColor: AsOneTheme.accent,
                backgroundColor: AsOneTheme.cardBg,
              ),
            ],
          ],
        ),
        Padding(
          padding: EdgeInsets.only(
            left: isUser ? 0 : 40,
            right: isUser ? 40 : 0,
            top: 3,
          ),
          child: Text(
            _formatTime(message.createdAt),
            style: const TextStyle(
              fontSize: 10,
              color: AsOneTheme.textTertiary,
            ),
          ),
        ),
        actionBar,
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: child,
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SizedBox(width: 8),
      Text('正在输入…', style: TextStyle(color: AsOneTheme.textSecondary)),
    ],
  );
}

class _CommunityChatMessageContent extends StatelessWidget {
  const _CommunityChatMessageContent({
    required this.content,
    required this.isUser,
  });

  final String content;
  final bool isUser;

  static final _fencedCode = RegExp(r'```[^\n]*\n([\s\S]*?)```');

  @override
  Widget build(BuildContext context) {
    final matches = _fencedCode.allMatches(content).toList(growable: false);
    final style = MarkdownStyleSheet(
      p: const TextStyle(
        fontSize: 15,
        height: 1.45,
        color: AsOneTheme.chatBodyText,
      ),
      code: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
    );
    if (matches.isEmpty) {
      return MarkdownBody(
        data: content,
        styleSheet: style,
        softLineBreak: isUser,
      );
    }
    final children = <Widget>[];
    var cursor = 0;
    for (final match in matches) {
      final before = content.substring(cursor, match.start).trimRight();
      if (before.isNotEmpty) {
        children.add(
          MarkdownBody(data: before, styleSheet: style, softLineBreak: isUser),
        );
        children.add(const SizedBox(height: 7));
      }
      children.add(_CommunityCopyableCodeBlock(code: match.group(1) ?? ''));
      cursor = match.end;
    }
    final after = content.substring(cursor).trimLeft();
    if (after.isNotEmpty)
      children.add(
        MarkdownBody(data: after, styleSheet: style, softLineBreak: isUser),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _CommunityCopyableCodeBlock extends StatelessWidget {
  const _CommunityCopyableCodeBlock({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8F6),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE8DAD7), width: 0.8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: '复制代码',
          visualDensity: VisualDensity.compact,
          iconSize: 17,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) AsOneToast.show(context, '代码已复制');
          },
          icon: const AsOneIcon(AsOneIconName.copy),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              code.trimRight(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
