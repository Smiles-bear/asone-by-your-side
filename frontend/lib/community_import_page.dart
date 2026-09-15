import 'dart:io';

import 'local_core/import/import_job.dart';
import 'local_core/import/import_plan.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'public_core.dart';

/// 社区版聊天记录导入：仅执行解析、预览与本地导入，不触发记忆重建。
class CommunityImportPage extends StatefulWidget {
  const CommunityImportPage({super.key, required this.core});

  final PublicCore core;

  @override
  State<CommunityImportPage> createState() => _CommunityImportPageState();
}

class _CommunityImportPageState extends State<CommunityImportPage> {
  String? _summary;
  String? _error;
  bool _working = false;

  Future<void> _pickAndImport() async {
    if (_working) return;
    final selected = await FilePicker.pickFiles(withData: false);
    final path = selected == null || selected.files.isEmpty
        ? null
        : selected.files.first.path;
    if (path == null) return;
    setState(() {
      _working = true;
      _error = null;
      _summary = null;
    });
    try {
      final created = await widget.core.imports.createImportFromFile(
        File(path),
      );
      final preview = created.preview;
      if (preview.errors.isNotEmpty || preview.sourceConversations.isEmpty) {
        throw StateError(
          preview.errors.isEmpty ? '文件中没有可导入的聊天记录' : preview.errors.join('\n'),
        );
      }
      if (!preview.canStart && preview.uncertainRoles.isEmpty) {
        throw StateError('文件预检未通过，无法安全导入。');
      }
      final roleMappings = await _confirmRoleMappings(preview);
      if (roleMappings == null) return;
      final groups = preview.sourceConversations
          .map(
            (source) => ImportPlanGroup(
              groupId: 'community-${source.id}',
              sourceConversationIds: [source.id],
              assistantName: '导入助手',
              conversationTitle: source.title.trim().isEmpty
                  ? '导入对话'
                  : source.title,
            ),
          )
          .toList(growable: false);
      await widget.core.imports.submitGroupedImportPlan(
        created.job.jobId,
        GroupedImportPlan(
          groups: groups,
          roleMappings: roleMappings,
          conversationOrder: preview.sourceConversations
              .map((item) => item.id)
              .toList(),
        ),
      );
      await widget.core.imports.startImport(created.job.jobId);
      final status = await _waitForCompletion(created.job.jobId);
      if (status.status != 'completed') {
        final detail = status.errors.join('\n');
        throw StateError(detail.isEmpty ? '导入未完成，请检查文件内容后重试。' : detail);
      }
      if (!mounted) return;
      setState(
        () => _summary =
            '已导入 ${preview.conversationCount} 个对话、${preview.messageCount} 条消息。',
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<Map<String, String>?> _confirmRoleMappings(
    ImportPreview preview,
  ) async {
    if (preview.uncertainRoles.isEmpty) return const {};
    final mappings = <String, String>{
      for (final role in preview.uncertainRoles)
        role.sourceRole: _suggestRole(role.sourceRole),
    };
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('确认说话人角色'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('以下标签无法由文件格式可靠确认。请确认后再导入。'),
                const SizedBox(height: 12),
                for (final role in preview.uncertainRoles)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${role.sourceRole}（${role.messageCount} 条）',
                        ),
                      ),
                      DropdownButton<String>(
                        value: mappings[role.sourceRole],
                        items: const [
                          DropdownMenuItem(value: 'user', child: Text('我')),
                          DropdownMenuItem(
                            value: 'assistant',
                            child: Text('助手'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(
                            () => mappings[role.sourceRole] = value,
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(Map<String, String>.unmodifiable(mappings)),
              child: const Text('确认并导入'),
            ),
          ],
        ),
      ),
    );
  }

  String _suggestRole(String sourceRole) {
    switch (sourceRole.trim().toLowerCase()) {
      case 'user':
      case 'human':
      case 'me':
      case '用户':
      case '我':
        return 'user';
      case 'assistant':
      case 'ai':
      case 'bot':
      case '助手':
        return 'assistant';
      default:
        return 'user';
    }
  }

  Future<ImportJob> _waitForCompletion(String jobId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      final status = await widget.core.imports.getImportStatus(jobId);
      if (status == null) throw StateError('导入任务不存在');
      if (status.isTerminal) return status;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('导入超时，任务仍在后台运行；请稍后重试。');
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导入聊天记录')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '支持 JSON、JSONL、HTML、Markdown、文本和 ZIP 聊天记录。导入仅写入本机，不触发记忆整理。',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('community-import-file'),
            onPressed: _working ? null : _pickAndImport,
            icon: const Icon(Icons.upload_file),
            label: Text(_working ? '正在导入…' : '选择聊天记录文件'),
          ),
          if (_summary != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_summary!),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
  );
}
