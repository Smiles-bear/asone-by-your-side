import 'package:asone_contracts/asone_contracts.dart';
import 'theme/asone_theme.dart';
import 'widgets/asone_app_bar.dart';
import 'widgets/asone_empty_state.dart';
import 'widgets/asone_feedback.dart';
import 'widgets/asone_icons.dart';
import 'widgets/asone_list_tile.dart';
import 'pages/model_service_list_page.dart';
import 'package:flutter/material.dart';

import 'community_chat_page.dart';

/// 社区版助手页：沿用正式版列表的视觉结构，只保留本地助手和 API 对话入口。
class CommunityAssistantListPage extends StatefulWidget {
  const CommunityAssistantListPage({super.key});

  @override
  State<CommunityAssistantListPage> createState() =>
      _CommunityAssistantListPageState();
}

class _CommunityAssistantListPageState
    extends State<CommunityAssistantListPage> {
  List<Assistant> _assistants = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAssistants();
  }

  Future<void> _loadAssistants() async {
    try {
      final list = await OpenCoreBinding.instance.assistants.getAssistants();
      if (!mounted) return;
      setState(() {
        _assistants = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('助手加载失败，请稍后重试');
    }
  }

  Future<void> _createAssistant() async {
    final services = await OpenCoreBinding.instance.modelServices
        .getModelServices();
    final usableServices = services
        .where(
          (service) =>
              service.baseUrl.trim().isNotEmpty &&
              !service.baseUrl.contains('example.invalid') &&
              service.model.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (usableServices.isEmpty) {
      _toast('请先在“我的 > 模型服务”添加可用配置');
      return;
    }

    final draft = await _showAssistantDialog(usableServices);
    if (!mounted || draft == null) return;

    try {
      await OpenCoreBinding.instance.assistants
          .createAssistantWithPrimaryConversation(
            name: draft.name,
            primaryModelServiceId: draft.modelServiceId,
          );
      await _loadAssistants();
      _toast('助手已创建，可在对话页开始聊天');
    } catch (_) {
      if (mounted) _toast('创建助手失败，请稍后重试');
    }
  }

  Future<_AssistantDraft?> _showAssistantDialog(
    List<ModelService> services,
  ) async {
    final nameController = TextEditingController();
    var selectedServiceId = services.first.id;
    final result = await showDialog<_AssistantDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建助手'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '助手名称',
                  hintText: '例如：我的 API 助手',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedServiceId,
                decoration: const InputDecoration(labelText: '模型服务'),
                items: [
                  for (final service in services)
                    DropdownMenuItem(
                      value: service.id,
                      child: Text('${service.name} · ${service.model}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedServiceId = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(
                  _AssistantDraft(
                    name: name,
                    modelServiceId: selectedServiceId,
                  ),
                );
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    return result;
  }

  Future<void> _openAssistant(Assistant assistant) async {
    if (assistant.modelServiceId.trim().isEmpty) {
      _toast('该助手还没有绑定模型服务');
      return;
    }
    try {
      final conversation = await OpenCoreBinding.instance.assistants
          .getOrCreatePrimaryConversation(assistant.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CommunityChatPage(
            initialConversation: conversation,
            initialAssistant: assistant,
          ),
        ),
      );
    } catch (_) {
      if (mounted) _toast('暂时无法打开助手对话');
    }
  }

  void _openModelServices() {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(builder: (_) => const ModelServiceListPage()),
        )
        .then((_) {
          if (mounted) _loadAssistants();
        });
  }

  void _toast(String message) {
    AsOneToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsOneTheme.mainPageBg,
      appBar: AsOneAppBar(
        title: '助手',
        mainPage: true,
        actions: [
          AsOneIconButton(
            key: const Key('community-assistant-create'),
            tooltip: '新建助手',
            icon: AsOneIconName.add,
            onPressed: _createAssistant,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _assistants.isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AsOneEmptyState(
                  icon: Icons.smart_toy_outlined,
                  title: '还没有助手',
                  description: '点右上角加号创建第一个助手',
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _openModelServices,
                  child: const Text('先去配置模型服务'),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: _loadAssistants,
              child: ListView.separated(
                itemCount: _assistants.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 0.5,
                  indent: 78,
                  color: AsOneTheme.divider,
                ),
                itemBuilder: (context, index) {
                  final assistant = _assistants[index];
                  return AsOneListTile(
                    key: ValueKey('community-assistant-${assistant.id}'),
                    title: assistant.name,
                    subtitle: assistant.mainModel.isEmpty
                        ? '未配置模型'
                        : assistant.mainModel,
                    avatarPath: assistant.avatar,
                    fallbackIcon: Icons.smart_toy_outlined,
                    fallbackText: assistant.name.isEmpty
                        ? '助'
                        : assistant.name.characters.first,
                    onTap: () => _openAssistant(assistant),
                  );
                },
              ),
            ),
    );
  }
}

final class _AssistantDraft {
  const _AssistantDraft({required this.name, required this.modelServiceId});

  final String name;
  final String modelServiceId;
}
