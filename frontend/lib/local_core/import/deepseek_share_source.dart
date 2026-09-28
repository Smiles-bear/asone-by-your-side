import 'dart:convert';
import 'dart:typed_data';

import 'link_source_reader.dart';

Uri? deepSeekShareContentUri(Uri uri) {
  if (uri.scheme != 'https' || uri.host.toLowerCase() != 'chat.deepseek.com') {
    return null;
  }
  final match = RegExp(r'^/share/([A-Za-z0-9_-]+)/?$').firstMatch(uri.path);
  if (match == null) return null;
  return Uri.https('chat.deepseek.com', '/api/v0/share/content', {
    'share_id': match.group(1)!,
  });
}

Map _shareBody(Uint8List bytes) {
  const unavailable = PublicLinkReadException('分享链接已失效或无法访问，请重新分享后重试');
  const unsupported = PublicLinkReadException('分享内容结构暂不支持，请改用导出的聊天文件');
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw unsupported;
  }
  if (decoded is! Map) throw unsupported;
  if (decoded['code'] != 0) throw unavailable;
  final data = decoded['data'];
  if (data is! Map) throw unsupported;
  if (data['biz_code'] != 0) throw unavailable;
  final body = data['biz_data'];
  if (body is! Map || body['messages'] is! List) throw unsupported;
  return body;
}

PublicLinkContent decodeDeepSeekShare(Uint8List bytes) {
  final body = _shareBody(bytes);
  final normalized = _orderedShareMessageChains(body['messages'] as List);
  final title = body['title'] is String && (body['title'] as String).isNotEmpty
      ? body['title'] as String
      : 'DeepSeek 导入会话';
  final root = normalized.chains.length == 1
      ? <String, Object?>{'title': title, 'messages': normalized.chains.single}
      : <String, Object?>{
          'conversations': [
            for (var index = 0; index < normalized.chains.length; index++)
              {
                'id': 'deepseek-chain-${index + 1}',
                'title': '$title（${index + 1}/${normalized.chains.length}）',
                'messages': normalized.chains[index],
              },
          ],
        };
  return PublicLinkContent(
    name: 'deepseek-share.json',
    bytes: Uint8List.fromList(utf8.encode(jsonEncode(root))),
  );
}

({List<List<Map<String, Object?>>> chains}) _orderedShareMessageChains(
  List messages,
) {
  const unsupported = PublicLinkReadException('分享内容结构暂不支持，请改用导出的聊天文件');
  if (messages.isEmpty) throw const PublicLinkReadException('分享中没有可导入的消息');
  final byId = <Object, Map<String, Object?>>{};
  var thinkingFragments = 0;
  var auxiliaryFragments = 0;
  var fileFragments = 0;
  var skippedInternalMessages = 0;
  for (final m in messages) {
    if (m is! Map ||
        m['message_id'] == null ||
        !const {
          'USER',
          'ASSISTANT',
          'SYSTEM',
          'user',
          'assistant',
          'system',
        }.contains(m['role'])) {
      throw unsupported;
    }
    if (byId.containsKey(m['message_id'])) throw unsupported;
    final body = _deepSeekMessageContent(m);
    thinkingFragments += body.thinkingFragments;
    auxiliaryFragments += body.auxiliaryFragments;
    fileFragments += body.fileFragments;
    if (body.content == null) skippedInternalMessages++;
    byId[m['message_id']!] = {
      ...m.cast<Object?, Object?>(),
      '_visible_content': body.content,
    }.cast<String, Object?>();
  }
  final childByParent = <Object, Map<String, Object?>>{};
  for (final message in byId.values) {
    final parent = message['parent_id'];
    if (byId.containsKey(parent)) {
      if (childByParent.containsKey(parent)) {
        throw const PublicLinkReadException('分享包含多个回复分支，请分享需要导入的完整对话分支');
      }
      childByParent[parent!] = message;
    }
  }
  final roots = byId.values
      .where((message) => !byId.containsKey(message['parent_id']))
      .toList(growable: false);
  if (roots.isEmpty) throw unsupported;
  final emitted = <Object>{};
  final chains = <List<Map<String, Object?>>>[];
  for (final root in roots) {
    final chain = <Map<String, Object?>>[];
    Map<String, Object?>? current = root;
    while (current != null) {
      final id = current['message_id']!;
      if (!emitted.add(id)) throw unsupported;
      final content = current['_visible_content'];
      if (content is String) chain.add(_visibleMessage(current, content));
      current = childByParent[id];
    }
    if (chain.isNotEmpty) chains.add(chain);
  }
  if (emitted.length != byId.length) throw unsupported;
  if (chains.isEmpty) throw const PublicLinkReadException('分享中没有可导入的消息');
  final first = chains.first.first;
  first['deepseek_omitted_thinking_count'] = thinkingFragments;
  first['deepseek_omitted_auxiliary_count'] = auxiliaryFragments;
  first['deepseek_file_fragment_count'] = fileFragments;
  first['deepseek_skipped_internal_message_count'] = skippedInternalMessages;
  return (chains: chains);
}

Map<String, Object?> _visibleMessage(
  Map<String, Object?> message,
  String content,
) => {
  'id': message['message_id'].toString(),
  'sender': message['role'].toString().toLowerCase(),
  'content': content,
  'inserted_at': message['inserted_at'],
};

({
  String? content,
  int thinkingFragments,
  int auxiliaryFragments,
  int fileFragments,
})
_deepSeekMessageContent(Map message) {
  const unsupported = PublicLinkReadException('分享内容结构暂不支持，请改用导出的聊天文件');
  final legacy = message['content'];
  if (legacy is String) {
    return (
      content: legacy,
      thinkingFragments: 0,
      auxiliaryFragments: 0,
      fileFragments: 0,
    );
  }
  if (legacy != null) throw unsupported;
  final fragments = message['fragments'];
  if (fragments is! List || fragments.isEmpty) throw unsupported;
  final role = message['role'].toString().toUpperCase();
  final expected = switch (role) {
    'USER' => 'REQUEST',
    'ASSISTANT' => 'RESPONSE',
    _ => null,
  };
  if (expected == null) throw unsupported;
  final contents = <String>[];
  var thinkingFragments = 0;
  var auxiliaryFragments = 0;
  var fileFragments = 0;
  for (final fragment in fragments) {
    if (fragment is! Map || fragment['type'] is! String) throw unsupported;
    final type = fragment['type'].toString().toUpperCase();
    if (type == expected) {
      final content = fragment['content'];
      if (content is! String) throw unsupported;
      if (content.isNotEmpty) contents.add(content);
      continue;
    }
    if (role == 'ASSISTANT' && type == 'THINK') {
      if (fragment['content'] is! String) throw unsupported;
      thinkingFragments++;
      continue;
    }
    if (role == 'ASSISTANT' &&
        const {'TIP', 'SEARCH', 'TOOL_SEARCH'}.contains(type)) {
      if (fragment['content'] is! String) throw unsupported;
      auxiliaryFragments++;
      continue;
    }
    if (role == 'USER' && type == 'FILE') {
      if (fragment['content'] != null || fragment['files'] is! List) {
        throw unsupported;
      }
      fileFragments++;
      continue;
    }
    throw unsupported;
  }
  final omittedCount = thinkingFragments + auxiliaryFragments + fileFragments;
  if (contents.isEmpty && omittedCount == 0) throw unsupported;
  return (
    content: contents.isEmpty ? null : contents.join('\n'),
    thinkingFragments: thinkingFragments,
    auxiliaryFragments: auxiliaryFragments,
    fileFragments: fileFragments,
  );
}
