/// 记忆条目模型。
class MemoryItem {
  final String memoryId;
  final String content;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool manualEdit;
  final DateTime? manualEditedAt;
  final int editVersion;
  final String sourceMode;
  final DateTime? sourceTime;
  final bool isNew;
  final String displayOrigin;

  const MemoryItem({
    required this.memoryId,
    required this.content,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.manualEdit,
    required this.manualEditedAt,
    required this.editVersion,
    this.sourceMode = 'sourced',
    this.sourceTime,
    this.isNew = false,
    this.displayOrigin = '',
  });

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    return MemoryItem(
      memoryId: json['memory_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      manualEdit: json['manual_edit'] as bool? ?? false,
      manualEditedAt: (json['manual_edited_at'] as String? ?? '').isNotEmpty
          ? DateTime.parse(json['manual_edited_at'] as String)
          : null,
      editVersion: json['edit_version'] as int? ?? 1,
      sourceMode: json['source_mode'] as String? ?? 'sourced',
      sourceTime: (json['source_time'] as String? ?? '').isEmpty
          ? null
          : DateTime.parse(json['source_time'] as String),
      isNew: json['is_new'] == true || json['is_new'] == 1,
      displayOrigin: json['display_origin'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'memory_id': memoryId,
    'content': content,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'manual_edit': manualEdit,
    'manual_edited_at': manualEditedAt?.toIso8601String() ?? '',
    'edit_version': editVersion,
    'source_mode': sourceMode,
    'source_time': sourceTime?.toIso8601String(),
    'is_new': isNew,
    'display_origin': displayOrigin,
  };
}
