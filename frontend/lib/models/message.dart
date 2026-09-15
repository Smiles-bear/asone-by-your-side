import '../services/chat_time_display.dart';

/// 消息模型。
class Message {
  final String? id; // 消息ID（后端返回，用于删除）
  final String role; // 'user' 或 'assistant'
  final String content;
  final String? answerStatus;
  final String? failureHint;
  final int? elapsedMs;
  final DateTime? replyStartedAt;
  final bool toolUsed;
  final bool streaming; // 是否正在流式接收中（用于显示光标等）
  final DateTime? createdAt; // 消息创建时间（用于时间分隔线）
  final String timestampStatus;
  final int? sourceSequence;
  final List<MessageAttachment> attachments;
  final String? assistantTurnId; // 所属 assistant turn（连续消息多段共享）
  final int segmentIndex; // turn 内段序号（连续消息）
  final List<String>? segments; // 可选：消息的显示分段（从 message_segments 读取）
  final String? reasoning; // 推理过程内容（thinking/reasoning）
  final VoiceMessageInfo? voice;
  final List<VoiceMessageInfo> voiceSegments;
  final List<MessageDirectorInfo> directorScripts;
  final String? currentAnswerVersionId;
  final ConfigurationHelpCardInfo? configurationHelp;
  final ToolConfirmationCardInfo? toolConfirmation;

  const Message({
    this.id,
    required this.role,
    required this.content,
    this.answerStatus,
    this.failureHint,
    this.elapsedMs,
    this.replyStartedAt,
    this.toolUsed = false,
    this.streaming = false,
    this.createdAt,
    this.timestampStatus = 'exact',
    this.sourceSequence,
    this.attachments = const [],
    this.assistantTurnId,
    this.segmentIndex = 0,
    this.segments,
    this.reasoning,
    this.voice,
    this.voiceSegments = const [],
    this.directorScripts = const [],
    this.currentAnswerVersionId,
    this.configurationHelp,
    this.toolConfirmation,
  });

  Message copyWith({
    String? id,
    String? content,
    String? answerStatus,
    String? failureHint,
    int? elapsedMs,
    DateTime? replyStartedAt,
    bool? toolUsed,
    bool? streaming,
    DateTime? createdAt,
    String? assistantTurnId,
    int? segmentIndex,
    List<String>? segments,
    String? reasoning,
    VoiceMessageInfo? voice,
    List<VoiceMessageInfo>? voiceSegments,
    List<MessageDirectorInfo>? directorScripts,
    String? currentAnswerVersionId,
    ConfigurationHelpCardInfo? configurationHelp,
    ToolConfirmationCardInfo? toolConfirmation,
  }) => Message(
    id: id ?? this.id,
    role: role,
    content: content ?? this.content,
    answerStatus: answerStatus ?? this.answerStatus,
    failureHint: failureHint ?? this.failureHint,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    replyStartedAt: replyStartedAt ?? this.replyStartedAt,
    toolUsed: toolUsed ?? this.toolUsed,
    streaming: streaming ?? this.streaming,
    createdAt: createdAt ?? this.createdAt,
    timestampStatus: timestampStatus,
    sourceSequence: sourceSequence,
    attachments: attachments,
    assistantTurnId: assistantTurnId ?? this.assistantTurnId,
    segmentIndex: segmentIndex ?? this.segmentIndex,
    segments: segments ?? this.segments,
    reasoning: reasoning ?? this.reasoning,
    voice: voice ?? this.voice,
    voiceSegments: voiceSegments ?? this.voiceSegments,
    directorScripts: directorScripts ?? this.directorScripts,
    currentAnswerVersionId:
        currentAnswerVersionId ?? this.currentAnswerVersionId,
    configurationHelp: configurationHelp ?? this.configurationHelp,
    toolConfirmation: toolConfirmation ?? this.toolConfirmation,
  );

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String?,
    role: json['role'] as String,
    content: json['content'] as String,
    answerStatus: json['answer_status'] as String?,
    failureHint: json['failure_hint'] as String?,
    elapsedMs: json['elapsed_ms'] as int?,
    replyStartedAt: json['reply_started_at'] is String
        ? DateTime.tryParse(json['reply_started_at'] as String)
        : null,
    toolUsed: (json['tool_used'] as int? ?? 0) == 1,
    streaming: json['answer_status'] == 'streaming',
    createdAt: ChatTimeDisplay.resolveMessageTime(json),
    timestampStatus: json['timestamp_status'] as String? ?? 'exact',
    sourceSequence: json['source_sequence'] as int?,
    attachments: ((json['attachments'] as List?) ?? const [])
        .map(
          (item) =>
              MessageAttachment.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList(growable: false),
    assistantTurnId: json['assistant_turn_id'] as String?,
    segmentIndex: (json['segment_index'] as int?) ?? 0,
    reasoning: json['reasoning'] as String?,
    voice: json['voice_asset'] is Map
        ? VoiceMessageInfo.fromJson(
            (json['voice_asset'] as Map).cast<String, dynamic>(),
          )
        : null,
    voiceSegments: ((json['voice_assets'] as List?) ?? const [])
        .map(
          (item) =>
              VoiceMessageInfo.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList(growable: false),
    directorScripts: ((json['director_scripts'] as List?) ?? const [])
        .map(
          (item) => MessageDirectorInfo.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
        )
        .toList(growable: false),
    currentAnswerVersionId: json['current_answer_version_id']?.toString(),
    configurationHelp: json['configuration_help_feature_type'] == null
        ? null
        : ConfigurationHelpCardInfo(
            featureType: json['configuration_help_feature_type']!.toString(),
            currentStep: json['configuration_help_current_step']?.toString(),
            userNote: json['configuration_help_user_note']?.toString() ?? '',
            status: json['configuration_help_status']?.toString() ?? 'sent',
          ),
    toolConfirmation: json['tool_confirmation_request_id'] == null
        ? null
        : ToolConfirmationCardInfo(
            requestId: json['tool_confirmation_request_id']!.toString(),
            title: json['tool_confirmation_title']?.toString() ?? '确认执行操作',
            description:
                json['tool_confirmation_description']?.toString() ?? '',
            riskLevel:
                json['tool_confirmation_risk_level']?.toString() ?? 'unknown',
            status: json['tool_confirmation_status']?.toString() ?? 'expired',
          ),
  );

  Map<String, dynamic> toApiJson() => {'role': role, 'content': content};
}

class ToolConfirmationCardInfo {
  const ToolConfirmationCardInfo({
    required this.requestId,
    required this.title,
    required this.description,
    required this.riskLevel,
    required this.status,
  });

  final String requestId;
  final String title;
  final String description;
  final String riskLevel;
  final String status;
}

class ConfigurationHelpCardInfo {
  const ConfigurationHelpCardInfo({
    required this.featureType,
    required this.userNote,
    required this.status,
    this.currentStep,
  });

  final String featureType;
  final String? currentStep;
  final String userNote;
  final String status;
}

class MessageDirectorInfo {
  const MessageDirectorInfo({
    required this.scriptId,
    required this.segmentIndex,
    required this.script,
    required this.status,
    required this.revision,
    required this.mode,
  });

  final String scriptId;
  final int segmentIndex;
  final String script;
  final String status;
  final int revision;
  final String mode;

  bool get ready => status == 'done' && script.trim().isNotEmpty;

  factory MessageDirectorInfo.fromJson(Map<String, dynamic> json) =>
      MessageDirectorInfo(
        scriptId: json['script_id']?.toString() ?? '',
        segmentIndex: json['segment_index'] as int? ?? 0,
        script: json['script']?.toString() ?? '',
        status: json['status']?.toString() ?? 'none',
        revision: json['revision'] as int? ?? 0,
        mode: json['mode']?.toString() ?? 'normal',
      );
}

class VoiceMessageInfo {
  const VoiceMessageInfo({
    required this.assetId,
    required this.relativePath,
    required this.durationMs,
    required this.state,
    required this.transcriptState,
    required this.transcriptVisible,
    this.segmentIndex = 0,
    this.kind = 'user_recording',
    this.displayMode = 'voice_text',
    this.answerVersionId,
    this.transcript,
  });

  final String assetId;
  final String relativePath;
  final int durationMs;
  final String state;
  final String transcriptState;
  final bool transcriptVisible;
  final int segmentIndex;
  final String kind;
  final String displayMode;
  final String? answerVersionId;
  final String? transcript;

  bool get isReady => state == 'ready' && relativePath.isNotEmpty;
  bool get hasTranscript =>
      transcriptState == 'ready' &&
      transcript != null &&
      transcript!.trim().isNotEmpty;

  factory VoiceMessageInfo.fromJson(Map<String, dynamic> json) =>
      VoiceMessageInfo(
        assetId: json['asset_id']?.toString() ?? '',
        relativePath: json['relative_path']?.toString() ?? '',
        durationMs: json['duration_ms'] as int? ?? 0,
        state: json['state']?.toString() ?? 'failed',
        transcriptState: json['transcript_state']?.toString() ?? 'none',
        transcriptVisible:
            json['transcript_visible'] == 1 ||
            json['transcript_visible'] == true,
        segmentIndex: json['segment_index'] as int? ?? 0,
        kind: json['kind']?.toString() ?? 'user_recording',
        displayMode: json['display_mode']?.toString() ?? 'voice_text',
        answerVersionId: json['answer_version_id']?.toString(),
        transcript: json['transcript']?.toString(),
      );
}

class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.name,
    required this.status,
    this.storagePath,
    this.mimeType,
    this.sourceUrl,
    this.byteSize,
  });

  final String id;
  final String name;
  final String status;
  final String? storagePath;
  final String? mimeType;
  final String? sourceUrl;
  final int? byteSize;

  bool get isLink => sourceUrl != null && sourceUrl!.isNotEmpty;
  bool get isImage => !isLink && (mimeType?.startsWith('image/') ?? false);
  bool get isAvailable =>
      status == 'available' && (storagePath != null || isLink);

  factory MessageAttachment.fromJson(Map<String, dynamic> json) =>
      MessageAttachment(
        id: json['attachment_id']! as String,
        name: json['original_name']! as String,
        status: json['status']! as String,
        storagePath: json['storage_path'] as String?,
        mimeType: json['mime_type'] as String?,
        sourceUrl: json['source_url'] as String?,
        byteSize: json['byte_size'] as int?,
      );
}
