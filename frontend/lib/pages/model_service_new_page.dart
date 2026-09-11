import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart'
    show ModelDiscoveryApi, OpenCoreBinding;
import 'package:flutter/material.dart';

import '../services/model_endpoint.dart';
import '../services/provider_definition.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_button.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_surface.dart';
import 'capability_detection_page.dart';

/// 新建模型配置页：官方预填地址可改，自定义为空。
/// 只有"检测能力""扫描可用模型"两个按钮。
/// 检测成功后点"完成"才保存配置并返回。
class ModelServiceNewPage extends StatefulWidget {
  final ProviderDefinition provider;
  final ModelDiscoveryApi? discovery;

  const ModelServiceNewPage({
    super.key,
    required this.provider,
    this.discovery,
  });

  @override
  State<ModelServiceNewPage> createState() => _ModelServiceNewPageState();
}

class _ModelServiceNewPageState extends State<ModelServiceNewPage> {
  late final ModelDiscoveryApi _api =
      widget.discovery ?? OpenCoreBinding.instance.modelDiscovery;
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelNameController = TextEditingController();

  bool _discovering = false;
  bool _obscureKey = true;
  List<Map<String, dynamic>> _discoveredModels = [];
  Map<String, String>? _selectedModelCapabilities;

  bool get _isOfficial => widget.provider.official;

  @override
  void initState() {
    super.initState();
    if (_isOfficial) {
      _baseUrlController.text = widget.provider.baseUrl;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  /// 扫描可用模型
  Future<void> _scanModels() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _toast('请先填写 API Key');
      return;
    }

    if (!_isOfficial) {
      final baseUrl = _baseUrlController.text.trim();
      if (baseUrl.isEmpty) {
        _toast('请先填写 API 地址');
        return;
      }
    }

    setState(() {
      _discovering = true;
      _discoveredModels = [];
    });

    try {
      final List<Map<String, dynamic>> models;
      if (_isOfficial) {
        models = await _api.discoverProviderModels(widget.provider.id, apiKey);
      } else {
        final baseUrl = normalizeModelBaseUrl(_baseUrlController.text);
        models = await _api.discoverModelsWithCredentials(
          baseUrl: baseUrl,
          apiKey: apiKey,
          protocolType: 'auto',
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
      }
    } on ModelEndpointException catch (error) {
      if (!mounted) return;
      setState(() => _discovering = false);
      _toast(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _discovering = false);
      _toast('扫描模型失败，请稍后重试');
    }
  }

  /// 选择模型后自动填入并收起列表
  void _selectModelFromList(String modelId, Map<String, dynamic> modelData) {
    final capabilities = modelData['capabilities'] as Map<String, dynamic>?;
    setState(() {
      _modelNameController.text = modelId;
      _discoveredModels = [];
      _selectedModelCapabilities = capabilities?.map(
        (k, v) => MapEntry(k, v.toString()),
      );
    });
  }

  /// 检测能力：内存传递配置，检测成功后才保存
  Future<void> _detectCapabilities() async {
    if (!_formKey.currentState!.validate()) return;

    final apiKey = _apiKeyController.text.trim();
    final modelName = _modelNameController.text.trim();

    if (apiKey.isEmpty) {
      _toast('请先填写 API Key');
      return;
    }

    if (modelName.isEmpty) {
      _toast('请先填写或选择模型名称');
      return;
    }

    if (!_isOfficial && _baseUrlController.text.trim().isEmpty) {
      _toast('请先填写 API 地址');
      return;
    }

    // 准备配置数据（内存中，不写数据库）
    try {
      final baseUrl = _isOfficial
          ? widget.provider.baseUrl
          : normalizeModelBaseUrl(_baseUrlController.text);

      final configData = {
        'name': _isOfficial ? widget.provider.displayName : '自定义',
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': modelName,
        'protocol_type': _isOfficial ? widget.provider.protocol : 'auto',
        'provider_id': widget.provider.id,
        'status': 'available',
      };

      if (!mounted) return;

      // 跳转检测页，传递配置数据和官方元数据
      final detected = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => CapabilityDetectionPage(
            configData: configData,
            discoveryCapabilities: _selectedModelCapabilities,
          ),
        ),
      );

      if (!mounted) return;

      if (detected == true) {
        // 检测成功且用户点"完成"，配置和能力已在检测页保存，返回上一页刷新列表
        Navigator.pop(context, true);
      }
      // 检测失败或取消，数据库无新记录，停留在当前页可重试
    } on ModelEndpointException catch (error) {
      if (!mounted) return;
      _toast(error.message);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('未发现该模型') ||
          e.toString().contains('MODEL_NOT_FOUND')) {
        _toast('未发现该模型，请检查名称后重试');
      } else {
        _toast('配置失败，请稍后重试');
      }
    }
  }

  void _toast(String msg) {
    AsOneToast.show(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final modelName = _modelNameController.text.trim();
    final canDetect = modelName.isNotEmpty;

    return Scaffold(
      appBar: AsOneAppBar(
        title: '配置 ${widget.provider.displayName}',
        leading: AsOneIconButton(
          icon: AsOneIconName.close,
          tooltip: '关闭',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 16,
            bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            const AsOneSectionTitle('连接信息', subtitle: '密钥仅保存在当前设备，用于连接所选模型服务。'),
            AsOneSurface(
              child: Column(
                children: [
                  TextFormField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      labelText: 'API 地址',
                      hintText: _isOfficial
                          ? widget.provider.baseUrl
                          : 'https://api.example.com/v1',
                      enabled:
                          !_isOfficial || _baseUrlController.text.isNotEmpty,
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入 API 地址'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                      suffixIcon: AsOneIconButton(
                        icon: _obscureKey
                            ? AsOneIconName.eyeOff
                            : AsOneIconName.eye,
                        tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                    obscureText: _obscureKey,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入 API Key'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _modelNameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '模型名称（可选）',
                      hintText: '可选择或手动填写',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            AsOneButton(
              label: '检测能力',
              icon: AsOneIconName.test,
              onPressed: canDetect ? _detectCapabilities : null,
              expand: true,
            ),
            const SizedBox(height: 12),
            AsOneButton(
              label: _discovering ? '扫描中…' : '扫描可用模型',
              icon: AsOneIconName.search,
              loading: _discovering,
              onPressed: _discovering ? null : _scanModels,
              tone: AsOneButtonTone.secondary,
              expand: true,
            ),

            // 模型列表（扫描后展开）
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
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _discoveredModels.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final model = _discoveredModels[index];
                    final modelId = model['id'] as String;
                    return ListTile(
                      title: Text(modelId),
                      onTap: () => _selectModelFromList(modelId, model),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
