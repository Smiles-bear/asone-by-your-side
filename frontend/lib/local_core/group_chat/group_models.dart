library;

import 'dart:math';

import '../../models/message.dart';

class GroupIdFactory {
  GroupIdFactory() : _random = Random.secure();

  final Random _random;

  String next(String prefix) {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = List.generate(
      2,
      (_) => _random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0'),
    ).join();
    return '${prefix}_$micros$random';
  }
}

class GroupRoom {
  const GroupRoom({
    required this.roomId,
    required this.title,
    required this.roomInstruction,
    required this.sequentialEnabled,
    required this.manualMentionEnabled,
    required this.status,
    required this.nextSequence,
    required this.draftText,
    this.draftUpdatedAt,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.createdAt,
    required this.updatedAt,
  });

  final String roomId;
  final String title;
  final String roomInstruction;
  final bool sequentialEnabled;
  final bool manualMentionEnabled;
  final String status;
  final int nextSequence;
  final String draftText;
  final DateTime? draftUpdatedAt;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  DateTime get listActivityAt => lastMessageAt ?? createdAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GroupRoom.fromRow(Map<String, Object?> row) => GroupRoom(
    roomId: row['room_id']! as String,
    title: row['title']! as String,
    roomInstruction: row['room_instruction'] as String? ?? '',
    sequentialEnabled: row['sequential_enabled'] == 1,
    manualMentionEnabled: row['manual_mention_enabled'] == 1,
    status: row['status']! as String,
    nextSequence: row['next_sequence']! as int,
    draftText: row['draft_text'] as String? ?? '',
    draftUpdatedAt: _date(row['draft_updated_at']),
    lastMessageAt: _date(row['last_message_at']),
    lastMessagePreview: row['last_message_preview'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );
}

class GroupParticipant {
  const GroupParticipant({
    required this.roomId,
    required this.assistantId,
    required this.speakOrder,
    required this.createdAt,
  });

  final String roomId;
  final String assistantId;
  final int speakOrder;
  final DateTime createdAt;

  factory GroupParticipant.fromRow(Map<String, Object?> row) =>
      GroupParticipant(
        roomId: row['room_id']! as String,
        assistantId: row['assistant_id']! as String,
        speakOrder: row['speak_order']! as int,
        createdAt: DateTime.parse(row['created_at']! as String),
      );
}

class GroupMessage {
  const GroupMessage({
    required this.messageId,
    required this.roomId,
    required this.sequence,
    required this.speakerType,
    this.speakerAssistantId,
    required this.content,
    this.reasoning,
    this.replyToMessageId,
    this.rootTriggerMessageId,
    this.roundPosition,
    required this.requestType,
    required this.revision,
    this.currentMessageVersionId,
    this.currentAnswerVersionId,
    this.currentAnswerVersionNumber,
    required this.answerVersionCount,
    this.answerStatus,
    this.failureHint,
    required this.toolUsed,
    required this.visible,
    required this.contextVisible,
    required this.isDeleted,
    this.contentHash,
    required this.upstreamRevisionHash,
    required this.upstreamStatus,
    required this.createdAt,
    required this.updatedAt,
    this.attachments = const [],
    this.voiceSegments = const [],
  });

  final String messageId;
  final String roomId;
  final int sequence;
  final String speakerType;
  final String? speakerAssistantId;
  final String content;
  final String? reasoning;
  final String? replyToMessageId;
  final String? rootTriggerMessageId;
  final int? roundPosition;
  final String requestType;
  final int revision;
  final String? currentMessageVersionId;
  final String? currentAnswerVersionId;
  final int? currentAnswerVersionNumber;
  final int answerVersionCount;
  final String? answerStatus;
  final String? failureHint;
  final bool toolUsed;
  final bool visible;
  final bool contextVisible;
  final bool isDeleted;
  final String? contentHash;
  final String upstreamRevisionHash;
  final String upstreamStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MessageAttachment> attachments;
  final List<VoiceMessageInfo> voiceSegments;

  factory GroupMessage.fromRow(Map<String, Object?> row) => GroupMessage(
    messageId: row['message_id']! as String,
    roomId: row['room_id']! as String,
    sequence: row['sequence']! as int,
    speakerType: row['speaker_type']! as String,
    speakerAssistantId: row['speaker_assistant_id'] as String?,
    content: row['content'] as String? ?? '',
    reasoning: row['reasoning'] as String?,
    replyToMessageId: row['reply_to_message_id'] as String?,
    rootTriggerMessageId: row['root_trigger_message_id'] as String?,
    roundPosition: row['round_position'] as int?,
    requestType: row['request_type']! as String,
    revision: row['revision']! as int,
    currentMessageVersionId: row['current_message_version_id'] as String?,
    currentAnswerVersionId: row['current_answer_version_id'] as String?,
    currentAnswerVersionNumber: row['current_answer_version_number'] as int?,
    answerVersionCount: row['answer_version_count']! as int,
    answerStatus: row['answer_status'] as String?,
    failureHint: row['failure_hint'] as String?,
    toolUsed: row['tool_used'] == 1,
    visible: row['visible'] == 1,
    contextVisible: row['context_visible'] == 1,
    isDeleted: row['is_deleted'] == 1,
    contentHash: row['content_hash'] as String?,
    upstreamRevisionHash: row['upstream_revision_hash'] as String? ?? '',
    upstreamStatus: row['upstream_status'] as String? ?? 'current',
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    attachments: const [],
    voiceSegments: const [],
  );

  GroupMessage copyWithMedia({
    List<MessageAttachment>? attachments,
    List<VoiceMessageInfo>? voiceSegments,
  }) => GroupMessage(
    messageId: messageId,
    roomId: roomId,
    sequence: sequence,
    speakerType: speakerType,
    speakerAssistantId: speakerAssistantId,
    content: content,
    reasoning: reasoning,
    replyToMessageId: replyToMessageId,
    rootTriggerMessageId: rootTriggerMessageId,
    roundPosition: roundPosition,
    requestType: requestType,
    revision: revision,
    currentMessageVersionId: currentMessageVersionId,
    currentAnswerVersionId: currentAnswerVersionId,
    currentAnswerVersionNumber: currentAnswerVersionNumber,
    answerVersionCount: answerVersionCount,
    answerStatus: answerStatus,
    failureHint: failureHint,
    toolUsed: toolUsed,
    visible: visible,
    contextVisible: contextVisible,
    isDeleted: isDeleted,
    contentHash: contentHash,
    upstreamRevisionHash: upstreamRevisionHash,
    upstreamStatus: upstreamStatus,
    createdAt: createdAt,
    updatedAt: updatedAt,
    attachments: attachments ?? this.attachments,
    voiceSegments: voiceSegments ?? this.voiceSegments,
  );

  GroupMessage copyWithAttachments(List<MessageAttachment> value) =>
      copyWithMedia(attachments: value);
}

class GroupMessageVersion {
  const GroupMessageVersion({
    required this.versionId,
    required this.messageId,
    required this.versionNumber,
    required this.content,
    required this.contentHash,
    this.editedBy,
    required this.createdAt,
  });

  final String versionId;
  final String messageId;
  final int versionNumber;
  final String content;
  final String contentHash;
  final String? editedBy;
  final DateTime createdAt;

  factory GroupMessageVersion.fromRow(Map<String, Object?> row) =>
      GroupMessageVersion(
        versionId: row['version_id']! as String,
        messageId: row['message_id']! as String,
        versionNumber: row['version_number']! as int,
        content: row['content']! as String,
        contentHash: row['content_hash']! as String,
        editedBy: row['edited_by'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
      );
}

class GroupAnswerVersion {
  const GroupAnswerVersion({
    required this.answerVersionId,
    required this.messageId,
    required this.versionNumber,
    required this.content,
    this.reasoning,
    required this.answerStatus,
    this.failureHint,
    this.promptTokens,
    this.completionTokens,
    required this.toolUsed,
    required this.upstreamRevisionHash,
    required this.contextCutoffSequence,
    required this.branchActive,
    required this.createdAt,
    this.completedAt,
  });

  final String answerVersionId;
  final String messageId;
  final int versionNumber;
  final String content;
  final String? reasoning;
  final String answerStatus;
  final String? failureHint;
  final int? promptTokens;
  final int? completionTokens;
  final bool toolUsed;
  final String upstreamRevisionHash;
  final int contextCutoffSequence;
  final bool branchActive;
  final DateTime createdAt;
  final DateTime? completedAt;

  factory GroupAnswerVersion.fromRow(Map<String, Object?> row) =>
      GroupAnswerVersion(
        answerVersionId: row['answer_version_id']! as String,
        messageId: row['message_id']! as String,
        versionNumber: row['version_number']! as int,
        content: row['content'] as String? ?? '',
        reasoning: row['reasoning'] as String?,
        answerStatus: row['answer_status']! as String,
        failureHint: row['failure_hint'] as String?,
        promptTokens: row['prompt_tokens'] as int?,
        completionTokens: row['completion_tokens'] as int?,
        toolUsed: row['tool_used'] == 1,
        upstreamRevisionHash: row['upstream_revision_hash'] as String? ?? '',
        contextCutoffSequence: row['context_cutoff_sequence'] as int? ?? 0,
        branchActive: row['branch_active'] == 1,
        createdAt: DateTime.parse(row['created_at']! as String),
        completedAt: _date(row['completed_at']),
      );
}

class GroupRound {
  const GroupRound({
    required this.roundId,
    required this.roomId,
    this.rootTriggerMessageId,
    this.triggerMessageVersionId,
    required this.requestType,
    this.branchParentRoundId,
    required this.branchActive,
    required this.participantOrder,
    required this.status,
    this.activeJobId,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String roundId;
  final String roomId;
  final String? rootTriggerMessageId;
  final String? triggerMessageVersionId;
  final String requestType;
  final String? branchParentRoundId;
  final bool branchActive;
  final List<String> participantOrder;
  final String status;
  final String? activeJobId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
}

class GroupRoundStep {
  const GroupRoundStep({
    required this.roundId,
    required this.position,
    required this.assistantId,
    required this.logicalMessageId,
    this.jobRequestId,
    required this.status,
    this.errorCode,
    this.startedAt,
    this.completedAt,
  });

  final String roundId;
  final int position;
  final String assistantId;
  final String logicalMessageId;
  final String? jobRequestId;
  final String status;
  final String? errorCode;
  final DateTime? startedAt;
  final DateTime? completedAt;

  factory GroupRoundStep.fromRow(Map<String, Object?> row) => GroupRoundStep(
    roundId: row['round_id']! as String,
    position: row['position']! as int,
    assistantId: row['assistant_id']! as String,
    logicalMessageId: row['logical_message_id']! as String,
    jobRequestId: row['job_request_id'] as String?,
    status: row['status']! as String,
    errorCode: row['error_code'] as String?,
    startedAt: _date(row['started_at']),
    completedAt: _date(row['completed_at']),
  );
}

DateTime? _date(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
