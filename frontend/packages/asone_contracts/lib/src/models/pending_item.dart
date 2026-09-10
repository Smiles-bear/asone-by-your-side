/// Basic pending-item data contract.
class PendingItem {
  final String pendingId;
  final String content;
  final String status;
  final String dueAt;
  final DateTime createdAt;

  const PendingItem({
    required this.pendingId,
    required this.content,
    required this.status,
    required this.dueAt,
    required this.createdAt,
  });

  factory PendingItem.fromJson(Map<String, dynamic> json) {
    return PendingItem(
      pendingId: json['pending_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      dueAt: json['due_at'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'pending_id': pendingId,
    'content': content,
    'status': status,
    'due_at': dueAt,
    'created_at': createdAt.toIso8601String(),
  };
}
