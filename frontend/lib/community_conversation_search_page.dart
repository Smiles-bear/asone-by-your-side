import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:flutter/material.dart';

import 'community_chat_page.dart';
import 'theme/asone_theme.dart';
import 'widgets/asone_app_bar.dart';
import 'widgets/asone_empty_state.dart';
import 'widgets/asone_feedback.dart';
import 'widgets/asone_icons.dart';

/// 社区版全局聊天记录搜索。
///
/// 正式版的全局搜索入口由宿主挂载；社区版使用公开消息契约搜索，点击结果
/// 直接打开对应的社区聊天页。
class CommunityConversationSearchPage extends StatefulWidget {
  const CommunityConversationSearchPage({super.key});

  @override
  State<CommunityConversationSearchPage> createState() =>
      _CommunityConversationSearchPageState();
}

class _CommunityConversationSearchPageState
    extends State<CommunityConversationSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = const [];
  List<Conversation> _conversations = const [];
  List<Assistant> _assistants = const [];
  String _query = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    unawaited(_loadContext());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    try {
      final core = OpenCoreBinding.instance;
      final values = await Future.wait<Object>([
        core.conversations.getConversations(),
        core.assistants.getAssistants(),
      ]);
      if (!mounted) return;
      setState(() {
        _conversations = values[0] as List<Conversation>;
        _assistants = values[1] as List<Assistant>;
      });
    } catch (_) {
      // 搜索时仍会返回结果；缺少上下文时只禁用结果跳转。
    }
  }

  void _onChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (query.isEmpty) {
        if (mounted) {
          setState(() {
            _query = '';
            _results = const [];
          });
        }
        return;
      }
      unawaited(_search(query));
    });
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() {
      _query = query;
      _loading = true;
    });
    try {
      final page = await OpenCoreBinding.instance.messages.searchMessages(
        query,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _results = page.items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AsOneToast.show(context, '搜索失败，请稍后重试');
    }
  }

  TextSpan _highlight(String text) {
    if (_query.isEmpty) return TextSpan(text: text);
    final lower = text.toLowerCase();
    final query = _query.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final start = lower.indexOf(query, cursor);
      if (start < 0) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(start, start + query.length),
          style: const TextStyle(
            backgroundColor: AsOneTheme.tileHighlight,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = start + query.length;
    }
    return TextSpan(children: spans);
  }

  Future<void> _openResult(SearchResult result) async {
    final conversation = _conversations
        .where((item) => item.id == result.conversationId)
        .firstOrNull;
    if (conversation == null) {
      AsOneToast.show(context, '对话已不存在');
      return;
    }
    final assistant = _assistants
        .where((item) => item.id == conversation.assistantId)
        .firstOrNull;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityChatPage(
          initialConversation: conversation,
          initialAssistant: assistant,
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final body = _results.isEmpty && !_loading
        ? AsOneEmptyState(
            icon: asOneIconData(AsOneIconName.search),
            title: _query.isEmpty ? '搜索聊天记录' : '没有找到匹配的消息',
            description: _query.isEmpty ? '输入关键词查找所有对话中的内容' : '试试更换关键词',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _results.length + (_loading ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index >= _results.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final result = _results[index];
              final conversation = _conversations
                  .where((item) => item.id == result.conversationId)
                  .firstOrNull;
              return Material(
                color: const Color(0xFFFFFDFC),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFF0E5E0)),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openResult(result),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AsOneIcon(
                              AsOneIconName.message,
                              size: 16,
                              color: AsOneTheme.accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                conversation?.title ?? '对话',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AsOneTheme.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(result.createdAt),
                              style: AsOneTheme.secondaryStyle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: _highlight(result.content),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          result.role == 'user' ? '我' : 'AI',
                          style: AsOneTheme.captionStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
    return Scaffold(
      backgroundColor: AsOneTheme.pageBg,
      appBar: AsOneAppBar(
        title: '搜索聊天记录',
        leading: AsOneIconButton(
          icon: AsOneIconName.back,
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const Key('community-conversation-search-field'),
              controller: _controller,
              autofocus: true,
              maxLines: 1,
              decoration: InputDecoration(
                hintText: '搜索所有对话…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFFFFDFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFF0E5E0)),
                ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
