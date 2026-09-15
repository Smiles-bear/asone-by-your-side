class ImportPlanGroup {
  const ImportPlanGroup({
    required this.groupId,
    required this.sourceConversationIds,
    required this.assistantName,
    required this.conversationTitle,
    this.existingAssistantId,
    this.existingConversationId,
    this.messageRangeStart,
    this.messageRangeEnd,
  });

  final String groupId;
  final List<String> sourceConversationIds;
  final String assistantName;
  final String conversationTitle;
  final String? existingAssistantId;
  final String? existingConversationId;
  final int? messageRangeStart;
  final int? messageRangeEnd;

  String get targetKind =>
      existingAssistantId == null && existingConversationId == null
      ? 'new'
      : 'existing';

  Map<String, Object?> toJson() => {
    'group_id': groupId,
    'source_conversation_ids': sourceConversationIds,
    'assistant_name': assistantName,
    'conversation_title': conversationTitle,
    'existing_assistant_id': existingAssistantId,
    'existing_conversation_id': existingConversationId,
    'message_range_start': messageRangeStart,
    'message_range_end': messageRangeEnd,
  };

  factory ImportPlanGroup.fromJson(Map<String, Object?> json) =>
      ImportPlanGroup(
        groupId: json['group_id']! as String,
        sourceConversationIds: (json['source_conversation_ids']! as List)
            .cast<String>(),
        assistantName: json['assistant_name']! as String,
        conversationTitle: json['conversation_title']! as String,
        existingAssistantId: json['existing_assistant_id'] as String?,
        existingConversationId: json['existing_conversation_id'] as String?,
        messageRangeStart: json['message_range_start'] as int?,
        messageRangeEnd: json['message_range_end'] as int?,
      );
}

class GroupedImportPlan {
  const GroupedImportPlan({
    required this.groups,
    this.roleMappings = const {},
    this.conversationOrder = const [],
    this.duplicatePolicy = 'new_only',
  });

  final List<ImportPlanGroup> groups;
  final Map<String, String> roleMappings;
  final List<String> conversationOrder;
  final String duplicatePolicy;

  String get duplicateStrategy => duplicatePolicy;

  List<String> get selectedConversationIds => [
    for (final group in groups) ...group.sourceConversationIds,
  ];

  Map<String, Object?> toJson() => {
    'groups': groups.map((group) => group.toJson()).toList(),
    'role_mappings': roleMappings,
    'conversation_order': conversationOrder,
    'duplicate_policy': duplicatePolicy,
  };
}
