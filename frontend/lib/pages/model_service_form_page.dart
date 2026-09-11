import '../widgets/unsaved_changes_guard.dart';
import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart'
    show
        CapabilityDetectionApi,
        ModelDiscoveryApi,
        ModelService,
        ModelServiceRepositoryApi,
        OpenCoreBinding,
        ProtocolType;
import 'package:flutter/material.dart';

import '../services/model_endpoint.dart';
import '../services/provider_definition.dart';
import '../services/provider_registry.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_bottom_sheet.dart';
import '../widgets/asone_button.dart';
import '../widgets/asone_dialog.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_surface.dart';

class ModelServiceFormPage extends StatefulWidget {
  final ModelService? service;
  final ModelServiceRepositoryApi? modelServices;
  final ModelDiscoveryApi? discovery;
  final CapabilityDetectionApi? capabilityDetection;

  const ModelServiceFormPage({
    super.key,
    this.service,
    this.modelServices,
    this.discovery,
    this.capabilityDetection,
  });

  @override
  State<ModelServiceFormPage> createState() => _ModelServiceFormPageState();
}

class _ModelServiceFormPageState extends State<ModelServiceFormPage> {
  late final ModelServiceRepositoryApi _modelServices =
      widget.modelServices ?? OpenCoreBinding.instance.modelServices;
  late final ModelDiscoveryApi _discovery =
      widget.discovery ?? OpenCoreBinding.instance.modelDiscovery;
  late final CapabilityDetectionApi _capabilities =
      widget.capabilityDetection ??
      OpenCoreBinding.instance.capabilityDetection;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelNameController = TextEditingController();
  bool _saving = false;
  bool _discovering = false;
  bool _obscureKey = true;
  bool _testing = false;
  String? _selectedModel;
  String _selectedProtocol = 'auto';
  String? _selectedProviderId;
  List<Map<String, dynamic>> _discoveredModels = [];
  Map<String, String> _capabilityVerdicts = const {};
  String? _tempServiceId; // 临时保存的服务ID，用于discover
  String? _persistedModel;

  bool get _isEditing => widget.service != null;

  bool get _hasUnsavedModelChange =>
      _isEditing && _selectedModel != _persistedModel;

  ProviderDefinition? get _selectedProvider => _selectedProviderId == null
      ? null
      : ProviderRegistry.instance.get(_selectedProviderId!);

  bool get _isOfficialProvider =>
      _selectedProvider != null && _selectedProvider!.official;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final service = widget.service!;
      _nameController.text = service.name;
      _baseUrlController.text = service.baseUrl;
      _apiKeyController.text = service.apiKey;
      _selectedModel = service.model.isNotEmpty ? service.model : null;
      _persistedModel = _selectedModel;
      _modelNameController.text = service.model;
      _selectedProtocol = service.protocolType;
      _selectedProviderId = service.providerId;
      _tempServiceId = service.id;
      unawaited(_loadCapabilityVerdicts(service.id));
    }
  }

  Future<void> _loadCapabilityVerdicts(String serviceId) async {
    final results = await _modelServices.getModelCapabilityTests(serviceId);
    if (!mounted) return;
    setState(() {
      _capabilityVerdicts = {
        for (final result in results)
          result['capability'] as String: result['verdict'] as String,
      };
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  /// 选择服务商：官方自动带入名称/地址/协议，自定义保留名称并清空地址。
  void _selectProvider(ProviderDefinition provider) {
    setState(() {
      _selectedProviderId = provider.id;
      _selectedModel = null;
      _discoveredModels = [];
      if (provider.official) {
        _nameController.text = provider.displayName;
        _baseUrlController.text = provider.baseUrl;
        _selectedProtocol = provider.protocol;
      } else {
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = '自定义';
        }
        _baseUrlController.text = '';
        _selectedProtocol = ProtocolType.auto;
      }
    });
  }

  /// 发现模型流程：官方走 ProviderAdapter，自定义走协议扫描。选定模型后再持久化。
  Future<void> _discoverModels() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _toast('请先填写 API Key');
      return;
    }

    setState(() => _discovering = true);
    try {
      // 发现阶段只探测，不提前落库。失败或取消不会留下脏配置。
      final List<Map<String, dynamic>> models;
      if (_isOfficialProvider) {
        models = await _discovery.discoverProviderModels(
          _selectedProviderId!,
          apiKey,
        );
      } else {
        final name = _nameController.text.trim();
        if (name.isEmpty || _baseUrlController.text.trim().isEmpty) {
          setState(() => _discovering = false);
          _toast('请先填写名称和 API 地址');
          return;
        }
        final baseUrl = normalizeModelBaseUrl(_baseUrlController.text);
        models = await _discovery.discoverModelsWithCredentials(
          baseUrl: baseUrl,
          apiKey: apiKey,
          protocolType: _selectedProtocol,
        );
        _baseUrlController.text = baseUrl;
      }
      if (!mounted) return;

      setState(() {
        _discoveredModels = models;
        _discovering = false;
      });

      if (models.isEmpty) {
        _toast('未发现可用模型');
      } else {
        _toast('发现 ${models.length} 个模型，请选择一个');
      }
    } on ModelEndpointException catch (error) {
      if (!mounted) return;
      setState(() {
        _discovering = false;
        _discoveredModels = [];
      });
      _toast(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _discovering = false;
        _discoveredModels = [];
      });
      _toast('发现模型失败，请稍后重试');
    }
  }

  Future<void> _reselectModel() async {
    await _discoverModels();
  }

  /// 候选点击只更新页面草稿。能力检测已解耦，扫描附带的可选元数据不参与选择。
  void _selectModel(String modelId, Map<String, dynamic> _) {
    setState(() {
      _selectedModel = modelId;
      _modelNameController.text = modelId;
      _discoveredModels = [];
      if (_hasUnsavedModelChange) {
        _capabilityVerdicts = const {};
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    late final String baseUrl;
    final apiKey = _apiKeyController.text.trim();
    final selectedModel = _selectedModel?.trim();

    if (name.isEmpty ||
        _baseUrlController.text.trim().isEmpty ||
        apiKey.isEmpty) {
      _toast('请填写名称、地址和 Key');
      return;
    }
    if (selectedModel == null || selectedModel.isEmpty) {
      _toast('请先选择模型');
      return;
    }
    try {
      baseUrl = normalizeModelBaseUrl(_baseUrlController.text);
    } on ModelEndpointException catch (error) {
      _toast(error.message);
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'name': name,
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': selectedModel,
        'protocol_type': _selectedProtocol,
        'provider_id': _selectedProviderId ?? 'custom',
        'status': 'available',
      };

      if (_tempServiceId case final serviceId?) {
        await _modelServices.updateModelService(serviceId, data);
      } else {
        await _modelServices.createModelService(data);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败，请稍后重试');
    }
  }

  void _toast(String msg) {
    AsOneToast.show(context, msg);
  }

  Future<void> _showTestMenu() async {
    final serviceId = _tempServiceId;
    if (serviceId == null) {
      _toast('请先填写名称、API 地址和 Key 并保存配置');
      return;
    }
    if (_selectedModel == null || _selectedModel!.isEmpty) {
      _toast('请先选择模型再测试');
      return;
    }
    if (_hasUnsavedModelChange) {
      _toast('请先保存模型更改，再进行能力测试');
      return;
    }

    final testType = await AsOneBottomSheet.showActions<String>(
      context,
      title: '选择单项测试',
      actions: const [
        AsOneSheetAction(
          value: 'text_chat',
          label: '测试文本',
          icon: AsOneIconName.message,
        ),
        AsOneSheetAction(
          value: 'vision_input',
          label: '测试视觉',
          icon: AsOneIconName.image,
        ),
        AsOneSheetAction(
          value: 'audio_input',
          label: '测试音频',
          icon: AsOneIconName.microphone,
        ),
        AsOneSheetAction(
          value: 'client_tool_calling',
          label: '测试工具',
          icon: AsOneIconName.settings,
        ),
        AsOneSheetAction(
          value: 'streaming',
          label: '测试流式',
          icon: AsOneIconName.voice,
        ),
        AsOneSheetAction(
          value: 'structured_output',
          label: '测试结构化',
          icon: AsOneIconName.developer,
        ),
      ],
    );
    if (testType != null) await _runTest(serviceId, testType);
  }

  Future<void> _runTest(String serviceId, String capability) async {
    setState(() => _testing = true);
    try {
      final result = await _capabilities.quickTestCapability(
        serviceId,
        capability,
      );

      if (!mounted) return;
      final verdict = result['verdict'] as String? ?? 'unconfirmed';
      setState(() {
        _testing = false;
        _capabilityVerdicts = {..._capabilityVerdicts, capability: verdict};
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AsOneDialog(
          icon: asOneIconData(AsOneIconName.test),
          title: _getTestName(capability),
          content: Text(
            '结果：${_verdictLabel(verdict)}\n'
            '耗时：${result['elapsed_ms'] ?? 0}ms\n'
            '${result['detail'] ?? result['error'] ?? ''}',
          ),
          actions: [
            AsOneButton(label: '知道了', onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _testing = false);
      _toast('检测未完成，请稍后重试');
    }
  }

  String _getTestName(String type) => switch (type) {
    'text_chat' => '文本对话测试',
    'vision_input' => '图片理解测试',
    'audio_input' => '音频理解测试',
    'client_tool_calling' => '工具调用测试',
    'streaming' => '流式输出测试',
    'structured_output' => '结构化输出测试',
    _ => '能力测试',
  };

  String _verdictLabel(String verdict) => switch (verdict) {
    'supported' => '支持',
    'unsupported' => '不支持',
    _ => '未确认',
  };

  Widget _buildSelectedModelSection() {
    final selectedModel = _selectedModel;
    if (selectedModel == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AsOneSurface(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const AsOneIcon(
                  AsOneIconName.success,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已选择：$selectedModel',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                TextButton(
                  onPressed: _discovering ? null : _reselectModel,
                  child: const Text('重新选择'),
                ),
              ],
            ),
          ),
          if (_hasUnsavedModelChange) ...[
            const SizedBox(height: 8),
            const Text('模型已更换，保存后请重新检测能力', style: AsOneTheme.captionStyle),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      snapshot: () => [
        _nameController.text,
        _baseUrlController.text,
        _apiKeyController.text,
        _modelNameController.text,
        _selectedModel,
        _selectedProtocol,
        _selectedProviderId,
      ],
      ready: true,
      saving: _saving,
      onSave: _save,
      child: Scaffold(
        appBar: AsOneAppBar(
          title: _isEditing ? '编辑模型配置' : '添加模型配置',
          leading: AsOneIconButton(
            icon: AsOneIconName.close,
            tooltip: '关闭',
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            TextButton(
              onPressed: _saving || _selectedModel == null ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? '保存更改' : '保存'),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            children: [
              if (!_isEditing) ...[
                // 十家官方服务商 + 自定义，三列网格。
                const AsOneSectionTitle(
                  '选择模型服务',
                  subtitle: '选择 API Key 所属的服务。',
                ),
                AsOneSurface(
                  padding: const EdgeInsets.all(10),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ProviderRegistry.all.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.2,
                        ),
                    itemBuilder: (context, index) {
                      final provider = ProviderRegistry.all[index];
                      final selected = provider.id == _selectedProviderId;
                      return OutlinedButton(
                        onPressed: _testing
                            ? null
                            : () => _selectProvider(provider),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: selected
                              ? AsOneTheme.tileHighlight
                              : null,
                        ),
                        child: Text(
                          provider.displayName,
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (!_isOfficialProvider)
                TextFormField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'https://api.openai.com/v1',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入 API 地址';
                    }
                    return null;
                  },
                ),
              if (!_isOfficialProvider) const SizedBox(height: 16),
              TextFormField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  border: const OutlineInputBorder(),
                  suffixIcon: AsOneIconButton(
                    icon: _obscureKey
                        ? AsOneIconName.eyeOff
                        : AsOneIconName.eye,
                    tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                obscureText: _obscureKey,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 API Key';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (!_isOfficialProvider) ...[
                TextFormField(
                  controller: _modelNameController,
                  decoration: const InputDecoration(
                    labelText: '模型名称（可选）',
                    hintText: '可手动填写，不影响扫描模型列表',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              AsOneButton(
                label: _discovering ? '验证中…' : '扫描可用模型',
                icon: AsOneIconName.search,
                loading: _discovering,
                onPressed: _discovering ? null : _discoverModels,
                tone: AsOneButtonTone.secondary,
                expand: true,
              ),
              const SizedBox(height: 12),
              AsOneButton(
                label: _testing ? '测试中…' : '单项测试',
                icon: AsOneIconName.test,
                loading: _testing,
                onPressed: _testing ? null : _showTestMenu,
                tone: AsOneButtonTone.secondary,
                expand: true,
              ),
              if (_discoveredModels.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  '选择模型',
                  style: TextStyle(
                    fontSize: 14,
                    color: AsOneTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                AsOneSurface(
                  padding: EdgeInsets.zero,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _discoveredModels.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final model = _discoveredModels[index];
                      final modelId = model['id'] as String;
                      final isSelected = modelId == _selectedModel;
                      return ListTile(
                        title: Text(modelId),
                        subtitle: model['owned_by'] != null
                            ? Text(
                                '提供商: ${model['owned_by']}',
                                style: AsOneTheme.captionStyle,
                              )
                            : null,
                        trailing: isSelected
                            ? const AsOneIcon(
                                AsOneIconName.success,
                                color: AsOneTheme.accent,
                              )
                            : null,
                        selected: isSelected,
                        onTap: () => _selectModel(modelId, model),
                      );
                    },
                  ),
                ),
              ],
              _buildSelectedModelSection(),
            ],
          ),
        ),
      ),
    );
  }
}
