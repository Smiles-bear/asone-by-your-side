import 'dart:typed_data';
import 'package:characters/characters.dart';

const worldEntryKeywordMaxLength = 20;

enum WorldUsageMode { always, relevant }

class WorldEntry {
  const WorldEntry({
    required this.id,
    required this.assistantId,
    required this.category,
    required this.title,
    required this.content,
    this.enabled = true,
    this.usageMode = WorldUsageMode.relevant,
    this.keywords = const [],
    this.sourceMaterialId,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, assistantId, category, title, content;
  final bool enabled;
  final WorldUsageMode usageMode;
  final List<String> keywords;
  final String? sourceMaterialId;
  final DateTime createdAt, updatedAt;
}

class WorldEntryDraft {
  const WorldEntryDraft({
    required this.title,
    required this.content,
    this.category = '其他资料',
    this.usageMode = WorldUsageMode.relevant,
    this.keywords = const [],
    this.enabled = true,
  });
  final String category, title, content;
  final WorldUsageMode usageMode;
  final List<String> keywords;
  final bool enabled;
  void validate() {
    if (title.trim().isEmpty) throw const FormatException('请填写条目标题');
    if (content.trim().isEmpty) throw const FormatException('请填写条目内容');
    if (keywords.any((k) => k.trim().isEmpty)) {
      throw const FormatException('请输入关键词');
    }
    if (keywords.any(
      (k) => k.trim().characters.length > worldEntryKeywordMaxLength,
    )) {
      throw const FormatException('每个关键词最多 20 字');
    }
  }
}

class WorldEntryCategory {
  const WorldEntryCategory(this.name, this.count, {int? enabledCount})
    : enabledCount = enabledCount ?? count;
  final String name;
  final int count;
  final int enabledCount;
}

class WorldEntryInput {
  const WorldEntryInput({
    required this.text,
    this.name = '',
    this.format = 'text',
    this.bytes,
  });
  final String text, name, format;
  final Uint8List? bytes;
}

abstract interface class WorldEntriesApi {
  Future<List<WorldEntryCategory>> categories(String assistantId);
  Future<List<WorldEntry>> list(
    String assistantId,
    String category, {
    int offset = 0,
    int limit = 40,
  });
  Future<WorldEntry?> get(String assistantId, String entryId);
  Future<void> save(
    String assistantId,
    WorldEntryDraft value, {
    String? entryId,
  });
  Future<void> setEnabled(String assistantId, String entryId, bool enabled);
  Future<void> setAllEnabled(String assistantId, bool enabled);
  Future<void> delete(String assistantId, String entryId);
  Future<bool> needsReorganization(String assistantId);
  Future<String> stageInput(String assistantId, WorldEntryInput input);
  Future<String> startStaged(String assistantId, List<String> sourceIds);
  Future<void> discardStaged(String assistantId, List<String> sourceIds);
  Future<String> organize(
    String assistantId,
    List<WorldEntryInput> input, {
    bool reorganize = false,
  });
}
