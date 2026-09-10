/// Public assistant profile model.
class Assistant {
  final String id;
  final String name;
  final String avatar;
  final String mainModel;
  final String assistantModel;
  final String voice;
  final String systemPrompt;
  final String modelServiceId;
  final String assistantModelServiceId;
  final String replyMode;
  final String memoryExpressionStyle;
  final String memoryExpressionCustom;
  final bool memoryAutoOrganizeEnabled;
  final String communicationStyle;
  final String behaviorBoundaries;
  final int contextWindow;
  final int maxOutputTokens;
  final int timestampsEnabled;
  final String userProfile;
  final String diaryWriter;
  final String diarySubject;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Assistant({
    required this.id,
    required this.name,
    required this.avatar,
    required this.mainModel,
    required this.assistantModel,
    required this.voice,
    required this.systemPrompt,
    required this.modelServiceId,
    this.assistantModelServiceId = '',
    this.replyMode = 'complete',
    this.memoryExpressionStyle = 'natural',
    this.memoryExpressionCustom = '',
    this.memoryAutoOrganizeEnabled = true,
    this.communicationStyle = '',
    this.behaviorBoundaries = '',
    this.contextWindow = 100000,
    this.maxOutputTokens = 8192,
    this.timestampsEnabled = 1,
    this.userProfile = '',
    this.diaryWriter = '助手',
    this.diarySubject = '用户',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Assistant.fromJson(Map<String, dynamic> json) => Assistant(
    id: json['id'] as String,
    name: json['name'] as String,
    avatar: json['avatar'] as String? ?? '',
    mainModel: json['main_model'] as String? ?? '',
    assistantModel: json['assistant_model'] as String? ?? '',
    voice: json['voice'] as String? ?? '',
    systemPrompt: json['system_prompt'] as String? ?? '',
    modelServiceId: json['model_service_id'] as String? ?? '',
    assistantModelServiceId:
        json['assistant_model_service_id'] as String? ?? '',
    replyMode: json['reply_mode'] as String? ?? 'complete',
    memoryExpressionStyle:
        json['memory_expression_style'] as String? ?? 'natural',
    memoryExpressionCustom: json['memory_expression_custom'] as String? ?? '',
    memoryAutoOrganizeEnabled:
        json['memory_auto_organize_enabled'] != 0 &&
        json['memory_auto_organize_enabled'] != false,
    communicationStyle: json['communication_style'] as String? ?? '',
    behaviorBoundaries: json['behavior_boundaries'] as String? ?? '',
    contextWindow: json['context_window'] as int? ?? 100000,
    maxOutputTokens: json['max_output_tokens'] as int? ?? 8192,
    timestampsEnabled: json['timestamps_enabled'] as int? ?? 1,
    userProfile: json['user_profile'] as String? ?? '',
    diaryWriter: json['diary_writer'] as String? ?? '助手',
    diarySubject: json['diary_subject'] as String? ?? '用户',
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'main_model': mainModel,
    'assistant_model': assistantModel,
    'voice': voice,
    'system_prompt': systemPrompt,
    'model_service_id': modelServiceId,
    'assistant_model_service_id': assistantModelServiceId,
    'reply_mode': replyMode,
    'memory_expression_style': memoryExpressionStyle,
    'memory_expression_custom': memoryExpressionCustom,
    'memory_auto_organize_enabled': memoryAutoOrganizeEnabled,
    'communication_style': communicationStyle,
    'behavior_boundaries': behaviorBoundaries,
    'context_window': contextWindow,
    'max_output_tokens': maxOutputTokens,
    'timestamps_enabled': timestampsEnabled,
    'user_profile': userProfile,
    'diary_writer': diaryWriter,
    'diary_subject': diarySubject,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
