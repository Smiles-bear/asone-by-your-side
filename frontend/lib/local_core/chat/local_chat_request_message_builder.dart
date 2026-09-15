import 'dart:convert';
import 'dart:typed_data';

import '../chat_context_window_planner.dart';
import '../document_text_extractor.dart';

typedef LocalChatAttachmentBytesReader =
    Future<Uint8List?> Function(String attachmentId);

class LocalChatRequestMessageBuilder {
  const LocalChatRequestMessageBuilder({
    required this.readAttachmentBytes,
    this.documentTextExtractor = const DocumentTextExtractor(),
  });

  final LocalChatAttachmentBytesReader readAttachmentBytes;
  final DocumentTextExtractor documentTextExtractor;

  Future<List<Map<String, Object?>>> build(ChatContextWindowPlan plan) async {
    final messages = <Map<String, Object?>>[];
    final terminalSystemParts = <Map<String, String>>[];

    for (final part in plan.systemParts) {
      if (_isTerminalSystemPart(part['kind']!)) {
        terminalSystemParts.add(part);
      } else {
        messages.add(_systemMessage(part));
      }
    }
    for (final item in plan.recentMessages) {
      messages.add(await _recentMessage(item));
    }
    for (final part in terminalSystemParts) {
      messages.add(_terminalSystemMessage(part));
    }
    return messages;
  }

  bool _isTerminalSystemPart(String kind) =>
      kind == 'proactive_message_task' || kind == 'group_turn_instruction';

  Map<String, Object?> _systemMessage(Map<String, String> part) =>
      <String, Object?>{
        'role': 'system',
        'content': '${_systemPrefix(part['kind']!)}\n${part['content']}',
      };

  String _systemPrefix(String kind) => switch (kind) {
    'custom_instructions' => '【自定义指令】',
    'reply_mode_instruction' => '【回复方式】',
    'communication_style' => '【沟通偏好】',
    'behavior_boundaries' => '【行为边界】',
    'user_profile' => '【用户资料】',
    'timestamp' => '【当前日期】',
    'relationship_state' => '【关系状态】',
    'world_core' => '【世界事实】',
    'world_assistant_setting' => '【你在这个世界中的设定】',
    'world_user_setting' => '【用户在这个世界中的设定】',
    'world_schedule' => '【当前世界日程】',
    'world_current_space' => '【当前世界空间】',
    'world_dynamic' => '【当前相关世界资料】',
    'game_interaction' => '【最近游戏互动】',
    'game_summary' => '【游戏记录】',
    'relevant_history' => '【相关聊天历史】',
    'system_hint' => '【系统提示】',
    'mind_continuity' => '【刚刚发生的事】',
    'mind_sticky_notes' => '【当前相关小纸条】',
    'mind_calendar_state' => '【当前日历状态】',
    'proactive_style' => '【主动消息风格】',
    'current_time' => '【当前时间】',
    'proactive_message_state' => '【主动消息状态】',
    'patrol_facts' => '【巡检事实】',
    'together_listen_state' => '【当前一起听状态】',
    'together_listen_event' => '【当前一起听事件】',
    'group_chat_contract' => '【群聊参与规则】',
    'group_chat_runtime' => '【当前群聊运行信息】',
    _ => '【相关长期记忆】',
  };

  Map<String, Object?> _terminalSystemMessage(Map<String, String> part) =>
      <String, Object?>{
        'role': 'system',
        'content': part['kind'] == 'group_turn_instruction'
            ? '【系统提示】\n${part['content']}'
            : '【主动消息任务】\n${part['content']}',
      };

  Future<Map<String, Object?>> _recentMessage(Map<String, Object?> item) async {
    final role = item['role'];
    var text = item['content'] as String? ?? '';
    final linkContext = item['link_context'] as String? ?? '';
    if (linkContext.isNotEmpty) text = '$text\n\n$linkContext';

    final imageParts = <Map<String, Object?>>[];
    final fileParts = <Map<String, Object?>>[];
    final refs = (item['attachment_refs'] as List?) ?? const [];
    for (final rawRef in refs) {
      text = await _appendAttachment(
        text: text,
        ref: (rawRef as Map).cast<String, Object?>(),
        imageParts: imageParts,
        fileParts: fileParts,
      );
    }

    if (imageParts.isEmpty && fileParts.isEmpty) {
      return <String, Object?>{'role': role, 'content': text};
    }
    return <String, Object?>{
      'role': role,
      'content': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'text',
          'text': text.isEmpty ? '请查看图片。' : text,
        },
        ...imageParts,
        ...fileParts,
      ],
    };
  }

  Future<String> _appendAttachment({
    required String text,
    required Map<String, Object?> ref,
    required List<Map<String, Object?>> imageParts,
    required List<Map<String, Object?>> fileParts,
  }) async {
    final attachmentId = ref['attachment_id'] as String?;
    if (attachmentId == null) return text;

    final mime = ref['mime_type'] as String? ?? '';
    final name = ref['name'] as String? ?? '附件';
    final bytes = await readAttachmentBytes(attachmentId);
    if (bytes == null) {
      if (mime == 'application/pdf') {
        throw const DocumentTextExtractionFailure('PDF 读取失败，请重新选择后重试');
      }
      return text;
    }
    if (mime.startsWith('image/')) {
      imageParts.add(<String, Object?>{
        'type': 'image_url',
        'image_url': <String, Object?>{
          'url': 'data:$mime;base64,${base64Encode(bytes)}',
        },
      });
      return text;
    }
    if (mime.startsWith('text/') || mime == 'application/json') {
      final limited = bytes.length > 200000 ? bytes.sublist(0, 200000) : bytes;
      return '$text\n\n【附件：$name】\n'
          '${utf8.decode(limited, allowMalformed: true)}';
    }
    if (mime == 'application/pdf') {
      final projection = documentTextExtractor.pdfChatProjection(
        sourceName: name,
        bytes: bytes,
      );
      fileParts.add(<String, Object?>{
        'type': 'file_data',
        'filename': name,
        'mime_type': mime,
        'data': base64Encode(bytes),
      });
      return '$text\n\n$projection';
    }
    return '$text\n\n【附件：$name，当前格式仅保留文件记录】';
  }
}
