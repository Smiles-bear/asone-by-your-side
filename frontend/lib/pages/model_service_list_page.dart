import 'dart:async';

import 'package:flutter/material.dart';

import 'package:asone_contracts/asone_contracts.dart'
    show
        ModelService,
        ModelServiceInUseException,
        ModelServiceRepositoryApi,
        OpenCoreBinding;

import '../services/debug_logger.dart';
import '../services/provider_registry.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_bottom_sheet.dart';
import '../widgets/asone_button.dart';
import '../widgets/asone_dialog.dart';
import '../widgets/asone_empty_state.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_input_dialog.dart';
import 'capability_detection_page.dart';
import 'model_service_form_page.dart';
import 'model_service_provider_select_page.dart';

class ModelServiceListPage extends StatefulWidget {
  const ModelServiceListPage({super.key, this.api});

  final ModelServiceRepositoryApi? api;

  @override
  State<ModelServiceListPage> createState() => _ModelServiceListPageState();
}

class _ModelServiceListPageState extends State<ModelServiceListPage> {
  late final ModelServiceRepositoryApi _api =
      widget.api ?? OpenCoreBinding.instance.modelServices;
  List<ModelService> _services = [];
  bool _loading = true;
  Map<String, List<Map<String, Object?>>> _capabilityCache = {};
  String? _retestingServiceId;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() => _loading = true);
    try {
      final list = await _api.getModelServices();
      await _loadCapabilities(list);
      if (!mounted) return;
      setState(() {
        _services = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('加载模型配置失败，请稍后重试');
    }
  }

  /// 仅加载与当前地址、Key、模型指纹一致的真实测试结果。
  Future<void> _loadCapabilities(List<ModelService> services) async {
    final cache = <String, List<Map<String, Object?>>>{};
    for (final service in services) {
      cache[service.id] = await _api.getModelCapabilityTests(service.id);
    }
    _capabilityCache = cache;
  }

  Future<void> _addService() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ModelServiceProviderSelectPage()),
    );
    if (result == true) {
      await _loadServices();
    }
  }

  Future<void> _editService(ModelService service) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ModelServiceFormPage(service: service)),
    );
    if (mounted) await _loadServices();
  }

  Future<void> _renameService(ModelService service) async {
    final result = await AsOneInputDialog.show(
      context,
      title: '重命名配置',
      hintText: '新名称',
      initialValue: service.name,
      confirmLabel: '确定',
      maxLines: 1,
    );

    if (result == null || result.isEmpty || result == service.name) return;

    try {
      await _api.updateModelService(service.id, {'name': result});
      await _loadServices();
    } catch (_) {
      if (!mounted) return;
      _toast('重命名失败，请稍后重试');
    }
  }

  Future<void> _deleteService(ModelService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AsOneDialog(
        title: '删除配置',
        content: Text('确定要删除「${service.name}」吗？此操作无法撤销。'),
        actions: [
          AsOneButton(
            label: '取消',
            onPressed: () => Navigator.pop(context, false),
            tone: AsOneButtonTone.secondary,
          ),
          AsOneButton(
            label: '删除',
            onPressed: () => Navigator.pop(context, true),
            tone: AsOneButtonTone.danger,
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.deleteModelService(service.id);
      await _loadServices();
    } on ModelServiceInUseException {
      if (!mounted) return;
      _toast('已有助手正在使用，请先为相关助手更换模型');
    } catch (error) {
      DebugLogger.instance.error(
        '删除模型配置失败',
        tag: 'ModelServiceList',
        details: error.toString(),
      );
      if (!mounted) return;
      _toast('删除失败，请检查设备存储后重试');
    }
  }

  Future<void> _retestService(ModelService service) async {
    if (service.model.isEmpty) return;
    setState(() => _retestingServiceId = service.id);
    try {
      final detected = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => CapabilityDetectionPage(serviceId: service.id),
        ),
      );
      if (!mounted) return;
      if (detected == true) {
        final results = await _api.getModelCapabilityTests(service.id);
        if (!mounted) return;
        setState(() {
          _capabilityCache[service.id] = results;
        });
      }
    } finally {
      if (mounted) setState(() => _retestingServiceId = null);
    }
  }

  Future<void> _showServiceMenu(ModelService service) async {
    final action = await AsOneBottomSheet.showActions<String>(
      context,
      title: service.name,
      actions: const [
        AsOneSheetAction(
          value: 'rename',
          label: '重命名',
          icon: AsOneIconName.edit,
        ),
        AsOneSheetAction(
          value: 'delete',
          label: '删除',
          icon: AsOneIconName.delete,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') await _renameService(service);
    if (action == 'delete') await _deleteService(service);
  }

  void _toast(String msg) {
    AsOneToast.show(context, msg);
  }

  static const _badgeOrder = [
    ('text_chat', '文'),
    ('vision_input', '视'),
    ('client_tool_calling', '工'),
    ('streaming', '流'),
    ('structured_output', '结'),
  ];

  Widget _buildCapabilityBadges(String serviceId) {
    final results = _capabilityCache[serviceId] ?? const [];
    if (results.isEmpty) {
      return const Text('检测失败，点击重新检测', style: AsOneTheme.captionStyle);
    }
    final supported = results
        .where((item) => item['verdict'] == 'supported')
        .map((item) => item['capability'])
        .toSet();
    final badges = <Widget>[];
    for (final (cap, label) in _badgeOrder) {
      if (!supported.contains(cap)) continue;
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            color: AsOneTheme.cardBg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AsOneTheme.accent),
          ),
        ),
      );
    }
    if (badges.isEmpty) {
      return const Text('检测失败，点击重新检测', style: AsOneTheme.captionStyle);
    }
    return Wrap(children: badges);
  }

  String _providerDisplayName(ModelService service) =>
      ProviderRegistry.instance.get(service.providerId).displayName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AsOneAppBar(
        title: '模型服务',
        actions: [
          AsOneIconButton(
            tooltip: '添加模型服务',
            icon: AsOneIconName.add,
            onPressed: _addService,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _services.isEmpty
          ? AsOneEmptyState(
              icon: asOneIconData(AsOneIconName.sliders),
              title: '还没有模型配置',
              description: '点击右上角添加模型服务',
            )
          : RefreshIndicator(
              onRefresh: _loadServices,
              child: ListView.separated(
                itemCount: _services.length,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final service = _services[index];
                  final isRetesting = _retestingServiceId == service.id;
                  return Material(
                    color: const Color(0xFFFFFDFC),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Color(0xFFF0E5E0)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0EA),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: const AsOneIcon(
                          AsOneIconName.cloud,
                          color: AsOneTheme.iconAccent,
                          size: 23,
                        ),
                      ),
                      title: Text(
                        service.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            _providerDisplayName(service),
                            style: AsOneTheme.captionStyle,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            service.model.isEmpty ? '未识别模型' : service.model,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AsOneTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildCapabilityBadges(service.id),
                        ],
                      ),
                      trailing: isRetesting
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : AsOneIconButton(
                              tooltip: '重新检测',
                              icon: AsOneIconName.refresh,
                              onPressed:
                                  service.model.isEmpty ||
                                      _retestingServiceId != null
                                  ? null
                                  : () => _retestService(service),
                            ),
                      onTap: () => _editService(service),
                      onLongPress: () => _showServiceMenu(service),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
