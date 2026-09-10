import '../models/board_item.dart';

/// Public data-access contract for the message board.
abstract interface class MessageBoardRepositoryApi {
  Future<BoardPostItem> publishPost({
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? generationTaskId,
    String? generationKind,
  });

  Future<bool> deletePost(String postId);

  Future<BoardPostItem?> loadPost(String postId);

  Future<int> unreadCount({String? assistantId});

  Future<void> markRead({DateTime? through});

  Future<List<BoardPostItem>> listActivePosts();

  Future<List<BoardPostItem>> listPostsForUser();

  Future<List<BoardPostItem>> listPostsForAssistant(String assistantId);

  Future<Map<String, BoardPostLikeState>> listPostLikeStates(
    Iterable<String> postIds,
  );

  Future<Map<String, int>> listPostCommentCountsForUser(
    Iterable<String> postIds,
  );

  Future<BoardPostLikeState> setUserPostLiked(
    String postId, {
    required bool liked,
  });

  Future<BoardPostLikeState> ensureAssistantPostLiked({
    required String postId,
    required String assistantId,
  });

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
  });

  Future<bool> deleteComment(String commentId);

  Future<List<BoardCommentItem>> listComments(String postId);

  Future<List<BoardCommentItem>> listCommentsForUser(String postId);

  Future<List<BoardCommentItem>> listCommentsForAssistant(
    String postId,
    String assistantId,
  );

  Future<int> countAssistantComments(String postId, String assistantId);
}
