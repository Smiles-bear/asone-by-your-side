import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:flutter/material.dart';

import 'theme/asone_theme.dart';
import 'widgets/asone_app_bar.dart';
import 'widgets/asone_empty_state.dart';
import 'widgets/asone_feedback.dart';
import 'widgets/asone_icons.dart';

/// 社区版聊天记录搜索。
///
/// 搜索只通过公开消息契约执行，点击结果返回原聊天页；不引入正式版的
/// 私有聊天导航或后台定位逻辑。
class CommunityChatSearchPage extends StatefulWidget {
  const CommunityChatSearchPage({
    super.key,
    required this.conversationId,
    required this.conversationTitle,
  });

  final String conversationId;
  final String conversationTitle;

  @override
  State<CommunityChatSearchPage> createState() =>
      _CommunityChatSearchPageState();
}

class _CommunityChatSearchPageState extends State<CommunityChatSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = const [];
  String _query = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (query.isEmpty) {
        if (mounted)
          setState(() {
            _query = '';
            _results = const [];
          });
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
        conversationId: widget.conversationId,
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

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
      if (start > cursor)
        spans.add(TextSpan(text: text.substring(cursor, start)));
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

  @override
  Widget build(BuildContext context) {
    final body = _results.isEmpty && !_loading
        ? AsOneEmptyState(
            icon: asOneIconData(AsOneIconName.search),
            title: _query.isEmpty ? '搜索聊天记录' : '没有找到匹配的消息',
            description: _query.isEmpty ? '输入关键词查找当前对话中的内容' : '试试更换关键词',
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
              return Material(
                color: const Color(0xFFFFFDFC),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFF0E5E0)),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(result.messageId),
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
                                widget.conversationTitle,
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
        subtitle: widget.conversationTitle,
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
              key: const Key('community-chat-search-field'),
              controller: _controller,
              autofocus: true,
              maxLines: 1,
              decoration: InputDecoration(
                hintText: '搜索聊天记录…',
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
