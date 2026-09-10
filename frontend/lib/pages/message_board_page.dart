/// 全局留言板页面（M4 §6）
///
/// 低打扰、异步的共同空间。帖子和评论只支持发布/删除，不支持编辑（§16）。
/// 支持用户发布留言、评论助手留言，以及回复助手评论。
library;

import 'package:flutter/material.dart';

import '../models/assistant.dart';
import '../models/board_item.dart';
import '../services/user_identity_service.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_bottom_sheet.dart';
import '../widgets/asone_dialog.dart';
import '../widgets/asone_empty_state.dart';
import '../widgets/asone_avatar.dart';
import '../widgets/asone_input_dialog.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_line_asset_icon.dart';
import '../widgets/asone_feedback.dart';

class MessageBoardPage extends StatefulWidget {
  const MessageBoardPage({
    super.key,
    this.messageBoard,
    this.coreRepository,
    this.initialPostId,
    this.initialAssistantId,
    this.initialCommentId,
  });

  /// 可注入（测试用），默认走 OpenCoreBinding
  final MessageBoardRepositoryApi? messageBoard;
  final AssistantRepositoryApi? coreRepository;
  final String? initialPostId;
  final String? initialAssistantId;
  final String? initialCommentId;

  static const pageColor = AsOneTheme.pageBg;
  static const headerColor = AsOneTheme.pageBg;
  static const dividerColor = AsOneTheme.divider;

  @override
  State<MessageBoardPage> createState() => _MessageBoardPageState();
}

class _MessageBoardPageState extends State<MessageBoardPage> {
  late final MessageBoardRepositoryApi _board =
      widget.messageBoard ?? OpenCoreBinding.instance.messageBoard;
  late final AssistantRepositoryApi _coreRepository =
      widget.coreRepository ?? OpenCoreBinding.instance.assistants;

  List<BoardPostItem> _posts = [];
  Map<String, BoardPostLikeState> _likeStates = {};
  Map<String, int> _commentCounts = {};
  Map<String, Assistant> _assistantMap = {};
  bool _loading = true;
  final Set<String> _likeUpdates = {};

  /// 已展开的帖子 ID → 评论列表
  final Map<String, List<BoardCommentItem>> _expandedComments = {};
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _postKeys = {};
  final Map<String, GlobalKey> _commentKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final readThrough = DateTime.now().toUtc();
    final posts = await _board.listActivePosts();
    final assistants = await _coreRepository.getAssistants();
    final likeStates = await _board.listPostLikeStates(
      posts.map((post) => post.postId),
    );
    final commentCounts = await _board.listPostCommentCountsForUser(
      posts.map((post) => post.postId),
    );
    final initialPostId = widget.initialPostId;
    final initialComments = initialPostId == null
        ? null
        : await _board.listComments(initialPostId);
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _likeStates = likeStates;
      _commentCounts = commentCounts;
      _assistantMap = {for (final a in assistants) a.id: a};
      if (initialPostId != null && initialComments != null) {
        _expandedComments[initialPostId] = initialComments;
      }
      _loading = false;
    });
    await _board.markRead(through: readThrough);
    _scheduleInitialFocus();
  }

  void _scheduleInitialFocus() {
    final postId = widget.initialPostId;
    if (postId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final postIndex = _posts.indexWhere((post) => post.postId == postId);
      if (_scrollController.hasClients && postIndex > 0 && _posts.length > 1) {
        final fraction = postIndex / (_posts.length - 1);
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent * fraction,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      final postContext = _postKeys[postId]?.currentContext;
      if (postContext == null || !postContext.mounted) return;
      await Scrollable.ensureVisible(
        postContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || widget.initialCommentId == null) return;
      final commentContext =
          _commentKeys[widget.initialCommentId]?.currentContext;
      if (commentContext == null || !commentContext.mounted) return;
      await Scrollable.ensureVisible(
        commentContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _authorLabel(String authorType, String? assistantId) {
    if (authorType == 'user') {
      return UserIdentityService.instance.value.nickname;
    }
    final a = _assistantMap[assistantId];
    return a?.name ?? '助手';
  }

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final time = '${two(local.hour)}:${two(local.minute)}';
    final dayOffset = today.difference(date).inDays;
    if (dayOffset == 0) return '今天  $time';
    if (dayOffset == 1) return '昨天  $time';
    if (local.year == now.year) return '${local.month}月${local.day}日  $time';
    return '${local.year}年${local.month}月${local.day}日  $time';
  }

  String _avatarPath(BoardPostItem post) {
    if (post.authorType == 'user') {
      return UserIdentityService.instance.value.avatarPath;
    }
    return _assistantMap[post.authorAssistantId]?.avatar ?? '';
  }

  Future<void> _toggleLike(BoardPostItem post) async {
    if (_likeUpdates.contains(post.postId)) return;
    final previous =
        _likeStates[post.postId] ??
        BoardPostLikeState(
          postId: post.postId,
          totalCount: 0,
          currentUserLiked: false,
        );
    final nextLiked = !previous.currentUserLiked;
    final optimistic = previous.copyWith(
      currentUserLiked: nextLiked,
      totalCount: nextLiked
          ? previous.totalCount + 1
          : (previous.totalCount - 1).clamp(0, 1 << 31).toInt(),
    );
    setState(() {
      _likeUpdates.add(post.postId);
      _likeStates[post.postId] = optimistic;
    });
    try {
      final saved = await _board.setUserPostLiked(
        post.postId,
        liked: nextLiked,
      );
      if (!mounted) return;
      setState(() => _likeStates[post.postId] = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _likeStates[post.postId] = previous);
      AsOneToast.show(context, nextLiked ? '点赞失败，请稍后重试' : '取消点赞失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _likeUpdates.remove(post.postId));
    }
  }

  Future<void> _showAddPostDialog() async {
    final result = await AsOneInputDialog.show(
      context,
      title: '发布留言',
      hintText: '留一句话在这里',
      confirmLabel: '发布',
      maxLength: 200,
      maxLines: 4,
    );
    if (result == null) return;
    await _board.publishPost(content: result, authorType: 'user');
    await _load();
  }

  Future<void> _confirmDeletePost(BoardPostItem post) async {
    final confirmed = await _confirmDialog('删除这条留言？', post.content);
    if (!confirmed) return;
    await _board.deletePost(post.postId);
    _expandedComments.remove(post.postId);
    await _load();
  }

  Future<void> _confirmDeleteComment(
    BoardCommentItem comment,
    String postId,
  ) async {
    final confirmed = await _confirmDialog('删除这条评论？', comment.content);
    if (!confirmed) return;
    await _board.deleteComment(comment.commentId);
    await _refreshComments(postId);
  }

  Future<void> _showCommentDialog(
    BoardPostItem post, {
    BoardCommentItem? parent,
  }) async {
    final assistantId =
        parent?.authorAssistantId ??
        parent?.targetAssistantId ??
        post.authorAssistantId;
    final result = await AsOneInputDialog.show(
      context,
      title: assistantId == null
          ? '发表评论'
          : parent == null
          ? '评论 ${_authorLabel('assistant', assistantId)} 的留言'
          : '回复 ${_authorLabel('assistant', assistantId)}',
      hintText: parent == null ? '写下评论' : '写下回复',
      confirmLabel: '发送',
      maxLength: 200,
      maxLines: 4,
    );
    if (result == null) return;
    await _board.publishComment(
      postId: post.postId,
      content: result,
      authorType: 'user',
      targetAssistantId: assistantId,
      parentCommentId: parent?.commentId,
    );
    await _refreshComments(post.postId);
  }

  Future<bool> _confirmDialog(String title, String content) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AsOneDialog(
        icon: asOneIconData(AsOneIconName.delete),
        iconColor: AsOneTheme.danger,
        title: title,
        content: Text(content, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AsOneTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _toggleExpand(BoardPostItem post) async {
    if (_expandedComments.containsKey(post.postId)) {
      setState(() => _expandedComments.remove(post.postId));
    } else {
      await _refreshComments(post.postId);
    }
  }

  Future<void> _refreshComments(String postId) async {
    final comments = await _board.listComments(postId);
    if (!mounted) return;
    setState(() {
      _expandedComments[postId] = comments;
      _commentCounts[postId] = comments.length;
    });
  }

  Future<void> _showPostMenu(BoardPostItem post) async {
    final action = await AsOneBottomSheet.showActions<String>(
      context,
      title: '留言操作',
      actions: const [
        AsOneSheetAction(
          value: 'delete',
          label: '删除留言',
          icon: AsOneIconName.delete,
          destructive: true,
        ),
      ],
    );
    if (action == 'delete' && mounted) await _confirmDeletePost(post);
  }

  List<BoardCommentItem>? _visibleComments(BoardPostItem post) {
    final allComments = _expandedComments[post.postId];
    final focusAssistantId = widget.initialPostId == post.postId
        ? widget.initialAssistantId
        : null;
    if (allComments == null || focusAssistantId == null) return allComments;
    return allComments
        .where(
          (comment) =>
              comment.authorAssistantId == focusAssistantId ||
              comment.targetAssistantId == focusAssistantId,
        )
        .toList(growable: false);
  }

  Widget _buildComments(BoardPostItem post, List<BoardCommentItem> comments) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(13, 0, 13, 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final comment in comments)
            Container(
              key: _commentKeys.putIfAbsent(comment.commentId, GlobalKey.new),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: widget.initialCommentId == comment.commentId
                  ? BoxDecoration(
                      color: const Color(0xFFFFEAE4),
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: comment.authorType == 'assistant'
                          ? () => _showCommentDialog(post, parent: comment)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.55,
                              color: Color(0xFF66605D),
                            ),
                            children: [
                              TextSpan(
                                text:
                                    '${_authorLabel(comment.authorType, comment.authorAssistantId)}：',
                                style: const TextStyle(
                                  color: Color(0xFF9A6B59),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: comment.content),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '删除评论',
                    child: InkWell(
                      onTap: () => _confirmDeleteComment(comment, post.postId),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: AsOneLineAssetIcon.close(
                          width: 12,
                          height: 12,
                          color: Color(0xFFB6AEAA),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (comments.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 2, 6, 8),
              child: Text(
                '还没有评论',
                style: TextStyle(fontSize: 12, color: Color(0xFF938B87)),
              ),
            ),
          TextButton(
            onPressed: () => _showCommentDialog(post),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE58E79),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(48, 36),
            ),
            child: const Text('发表评论'),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(BoardPostItem post) {
    final comments = _visibleComments(post);
    final expanded = comments != null;
    final focusPost = widget.initialPostId == post.postId;
    final like =
        _likeStates[post.postId] ??
        BoardPostLikeState(
          postId: post.postId,
          totalCount: 0,
          currentUserLiked: false,
        );
    final userPost = post.authorType == 'user';
    return Container(
      key: _postKeys.putIfAbsent(post.postId, GlobalKey.new),
      margin: const EdgeInsets.only(bottom: 14),
      constraints: const BoxConstraints(minHeight: 160),
      decoration: BoxDecoration(
        color: focusPost && widget.initialCommentId == null
            ? const Color(0xFFFFF0EC)
            : const Color(0xFFFDFDFA),
        borderRadius: BorderRadius.circular(9),
        border: focusPost ? Border.all(color: const Color(0xFFF2B8AC)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 4.3,
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13.5, 17, 12, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 89),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AsOneAvatar(
                    imagePath: _avatarPath(post),
                    size: 50,
                    borderRadius: 10,
                    fallbackIcon: userPost
                        ? Icons.person_outline
                        : Icons.smart_toy_outlined,
                    fallbackColor: userPost
                        ? const Color(0xFF7FB3D5)
                        : const Color(0xFFE5989B),
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _authorLabel(post.authorType, post.authorAssistantId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          post.content,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            letterSpacing: 0.15,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF252221),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _timeLabel(post.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            letterSpacing: 0.1,
                            fontWeight: FontWeight.w300,
                            color: Color(0xFFA8A1A1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      key: ValueKey('board-menu-${post.postId}'),
                      tooltip: '留言操作',
                      padding: EdgeInsets.zero,
                      onPressed: () => _showPostMenu(post),
                      icon: const AsOneLineAssetIcon.more(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 13, right: 13, top: 11),
            child: Divider(height: 1, thickness: 0.6, color: Color(0xFFCFDEC8)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 215, right: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Semantics(
                  button: true,
                  enabled: true,
                  label: like.currentUserLiked ? '取消点赞' : '点赞',
                  child: SizedBox(
                    width: 38,
                    height: 43,
                    child: IconButton(
                      key: ValueKey('board-like-${post.postId}'),
                      tooltip: like.currentUserLiked ? '取消点赞' : '点赞',
                      padding: EdgeInsets.zero,
                      onPressed: _likeUpdates.contains(post.postId)
                          ? null
                          : () => _toggleLike(post),
                      icon: AsOneLineAssetIcon.heart(
                        selected: like.currentUserLiked,
                      ),
                    ),
                  ),
                ),
                Text(
                  '${like.totalCount}',
                  key: ValueKey('board-like-count-${post.postId}'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 7),
                SizedBox(
                  width: 38,
                  height: 43,
                  child: IconButton(
                    key: ValueKey('board-comments-${post.postId}'),
                    tooltip: expanded ? '收起评论' : '展开评论',
                    padding: EdgeInsets.zero,
                    onPressed: () => _toggleExpand(post),
                    icon: const AsOneLineAssetIcon.comment(),
                  ),
                ),
                Text(
                  '${_commentCounts[post.postId] ?? 0}',
                  key: ValueKey('board-comment-count-${post.postId}'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          if (expanded) _buildComments(post, comments),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MessageBoardPage.pageColor,
      appBar: AsOneAppBar(
        title: '留言板',
        leading: AsOneIconButton(
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
          icon: AsOneIconName.back,
        ),
        actions: [
          AsOneIconButton(
            tooltip: '发布留言',
            onPressed: _showAddPostDialog,
            icon: AsOneIconName.edit,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
          ? const AsOneEmptyState(
              icon: Icons.forum_outlined,
              title: '还没有留言',
              description: '留一句话在这里，什么时候看到都行',
            )
          : ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(17, 15, 17, 24),
              children: [for (final post in _posts) _buildPostCard(post)],
            ),
    );
  }
}
