import 'dart:convert';
import 'package:characters/characters.dart';
import '../../features/world/world_entries.dart';
import '../../services/provider_adapters/model_output_contract.dart';
import '../../services/provider_adapters/structured_output_receiver.dart';

const worldEntryOrganizePrompt = '''
把提供的资料按主题整理为若干独立条目。每个条目应能独立理解，正文简洁，并保留原资料中的条件、否定、时间、关系和例外，不添加没有依据的内容。

输出一个 JSON 对象，根字段 entries 为数组，每个条目包含以下字段：
- category：字符串，按内容归类，使用简短的分类名称。
- title：字符串，简短概括这一条的主题。
- content：字符串，整理后的条目正文。
- usage_mode：字符串，只能为 always 或 relevant。always（每轮使用）适用于需要持续遵循的表达方式、身份、约定或通用规则；relevant（相关时使用）适用于涉及特定人物、地点、事件或主题时才需要的资料。
- keywords：字符串数组，提取有助于检索这一条的词语或短语，每项最多20个字；没有合适的关键词时使用空数组。

只输出 JSON 对象，不附解释或代码块。
''';

const worldEntryOutputContract = ModelOutputContract.structuredJson(
  schemaName: 'world_entries',
  schema: {
    'type': 'object',
    'properties': {
      'entries': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'category': {'type': 'string'},
            'title': {'type': 'string'},
            'content': {'type': 'string'},
            'usage_mode': {
              'type': 'string',
              'enum': ['always', 'relevant'],
            },
            'keywords': {
              'type': 'array',
              'items': {
                'type': 'string',
                'maxLength': worldEntryKeywordMaxLength,
              },
            },
          },
          'required': [
            'category',
            'title',
            'content',
            'usage_mode',
            'keywords',
          ],
          'additionalProperties': false,
        },
      },
    },
    'required': ['entries'],
    'additionalProperties': false,
  },
);

List<WorldEntryDraft> receiveWorldEntries(String raw) {
  final jsonText = extractSingleJsonValue(
    raw,
    schema: worldEntryOutputContract.schema!,
  );
  final value = jsonDecode(jsonText);
  if (value is! Map || value['entries'] is! List) {
    throw const FormatException('整理结果暂时无法读取，请重试');
  }
  final result = <WorldEntryDraft>[];
  for (final item in value['entries'] as List) {
    if (item is! Map) continue;
    final title = item['title'], content = item['content'];
    final category = item['category'], mode = item['usage_mode'];
    final keywords = item['keywords'] ?? const <String>[];
    if (title is! String ||
        title.trim().isEmpty ||
        content is! String ||
        content.trim().isEmpty ||
        category is! String ||
        category.trim().isEmpty ||
        !const {'always', 'relevant'}.contains(mode) ||
        keywords is! List ||
        keywords.any(
          (k) =>
              k is! String ||
              k.trim().isEmpty ||
              k.trim().characters.length > worldEntryKeywordMaxLength,
        )) {
      continue;
    }
    result.add(
      WorldEntryDraft(
        title: title,
        content: content,
        category: category,
        usageMode: mode == 'always'
            ? WorldUsageMode.always
            : WorldUsageMode.relevant,
        keywords: keywords.cast<String>(),
      ),
    );
  }
  if (result.isEmpty) throw const FormatException('整理结果暂时无法读取，请重试');
  return result;
}
