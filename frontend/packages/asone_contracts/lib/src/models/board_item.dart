/// Public bulletin-board data contracts.
class BoardPostLikeState {
  const BoardPostLikeState({
    required this.postId,
    required this.totalCount,
    required this.currentUserLiked,
  });

  final String postId;
  final int totalCount;
  final bool currentUserLiked;

  BoardPostLikeState copyWith({int? totalCount, bool? currentUserLiked}) {
    return BoardPostLikeState(
      postId: postId,
      totalCount: totalCount ?? this.totalCount,
      currentUserLiked: currentUserLiked ?? this.currentUserLiked,
    );
  }
}

/// A bulletin-board post.
class BoardPostItem {
  final String postId;
  final String content;
  final String authorType;
  final String? authorAssistantId;
  final String? generationTaskId;
  final String? generationKind;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const BoardPostItem({
    required this.postId,
    required this.content,
    required this.authorType,
    this.authorAssistantId,
    this.generationTaskId,
    this.generationKind,
    required this.createdAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  factory BoardPostItem.fromJson(Map<String, dynamic> json) {
    return BoardPostItem(
      postId: json['post_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      authorType: json['author_type'] as String? ?? 'user',
      authorAssistantId: json['author_assistant_id'] as String?,
      generationTaskId: json['generation_task_id'] as String?,
      generationKind: json['generation_kind'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'post_id': postId,
    'content': content,
    'author_type': authorType,
    'author_assistant_id': authorAssistantId,
    'generation_task_id': generationTaskId,
    'generation_kind': generationKind,
    'created_at': createdAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

/// A comment on a bulletin-board post.
class BoardCommentItem {
  final String commentId;
  final String postId;
  final String content;
  final String authorType;
  final String? authorAssistantId;
  final String? targetAssistantId;
  final String? parentCommentId;
  final String? generationTaskId;
  final String? generationKind;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const BoardCommentItem({
    required this.commentId,
    required this.postId,
    required this.content,
    required this.authorType,
    this.authorAssistantId,
    this.targetAssistantId,
    this.parentCommentId,
    this.generationTaskId,
    this.generationKind,
    required this.createdAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  factory BoardCommentItem.fromJson(Map<String, dynamic> json) {
    return BoardCommentItem(
      commentId: json['comment_id'] as String? ?? '',
      postId: json['post_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      authorType: json['author_type'] as String? ?? 'user',
      authorAssistantId: json['author_assistant_id'] as String?,
      targetAssistantId: json['target_assistant_id'] as String?,
      parentCommentId: json['parent_comment_id'] as String?,
      generationTaskId: json['generation_task_id'] as String?,
      generationKind: json['generation_kind'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'comment_id': commentId,
    'post_id': postId,
    'content': content,
    'author_type': authorType,
    'author_assistant_id': authorAssistantId,
    'target_assistant_id': targetAssistantId,
    'parent_comment_id': parentCommentId,
    'generation_task_id': generationTaskId,
    'generation_kind': generationKind,
    'created_at': createdAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}
