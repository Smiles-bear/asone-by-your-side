import 'package:asone_contracts/asone_contracts.dart';

import '../demo_ids.dart';
import '../read_state.dart';

class _LikeState {
  _LikeState();

  bool userLiked = false;
  final Set<String> assistantLikes = {};

  int get total => (userLiked ? 1 : 0) + assistantLikes.length;
}

/// In-memory [MessageBoardRepositoryApi] implementation.
class DemoBoardStore implements MessageBoardRepositoryApi {
  DemoBoardStore({
    required DemoReadState readState,
    List<Map<String, dynamic>>? posts,
    List<Map<String, dynamic>>? comments,
    Map<String, List<String>>? assistantLikes,
    Iterable<String>? userLikedPosts,
  }) : _readState = readState,
       _posts = [...?posts],
       _comments = [...?comments] {
    for (final entry in (assistantLikes ?? const {}).entries) {
      _likes
          .putIfAbsent(entry.key, _LikeState.new)
          .assistantLikes
          .addAll(entry.value);
    }
    for (final postId in userLikedPosts ?? const <String>[]) {
      _likes.putIfAbsent(postId, _LikeState.new).userLiked = true;
    }
  }

  /// Mirrors the private repository constant for UI parity.
  static const String currentUserActorId = 'local_user';

  final DemoReadState _readState;
  final List<Map<String, dynamic>> _posts;
  final List<Map<String, dynamic>> _comments;
  final Map<String, _LikeState> _likes = {};

  Map<String, dynamic>? _postRow(String postId) {
    for (final row in _posts) {
      if (row['post_id'] == postId) return row;
    }
    return null;
  }

  bool _isActive(Map<String, dynamic> row) => row['deleted_at'] == null;

  void _validateAuthor(String authorType) {
    if (authorType != 'user' && authorType != 'assistant') {
      throw ArgumentError('作者类型无效');
    }
  }

  BoardPostLikeState _likeStateOf(String postId) {
    final state = _likes[postId];
    return BoardPostLikeState(
      postId: postId,
      totalCount: state?.total ?? 0,
      currentUserLiked: state?.userLiked ?? false,
    );
  }

  @override
  Future<BoardPostItem> publishPost({
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? generationTaskId,
    String? generationKind,
  }) async {
    final body = content.trim();
    if (body.isEmpty) {
      throw ArgumentError('请填写留言内容');
    }
    _validateAuthor(authorType);
    final post = BoardPostItem(
      postId: demoId('post'),
      content: body,
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      generationTaskId: generationTaskId,
      generationKind: generationKind,
      createdAt: DateTime.now(),
    );
    _posts.add(post.toJson());
    if (authorType == 'assistant') _readState.notify();
    return post;
  }

  @override
  Future<bool> deletePost(String postId) async {
    final row = _postRow(postId);
    if (row == null || !_isActive(row)) return false;
    final now = DateTime.now().toIso8601String();
    row['deleted_at'] = now;
    for (final comment in _comments) {
      if (comment['post_id'] == postId && comment['deleted_at'] == null) {
        comment['deleted_at'] = now;
      }
    }
    return true;
  }

  @override
  Future<BoardPostItem?> loadPost(String postId) async {
    final row = _postRow(postId);
    // 与私有实现一致：软删除的帖子仍可加载，由调用方检查 deletedAt。
    return row == null ? null : BoardPostItem.fromJson(row);
  }

  /// Demo-internal synchronous count, also used by the unread store.
  int unreadCountSync({String? assistantId}) {
    final lastRead = _readState.lastRead('message_board');
    var count = 0;
    for (final row in [..._posts, ..._comments]) {
      if (!_isActive(row)) continue;
      if (row['author_type'] != 'assistant') continue;
      if (assistantId != null && row['author_assistant_id'] != assistantId) {
        continue;
      }
      final createdAt = DateTime.parse(row['created_at'] as String);
      if (lastRead == null || createdAt.isAfter(lastRead)) count += 1;
    }
    return count;
  }

  @override
  Future<int> unreadCount({String? assistantId}) async =>
      unreadCountSync(assistantId: assistantId);

  @override
  Future<void> markRead({DateTime? through}) async {
    _readState.setLastRead('message_board', through ?? DateTime.now());
  }

  @override
  Future<List<BoardPostItem>> listActivePosts() async {
    final list = _posts.where(_isActive).map(BoardPostItem.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<List<BoardPostItem>> listPostsForUser() async => listActivePosts();

  @override
  Future<List<BoardPostItem>> listPostsForAssistant(String assistantId) async {
    // 演示简化：助手视图与用户视图一致，不做按助手过滤。
    return listActivePosts();
  }

  @override
  Future<Map<String, BoardPostLikeState>> listPostLikeStates(
    Iterable<String> postIds,
  ) async => {for (final postId in postIds) postId: _likeStateOf(postId)};

  @override
  Future<Map<String, int>> listPostCommentCountsForUser(
    Iterable<String> postIds,
  ) async {
    final ids = postIds.toSet();
    final counts = <String, int>{for (final id in ids) id: 0};
    for (final comment in _comments) {
      final postId = comment['post_id'] as String?;
      if (postId == null || !ids.contains(postId)) continue;
      if (!_isActive(comment)) continue;
      counts[postId] = (counts[postId] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<BoardPostLikeState> setUserPostLiked(
    String postId, {
    required bool liked,
  }) async {
    final state = _likes.putIfAbsent(postId, _LikeState.new);
    state.userLiked = liked;
    return _likeStateOf(postId);
  }

  @override
  Future<BoardPostLikeState> ensureAssistantPostLiked({
    required String postId,
    required String assistantId,
  }) async {
    _likes.putIfAbsent(postId, _LikeState.new).assistantLikes.add(assistantId);
    return _likeStateOf(postId);
  }

  @override
  Future<BoardCommentItem> publishComment({
    required String postId,
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? targetAssistantId,
    String? parentCommentId,
    String? generationTaskId,
    String? generationKind,
    bool autoLikeUserPost = false,
  }) async {
    final body = content.trim();
    if (body.isEmpty) {
      throw ArgumentError('请填写评论内容');
    }
    _validateAuthor(authorType);
    final postRow = _postRow(postId);
    if (postRow == null || !_isActive(postRow)) {
      throw StateError('留言已不存在');
    }
    final comment = BoardCommentItem(
      commentId: demoId('comment'),
      postId: postId,
      content: body,
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      targetAssistantId: targetAssistantId,
      parentCommentId: parentCommentId,
      generationTaskId: generationTaskId,
      generationKind: generationKind,
      createdAt: DateTime.now(),
    );
    _comments.add(comment.toJson());
    if (autoLikeUserPost &&
        postRow['author_type'] == 'user' &&
        authorAssistantId != null) {
      _likes
          .putIfAbsent(postId, _LikeState.new)
          .assistantLikes
          .add(authorAssistantId);
    }
    if (authorType == 'assistant') _readState.notify();
    return comment;
  }

  @override
  Future<bool> deleteComment(String commentId) async {
    for (final row in _comments) {
      if (row['comment_id'] == commentId && _isActive(row)) {
        row['deleted_at'] = DateTime.now().toIso8601String();
        return true;
      }
    }
    return false;
  }

  List<BoardCommentItem> _activeComments(String postId) {
    final list =
        _comments
            .where((row) => row['post_id'] == postId && _isActive(row))
            .map(BoardCommentItem.fromJson)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<List<BoardCommentItem>> listComments(String postId) async =>
      _activeComments(postId);

  @override
  Future<List<BoardCommentItem>> listCommentsForUser(String postId) async =>
      _activeComments(postId);

  @override
  Future<List<BoardCommentItem>> listCommentsForAssistant(
    String postId,
    String assistantId,
  ) async =>
      // 演示简化：未定向的评论对所有助手可见，定向评论仅目标助手可见。
      _activeComments(postId)
          .where(
            (c) =>
                c.targetAssistantId == null ||
                c.targetAssistantId == assistantId,
          )
          .toList();

  @override
  Future<int> countAssistantComments(String postId, String assistantId) async =>
      _activeComments(
        postId,
      ).where((c) => c.authorAssistantId == assistantId).length;

  /// Demo-internal: latest assistant-authored activity timestamp.
  DateTime? latestAssistantCreatedAt() {
    DateTime? latest;
    for (final row in [..._posts, ..._comments]) {
      if (!_isActive(row) || row['author_type'] != 'assistant') continue;
      final createdAt = DateTime.parse(row['created_at'] as String);
      if (latest == null || createdAt.isAfter(latest)) latest = createdAt;
    }
    return latest;
  }
}
