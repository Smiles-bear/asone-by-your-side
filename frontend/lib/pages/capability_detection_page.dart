import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart'
    show
        CapabilityDetectionApi,
        CapabilityDetectionSessionApi,
        ModelCapabilityProbeResult,
        ModelCapabilityVerdict,
        OpenCoreBinding;
import 'package:flutter/material.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_button.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_surface.dart';

/// 能力检测进度页（独立全屏，可取消、可返回）。
///
/// 返回 `true` 表示检测完成并提交了完整快照；`false` 表示取消或失败。
class CapabilityDetectionPage extends StatefulWidget {
  final String? serviceId;
  final Map<String, dynamic>? configData;
  final Map<String, String>? discoveryCapabilities;
  final CapabilityDetectionApi? capabilityDetection;

  const CapabilityDetectionPage({
    super.key,
    this.serviceId,
    this.configData,
    this.discoveryCapabilities,
    this.capabilityDetection,
  }) : assert(
         serviceId != null || configData != null,
         '必须提供 serviceId 或 configData 之一',
       );

  @override
  State<CapabilityDetectionPage> createState() =>
      _CapabilityDetectionPageState();
}

class _CapabilityDetectionPageState extends State<CapabilityDetectionPage> {
  static const _order = [
    'text_chat',
    'vision_input',
    'client_tool_calling',
    'streaming',
    'structured_output',
  ];

  late final CapabilityDetectionApi _api =
      widget.capabilityDetection ??
      OpenCoreBinding.instance.capabilityDetection;
  CapabilityDetectionSessionApi? _session;

  int _completed = 0;
  int _total = 5;
  String _currentLabel = '准备中';
  bool _finished = false;
  List<ModelCapabilityProbeResult>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final session = await _api.createCapabilityDetectionSession(
        serviceId: widget.serviceId,
        configData: widget.configData,
        discoveryCapabilities: widget.discoveryCapabilities,
      );
      _session = session;
      session.onProgress = (completed, total, label) {
        if (!mounted) return;
        setState(() {
          _completed = completed;
          _total = total;
          _currentLabel = label;
        });
      };

      final results = await session.run();
      if (!mounted) return;

      if (results != null) {
        // 检测成功，保存配置和能力快照
        final saved = await _api.saveCapabilitySnapshot(
          serviceId: widget.serviceId,
          configData: widget.configData,
          results: results,
          resolvedProtocol: session.resolvedProtocol,
        );
        if (!mounted) return;
        if (saved) {
          setState(() {
            _finished = true;
            _results = results;
          });
        } else {
          setState(() {
            _finished = true;
            _error = '保存配置失败，请稍后重试';
          });
        }
      } else if (session.isCancelledByUser) {
        if (mounted) Navigator.pop(context, false);
      } else {
        setState(() {
          _finished = true;
          final step = session.failureLabel;
          final reason = _safeFailure(session.failureMessage ?? '未能形成可靠结论');
          _error = step == null ? '能力检测未完成：$reason' : '“$step”检测未完成：$reason';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finished = true;
        _error = '检测未完成，请检查配置和网络后重试';
      });
    }
  }

  void _cancel() {
    _session?.cancel();
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_finished) _cancel();
      },
      child: Scaffold(
        appBar: AsOneAppBar(
          title: '检测模型能力',
          leading: AsOneIconButton(
            icon: AsOneIconName.close,
            tooltip: '取消检测',
            onPressed: _cancel,
          ),
        ),
        body: _finished ? _buildResult() : _buildProgress(),
      ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            '正在检测模型能力 $_completed/$_total',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text('当前：$_currentLabel', style: AsOneTheme.secondaryStyle),
          const SizedBox(height: 32),
          LinearProgressIndicator(
            value: _total == 0 ? null : _completed / _total,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 48),
          AsOneButton(
            label: '取消',
            icon: AsOneIconName.close,
            onPressed: _cancel,
            tone: AsOneButtonTone.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AsOneIcon(
                AsOneIconName.warning,
                size: 56,
                color: AsOneTheme.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              AsOneButton(
                label: '重新检测',
                icon: AsOneIconName.refresh,
                onPressed: () {
                  setState(() {
                    _finished = false;
                    _error = null;
                    _completed = 0;
                    _results = null;
                  });
                  unawaited(_start());
                },
              ),
              const SizedBox(height: 12),
              AsOneButton(
                label: '返回配置',
                onPressed: () => Navigator.pop(context, false),
                tone: AsOneButtonTone.ghost,
              ),
            ],
          ),
        ),
      );
    }

    final results = _results ?? const [];
    final byCap = {for (final r in results) r.capability: r};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          results.any(
                (item) => item.verdict == ModelCapabilityVerdict.unconfirmed,
              )
              ? '检测完成，仍有能力待确认'
              : '检测完成',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        for (final capability in _order)
          if (byCap[capability] != null)
            _capabilityTile(capability, byCap[capability]!),
        const SizedBox(height: 24),
        AsOneButton(
          label: '完成',
          icon: AsOneIconName.check,
          onPressed: () => Navigator.pop(context, true),
          expand: true,
        ),
      ],
    );
  }

  Widget _capabilityTile(String capability, ModelCapabilityProbeResult result) {
    final supported = result.verdict == ModelCapabilityVerdict.supported;
    final unconfirmed = result.verdict == ModelCapabilityVerdict.unconfirmed;
    final label = _capabilityLabel(capability);
    final source =
        result.evidenceSource == 'official_catalog' ||
            result.evidenceSource == 'official_metadata'
        ? '官方资料'
        : result.requestSent
        ? '真实调用 ${result.elapsedMs}ms'
        : '未发起请求';
    return AsOneSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AsOneIcon(
            supported ? AsOneIconName.success : AsOneIconName.warning,
            color: supported ? AsOneTheme.accent : AsOneTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AsOneTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  capability == 'structured_output' && result.isSupported
                      ? '$source · ${result.detail}'
                      : source,
                  style: AsOneTheme.captionStyle,
                ),
              ],
            ),
          ),
          Text(
            supported ? '支持' : (unconfirmed ? '未确认' : '不支持'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: supported ? AsOneTheme.accent : AsOneTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _capabilityLabel(String capability) => switch (capability) {
    'text_chat' => '文本对话',
    'streaming' => '流式输出',
    'vision_input' => '图片理解',
    'audio_input' => '音频理解',
    'client_tool_calling' => '工具调用',
    'structured_output' => '结构化输出',
    _ => capability,
  };

  String _safeFailure(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('overdue') ||
        lower.contains('payment') ||
        lower.contains('account is in good standing') ||
        lower.contains('access denied')) {
      return '模型服务账户当前不可用，请检查额度或账号状态';
    }
    if (lower.contains('auth') || lower.contains('api key')) {
      return '认证失败，请检查 API Key';
    }
    if (lower.contains('timeout') || lower.contains('超时')) {
      return '请求超时，请检查网络后重试';
    }
    return value.length > 120 ? '模型服务返回异常，请检查配置后重试' : value;
  }
}
