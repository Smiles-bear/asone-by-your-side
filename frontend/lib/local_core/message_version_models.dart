/// 消息版本模型
class MessageVersion {
  final String versionId;
  final String messageId;
  final int versionNumber;
  final String content;
  final String contentHash;
  final String? editedBy;
  final String createdAt;

  MessageVersion({
    required this.versionId,
    required this.messageId,
    required this.versionNumber,
    required this.content,
    required this.contentHash,
    this.editedBy,
    required this.createdAt,
  });

  factory MessageVersion.fromJson(Map<String, dynamic> json) {
    return MessageVersion(
      versionId: json['version_id'] as String,
      messageId: json['message_id'] as String,
      versionNumber: json['version_number'] as int,
      content: json['content'] as String,
      contentHash: json['content_hash'] as String,
      editedBy: json['edited_by'] as String?,
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version_id': versionId,
      'message_id': messageId,
      'version_number': versionNumber,
      'content': content,
      'content_hash': contentHash,
      'edited_by': editedBy,
      'created_at': createdAt,
    };
  }
}

/// 回答版本模型
class AnswerVersion {
  final String answerVersionId;
  final String messageId;
  final int versionNumber;
  final String content;
  final String contentHash;
  final String? modelServiceId;
  final String? modelName;
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;
  final int? elapsedMs;
  final String? reasoning;
  final bool toolUsed;
  final String? branchParentVersionId;
  final bool branchActive;
  final String createdAt;

  AnswerVersion({
    required this.answerVersionId,
    required this.messageId,
    required this.versionNumber,
    required this.content,
    required this.contentHash,
    this.modelServiceId,
    this.modelName,
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
    this.elapsedMs,
    this.reasoning,
    this.toolUsed = false,
    this.branchParentVersionId,
    required this.branchActive,
    required this.createdAt,
  });

  factory AnswerVersion.fromJson(Map<String, dynamic> json) {
    return AnswerVersion(
      answerVersionId: json['answer_version_id'] as String,
      messageId: json['message_id'] as String,
      versionNumber: json['version_number'] as int,
      content: json['content'] as String,
      contentHash: json['content_hash'] as String,
      modelServiceId: json['model_service_id'] as String?,
      modelName: json['model_name'] as String?,
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      finishReason: json['finish_reason'] as String?,
      elapsedMs: json['elapsed_ms'] as int?,
      reasoning: json['reasoning'] as String?,
      toolUsed: (json['tool_used'] as int? ?? 0) == 1,
      branchParentVersionId: json['branch_parent_version_id'] as String?,
      branchActive: (json['branch_active'] as int) == 1,
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'answer_version_id': answerVersionId,
      'message_id': messageId,
      'version_number': versionNumber,
      'content': content,
      'content_hash': contentHash,
      'model_service_id': modelServiceId,
      'model_name': modelName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'finish_reason': finishReason,
      'elapsed_ms': elapsedMs,
      'reasoning': reasoning,
      'tool_used': toolUsed ? 1 : 0,
      'branch_parent_version_id': branchParentVersionId,
      'branch_active': branchActive ? 1 : 0,
      'created_at': createdAt,
    };
  }
}

/// 扩展的消息模型（包含版本信息）
class MessageWithVersions {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final int revision;
  final String? currentMessageVersionId;
  final String? currentAnswerVersionId;
  final int? currentAnswerVersionNumber;
  final int answerVersionCount;
  final String? answerStatus;
  final bool isDeleted;
  final bool visible;
  final String? contentHash;
  final String createdAt;
  final String? updatedAt;

  MessageWithVersions({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.revision,
    this.currentMessageVersionId,
    this.currentAnswerVersionId,
    this.currentAnswerVersionNumber,
    required this.answerVersionCount,
    this.answerStatus,
    required this.isDeleted,
    required this.visible,
    this.contentHash,
    required this.createdAt,
    this.updatedAt,
  });

  factory MessageWithVersions.fromJson(Map<String, dynamic> json) {
    return MessageWithVersions(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      revision: json['revision'] as int? ?? 1,
      currentMessageVersionId: json['current_message_version_id'] as String?,
      currentAnswerVersionId: json['current_answer_version_id'] as String?,
      currentAnswerVersionNumber: json['current_answer_version_number'] as int?,
      answerVersionCount: json['answer_version_count'] as int? ?? 0,
      answerStatus: json['answer_status'] as String?,
      isDeleted: (json['is_deleted'] as int? ?? 0) == 1,
      visible: (json['visible'] as int? ?? 1) == 1,
      contentHash: json['content_hash'] as String?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'revision': revision,
      'current_message_version_id': currentMessageVersionId,
      'current_answer_version_id': currentAnswerVersionId,
      'current_answer_version_number': currentAnswerVersionNumber,
      'answer_version_count': answerVersionCount,
      'answer_status': answerStatus,
      'is_deleted': isDeleted ? 1 : 0,
      'visible': visible ? 1 : 0,
      'content_hash': contentHash,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
