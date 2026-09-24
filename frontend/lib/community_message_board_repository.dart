import 'dart:math';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:sqflite/sqflite.dart';

import 'local_core/core_database.dart';
import 'local_core/feature_unread_service.dart';

/// 社区版留言板仓储。
///
/// 留言、评论和点赞落入本地 SQLite；社区版不创建助手自动回复任务，
/// 也不触发正式版连续性事件。
class CommunityMessageBoardRepository implements MessageBoardRepositoryApi {
  CommunityMessageBoardRepository({
    required CoreDatabase database,
    required FeatureUnreadService featureUnread,
  }) : _database = database,
       _featureUnread = featureUnread;

  final CoreDatabase _database;
  final FeatureUnreadService _featureUnread;
  final Random _random = Random.secure();

  static const _posts = 'board_posts';
  static const _comments = 'board_comments';
  static const _likes = 'board_post_likes';
  static const currentUserActorId = 'local_user';

  String _id(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${_random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0')}';

  String _now() => DateTime.now().toUtc().toIso8601String();

  @override
  Future<BoardPostItem> publishPost({
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? generationTaskId,
    String? generationKind,
  }) async {
    _validateAuthor(authorType, authorAssistantId);
    _validateContent(content);
    final post = BoardPostItem(
      postId: _id('p'),
      content: content.trim(),
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      generationTaskId: generationTaskId,
      generationKind: generationKind,
      createdAt: DateTime.now().toUtc(),
    );
    final db = await _database.open();
    await db.insert(_posts, post.toJson());
    if (authorType == 'assistant') await _featureUnread.refresh();
    return post;
  }

  @override
  Future<bool> deletePost(String postId) async {
    final db = await _database.open();
    final count = await db.update(
      _posts,
      {'deleted_at': _now()},
      where: 'post_id = ? AND deleted_at IS NULL',
      whereArgs: [postId],
    );
    if (count > 0) {
      await db.delete(_likes, where: 'post_id = ?', whereArgs: [postId]);
    }
    return count > 0;
  }

  @override
  Future<BoardPostItem?> loadPost(String postId) async {
    final db = await _database.open();
    final rows = await db.query(
      _posts,
      where: 'post_id = ?',
      whereArgs: [postId],
      limit: 1,
    );
    return rows.isEmpty ? null : BoardPostItem.fromJson(rows.single);
  }

  @override
  Future<int> unreadCount({String? assistantId}) =>
      _featureUnread.messageBoardUnreadCount(assistantId: assistantId);

  @override
  Future<void> markRead({DateTime? through}) =>
      _featureUnread.markRead(FeatureUnreadKind.messageBoard, through: through);

  @override
  Future<List<BoardPostItem>> listActivePosts() => listPostsForUser();

  @override
  Future<List<BoardPostItem>> listPostsForUser() async {
    final db = await _database.open();
    final rows = await db.query(
      _posts,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return rows.map(BoardPostItem.fromJson).toList(growable: false);
  }

  @override
  Future<List<BoardPostItem>> listPostsForAssistant(String assistantId) async {
    final db = await _database.open();
    final rows = await db.query(
      _posts,
      where:
          "deleted_at IS NULL AND (author_type = 'user' OR author_assistant_id = ?)",
      whereArgs: [assistantId],
      orderBy: 'created_at DESC',
    );
    return rows.map(BoardPostItem.fromJson).toList(growable: false);
  }

  @override
  Future<Map<String, BoardPostLikeState>> listPostLikeStates(
    Iterable<String> postIds,
  ) async {
    final ids = postIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final db = await _database.open();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT post_id, COUNT(*) AS total_count,
        MAX(CASE WHEN actor_type = 'user' AND actor_id = ? THEN 1 ELSE 0 END)
          AS current_user_liked
      FROM $_likes
      WHERE post_id IN ($placeholders)
      GROUP BY post_id
    ''',
      [currentUserActorId, ...ids],
    );
    final result = <String, BoardPostLikeState>{
      for (final id in ids)
        id: BoardPostLikeState(
          postId: id,
          totalCount: 0,
          currentUserLiked: false,
        ),
    };
    for (final row in rows) {
      final id = row['post_id']! as String;
      result[id] = BoardPostLikeState(
        postId: id,
        totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
        currentUserLiked:
            ((row['current_user_liked'] as num?)?.toInt() ?? 0) == 1,
      );
    }
    return result;
  }

  @override
  Future<Map<String, int>> listPostCommentCountsForUser(
    Iterable<String> postIds,
  ) async {
    final ids = postIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final db = await _database.open();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT post_id, COUNT(*) AS total_count FROM $_comments '
      'WHERE deleted_at IS NULL AND post_id IN ($placeholders) GROUP BY post_id',
      ids,
    );
    final result = <String, int>{for (final id in ids) id: 0};
    for (final row in rows) {
      result[row['post_id']! as String] =
          (row['total_count'] as num?)?.toInt() ?? 0;
    }
    return result;
  }

  @override
  Future<BoardPostLikeState> setUserPostLiked(
    String postId, {
    required bool liked,
  }) async {
    final db = await _database.open();
    return db.transaction((txn) async {
      await _requireActivePost(txn, postId);
      if (liked) {
        await txn.insert(_likes, {
          'post_id': postId,
          'actor_type': 'user',
          'actor_id': currentUserActorId,
          'created_at': _now(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        await txn.delete(
          _likes,
          where: 'post_id = ? AND actor_type = ? AND actor_id = ?',
          whereArgs: [postId, 'user', currentUserActorId],
        );
      }
      return _loadLikeState(txn, postId);
    });
  }

  @override
  Future<BoardPostLikeState> ensureAssistantPostLiked({
    required String postId,
    required String assistantId,
  }) async {
    if (assistantId.trim().isEmpty) throw ArgumentError('助手 ID 不能为空');
    final db = await _database.open();
    return db.transaction((txn) async {
      final post = await _requireActivePost(txn, postId);
      if (post.authorType != 'user') throw ArgumentError('助手只能给用户留言点赞');
      await txn.insert(_likes, {
        'post_id': postId,
        'actor_type': 'assistant',
        'actor_id': assistantId,
        'created_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return _loadLikeState(txn, postId);
    });
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
    _validateAuthor(authorType, authorAssistantId);
    _validateContent(content);
    final db = await _database.open();
    final comment = BoardCommentItem(
      commentId: _id('c'),
      postId: postId,
      content: content.trim(),
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      targetAssistantId: targetAssistantId,
      parentCommentId: parentCommentId,
      generationTaskId: generationTaskId,
      generationKind: generationKind,
      createdAt: DateTime.now().toUtc(),
    );
    await db.transaction((txn) async {
      final post = await _requireActivePost(txn, postId);
      if (parentCommentId != null) {
        final rows = await txn.query(
          _comments,
          where: 'comment_id = ? AND post_id = ? AND deleted_at IS NULL',
          whereArgs: [parentCommentId, postId],
          limit: 1,
        );
        if (rows.isEmpty) throw ArgumentError('父评论不存在或已删除');
      }
      _validateThread(
        post: post,
        authorType: authorType,
        authorAssistantId: authorAssistantId,
        targetAssistantId: targetAssistantId,
      );
      await txn.insert(_comments, comment.toJson());
      if (autoLikeUserPost) {
        if (authorType != 'assistant' || post.authorType != 'user') {
          throw ArgumentError('自动点赞只支持助手评论用户留言');
        }
        await txn.insert(_likes, {
          'post_id': postId,
          'actor_type': 'assistant',
          'actor_id': authorAssistantId,
          'created_at': _now(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    if (authorType == 'assistant') await _featureUnread.refresh();
    return comment;
  }

  @override
  Future<bool> deleteComment(String commentId) async {
    final db = await _database.open();
    return await db.update(
          _comments,
          {'deleted_at': _now()},
          where: 'comment_id = ? AND deleted_at IS NULL',
          whereArgs: [commentId],
        ) >
        0;
  }

  @override
  Future<List<BoardCommentItem>> listComments(String postId) =>
      listCommentsForUser(postId);

  @override
  Future<List<BoardCommentItem>> listCommentsForUser(String postId) async {
    final db = await _database.open();
    final rows = await db.query(
      _comments,
      where: 'post_id = ? AND deleted_at IS NULL',
      whereArgs: [postId],
      orderBy: 'created_at ASC',
    );
    return rows.map(BoardCommentItem.fromJson).toList(growable: false);
  }

  @override
  Future<List<BoardCommentItem>> listCommentsForAssistant(
    String postId,
    String assistantId,
  ) async {
    final db = await _database.open();
    final postRows = await db.query(
      _posts,
      columns: ['author_type', 'author_assistant_id'],
      where: 'post_id = ? AND deleted_at IS NULL',
      whereArgs: [postId],
      limit: 1,
    );
    if (postRows.isEmpty) return const [];
    if (postRows.single['author_type'] == 'assistant' &&
        postRows.single['author_assistant_id'] != assistantId) {
      return const [];
    }
    final rows = await db.query(
      _comments,
      where:
          'post_id = ? AND deleted_at IS NULL AND '
          '(author_assistant_id = ? OR target_assistant_id = ?)',
      whereArgs: [postId, assistantId, assistantId],
      orderBy: 'created_at ASC',
    );
    return rows.map(BoardCommentItem.fromJson).toList(growable: false);
  }

  @override
  Future<int> countAssistantComments(String postId, String assistantId) async {
    final db = await _database.open();
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $_comments '
            'WHERE post_id = ? AND author_assistant_id = ? AND deleted_at IS NULL',
            [postId, assistantId],
          ),
        ) ??
        0;
  }

  Future<BoardPostItem> _requireActivePost(
    DatabaseExecutor db,
    String postId,
  ) async {
    final rows = await db.query(
      _posts,
      where: 'post_id = ? AND deleted_at IS NULL',
      whereArgs: [postId],
      limit: 1,
    );
    if (rows.isEmpty) throw ArgumentError('留言不存在或已删除');
    return BoardPostItem.fromJson(rows.single);
  }

  Future<BoardPostLikeState> _loadLikeState(
    DatabaseExecutor db,
    String postId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total_count, '
      "MAX(CASE WHEN actor_type = 'user' AND actor_id = ? THEN 1 ELSE 0 END) AS liked "
      'FROM $_likes WHERE post_id = ?',
      [currentUserActorId, postId],
    );
    final row = rows.single;
    return BoardPostLikeState(
      postId: postId,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      currentUserLiked: ((row['liked'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  void _validateContent(String content) {
    if (content.trim().isEmpty) throw ArgumentError('留言内容不能为空');
  }

  void _validateAuthor(String authorType, String? assistantId) {
    if (authorType != 'user' && authorType != 'assistant') {
      throw ArgumentError('作者类型无效');
    }
    if (authorType == 'assistant' && assistantId == null) {
      throw ArgumentError('助手作者必须提供助手 ID');
    }
    if (authorType == 'user' && assistantId != null) {
      throw ArgumentError('用户作者不能带助手 ID');
    }
  }

  void _validateThread({
    required BoardPostItem post,
    required String authorType,
    required String? authorAssistantId,
    required String? targetAssistantId,
  }) {
    if (authorType == 'assistant') {
      if (targetAssistantId != null && targetAssistantId != authorAssistantId) {
        throw ArgumentError('助手不能指向其他助手');
      }
      if (post.authorType == 'assistant' &&
          post.authorAssistantId != authorAssistantId) {
        throw ArgumentError('助手不能评论其他助手的留言');
      }
    } else if (post.authorType == 'assistant' &&
        targetAssistantId != post.authorAssistantId) {
      throw ArgumentError('用户评论助手留言时必须指定目标助手');
    }
  }
}
