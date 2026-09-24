import 'package:asone_contracts/asone_contracts.dart';
import 'theme/asone_theme.dart';
import 'widgets/asone_app_bar.dart';
import 'widgets/asone_feedback.dart';
import 'widgets/asone_icons.dart';
import 'package:flutter/material.dart';

/// 社区版助手的公开配置页。
///
/// 只编辑聊天链路需要的名称和模型服务；正式版的记忆、语音、工具等
/// 私有能力不会在社区版里生成入口。
class CommunityAssistantFormPage extends StatefulWidget {
  const CommunityAssistantFormPage({super.key, this.assistant});

  final Assistant? assistant;

  @override
  State<CommunityAssistantFormPage> createState() =>
      _CommunityAssistantFormPageState();
}

class _CommunityAssistantFormPageState
    extends State<CommunityAssistantFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  List<ModelService> _services = const [];
  String? _selectedServiceId;
  bool _loading = true;
  bool _saving = false;

  bool get _editing => widget.assistant != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.assistant?.name ?? '');
    _loadServices();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final all = await OpenCoreBinding.instance.modelServices
          .getModelServices();
      final usable = all
          .where(
            (service) =>
                service.baseUrl.trim().isNotEmpty &&
                !service.baseUrl.contains('example.invalid') &&
                service.model.trim().isNotEmpty,
          )
          .toList(growable: false);
      final current = widget.assistant?.modelServiceId;
      if (!mounted) return;
      setState(() {
        _services = usable;
        _selectedServiceId = usable.any((service) => service.id == current)
            ? current
            : usable.firstOrNull?.id;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('模型服务加载失败，请稍后重试');
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final serviceId = _selectedServiceId;
    if (serviceId == null || serviceId.isEmpty) {
      _toast('请先配置并选择模型服务');
      return;
    }
    final service = _services.firstWhere((item) => item.id == serviceId);
    setState(() => _saving = true);
    try {
      final Assistant result;
      if (_editing) {
        result = await OpenCoreBinding.instance.assistants.updateAssistant(
          widget.assistant!.id,
          {
            'name': name,
            'main_model': service.model,
            'model_service_id': service.id,
          },
        );
      } else {
        result =
            (await OpenCoreBinding.instance.assistants
                    .createAssistantWithPrimaryConversation(
                      name: name,
                      primaryModelServiceId: service.id,
                    ))
                .assistant;
      }
      if (!mounted) return;
      Navigator.of(context).pop(CommunityAssistantFormResult.updated(result));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败，请检查模型服务后重试');
    }
  }

  Future<void> _delete() async {
    final assistant = widget.assistant;
    if (assistant == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除助手？'),
        content: Text('“${assistant.name}”及其主对话会从本机删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await OpenCoreBinding.instance.assistants.deleteAssistant(assistant.id);
      if (mounted) {
        Navigator.of(context).pop(const CommunityAssistantFormResult.deleted());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('删除失败，请稍后重试');
    }
  }

  void _toast(String message) => AsOneToast.show(context, message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsOneTheme.mainPageBg,
      appBar: AsOneAppBar(
        title: _editing ? '编辑助手' : '新建助手',
        actions: [
          if (_editing)
            AsOneIconButton(
              tooltip: '删除助手',
              icon: AsOneIconName.delete,
              onPressed: _saving ? null : _delete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  TextFormField(
                    controller: _nameController,
                    autofocus: !_editing,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '助手名称',
                      hintText: '例如：我的 API 助手',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入助手名称'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedServiceId,
                    decoration: const InputDecoration(
                      labelText: '模型服务',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final service in _services)
                        DropdownMenuItem(
                          value: service.id,
                          child: Text('${service.name} · ${service.model}'),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _selectedServiceId = value),
                    validator: (value) => value == null ? '请选择模型服务' : null,
                  ),
                  if (_services.isEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '还没有可用的模型服务，请先在“我的 > 模型服务”完成配置。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    '社区版只开放本地助手、API 聊天和基础对话管理；记忆、语音、工具等能力暂未开放。',
                    style: TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
    );
  }
}

class CommunityAssistantFormResult {
  const CommunityAssistantFormResult.updated(this.assistant) : deleted = false;

  const CommunityAssistantFormResult.deleted()
    : assistant = null,
      deleted = true;

  final Assistant? assistant;
  final bool deleted;
}
