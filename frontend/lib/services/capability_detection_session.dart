import 'dart:async';

import 'package:dio/dio.dart';

import '../models/model_service.dart';
import 'model_capability_probe.dart';
import 'official_capability_denylist.dart';
import 'official_model_capability_catalog.dart';

/// 一次能力检测会话：贯穿一个 CancelToken，管理进度、超时、取消与临时结果。
///
/// 六项能力（文本/流式/视觉/音频/工具/结构化）。能力判定优先级：
/// 1. 官方模型列表元数据（discoveryCapabilities）
/// 2. 官方能力目录（OfficialModelCapabilityCatalog）
/// 3. 真实能力探针
///
/// 基础文本不可用时整场失败；其他单项失败保留为 unconfirmed，
/// 已完成的真实结果仍可保存和展示。
class CapabilityDetectionSession implements CapabilityDetectionSessionApi {
  CapabilityDetectionSession({
    required this.service,
    required this.providerId,
    this.discoveryCapabilities,
    ModelCapabilityProbe? probe,
    this.itemTimeout = const Duration(seconds: 30),
    this.visionTimeout = const Duration(seconds: 150),
    this.overallTimeout = const Duration(minutes: 5),
  }) : sessionId = DateTime.now().microsecondsSinceEpoch.toString(),
       _probe = probe ?? ModelCapabilityProbe() {
    _probe.cancelToken = _cancelToken;
  }

  final String sessionId;
  final ModelService service;
  final String providerId;

  /// 官方模型列表响应中的能力元数据（优先级最高）。
  final Map<String, ModelCapabilityVerdict>? discoveryCapabilities;

  final Duration itemTimeout;
  final Duration visionTimeout;
  final Duration overallTimeout;

  final CancelToken _cancelToken = CancelToken();
  final ModelCapabilityProbe _probe;
  final List<ModelCapabilityProbeResult> _results = [];

  bool _cancelled = false;
  bool _cancelledByUser = false;
  bool _completed = false;
  int _completedCount = 0;
  String? _failureMessage;
  String? _failureLabel;

  static const totalCapabilities = 5;

  @override
  void Function(int completed, int total, String label)? onProgress;

  @override
  bool get isCancelled => _cancelled;
  @override
  bool get isCancelledByUser => _cancelledByUser;
  @override
  bool get isCompleted => _completed;
  @override
  String? get failureMessage => _failureMessage;
  @override
  String? get failureLabel => _failureLabel;

  /// 访问已解析的探针（供 api_service 读取协议）。
  ModelCapabilityProbe get probe => _probe;

  @override
  String get resolvedProtocol => _probe.resolvedProtocol;

  /// 取消会话：标记并取消底层请求；迟到响应将被丢弃。
  @override
  void cancel() {
    if (_cancelled) return;
    _cancelledByUser = true;
    _cancelled = true;
    _cancelToken.cancel();
  }

  /// 执行六项检测。优先级：官方元数据 → 官方能力目录 → 真实探针。
  ///
  /// 返回五项检测结果；只有取消或基础文本不可用时返回 null。
  @override
  Future<List<ModelCapabilityProbeResult>?> run() async {
    if (_cancelled) return null;
    final overallDeadline = DateTime.now().add(overallTimeout);
    _results.clear();
    _completedCount = 0;

    // 优先级 1：官方模型列表元数据
    if (discoveryCapabilities != null && discoveryCapabilities!.isNotEmpty) {
      return _runWithDiscoveryMetadata(discoveryCapabilities!, overallDeadline);
    }

    // 优先级 2：官方能力目录
    final official = OfficialModelCapabilityCatalog.match(service);
    if (official != null) {
      return _runWithOfficialCatalog(official, overallDeadline);
    }

    // 优先级 3：真实探针（自定义/中转/未知模型）
    return _runWithRealProbes(overallDeadline);
  }

  /// 官方元数据路径：发一次流式请求验证可用性，已知能力取元数据，未知能力补探针。
  Future<List<ModelCapabilityProbeResult>?> _runWithDiscoveryMetadata(
    Map<String, ModelCapabilityVerdict> metadata,
    DateTime overallDeadline,
  ) async {
    if (_cancelled) return null;
    onProgress?.call(0, totalCapabilities, '验证模型可用性');

    // 发送一次流式请求验证 Key/地址/模型可用。
    final configTest = await _guardedRun(
      '验证模型可用性',
      () => _probe.testStreaming(service, maxTokens: 128),
      overallDeadline,
    );
    if (configTest == null) return null;
    if (!configTest.isSupported) return null;

    // 构造五项常用能力结果：元数据有的用元数据，没有的补探针。
    final results = <ModelCapabilityProbeResult>[];
    var completed = 1;

    // 文本和流式从配置测试中获取
    results.add(
      ModelCapabilityProbeResult(
        capability: 'text_chat',
        verdict: ModelCapabilityVerdict.supported,
        elapsedMs: configTest.elapsedMs,
        detail: '官方模型列表元数据：支持',
        protocol: configTest.protocol,
        requestWasSent: true,
        evidenceSource: 'official_metadata',
      ),
    );
    onProgress?.call(completed++, totalCapabilities, '文本对话');

    results.add(
      ModelCapabilityProbeResult(
        capability: 'streaming',
        verdict: ModelCapabilityVerdict.supported,
        elapsedMs: configTest.elapsedMs,
        detail: '官方模型列表元数据：支持',
        protocol: configTest.protocol,
        diagnosis: configTest.diagnosis,
        requestWasSent: true,
        evidenceSource: 'official_metadata',
      ),
    );
    onProgress?.call(completed++, totalCapabilities, '流式输出');

    // 视觉、工具、结构化：元数据有就用，没有就探针。
    for (final capability in [
      'vision_input',
      'client_tool_calling',
      'structured_output',
    ]) {
      if (_cancelled) return null;
      final label = _capabilityLabel(capability);

      if (metadata.containsKey(capability)) {
        // 用官方元数据
        final verdict = metadata[capability]!;
        results.add(
          ModelCapabilityProbeResult(
            capability: capability,
            verdict: verdict,
            elapsedMs: 0,
            detail: verdict == ModelCapabilityVerdict.supported
                ? '官方模型列表元数据：支持'
                : '官方模型列表元数据：不支持',
            requestWasSent: false,
            evidenceSource: 'official_metadata',
          ),
        );
      } else {
        // 补真实探针
        final result = await _runSingleProbe(
          capability,
          label,
          overallDeadline,
        );
        if (result == null) return null;
        results.add(result);
      }
      onProgress?.call(completed++, totalCapabilities, label);
    }

    _completed = true;
    _completedCount = totalCapabilities;
    return List.unmodifiable(results);
  }

  /// 单项真实探针（供元数据路径补探针用）。
  Future<ModelCapabilityProbeResult?> _runSingleProbe(
    String capability,
    String label,
    DateTime overallDeadline,
  ) async {
    // 先查 denylist
    final reason = OfficialCapabilityDenylist.reasonFor(
      providerId,
      service.model,
      capability,
    );
    if (reason != null) {
      return ModelCapabilityProbeResult(
        capability: capability,
        verdict: ModelCapabilityVerdict.unsupported,
        elapsedMs: 0,
        detail: '$reason：不支持',
        requestWasSent: false,
        evidenceSource: 'official_catalog',
      );
    }

    // 发真实探针
    return _guardedRun(
      label,
      () async {
        switch (capability) {
          case 'vision_input':
            return _probe.testVision(service);
          case 'audio_input':
            return _probe.testAudio(service);
          case 'client_tool_calling':
            return _probe.testTool(service);
          case 'structured_output':
            return _probe.testStructured(service);
          default:
            throw StateError('未知能力：$capability');
        }
      },
      overallDeadline,
      timeout: capability == 'vision_input' ? visionTimeout : null,
    );
  }

  /// 官方能力目录路径：发一次流式请求验证可用性，五项能力取官方结论。
  Future<List<ModelCapabilityProbeResult>?> _runWithOfficialCatalog(
    OfficialModelCapabilityProfile official,
    DateTime overallDeadline,
  ) async {
    if (_cancelled) return null;
    onProgress?.call(0, totalCapabilities, '验证模型可用性');

    // 发送一次流式请求验证 Key/地址/模型可用。
    final officialProtocolService = service.protocolType == 'auto'
        ? ModelService.fromJson({
            ...service.toJson(),
            'protocol_type': official.protocol,
          })
        : service;
    final configTest = await _guardedRun(
      '验证模型可用性',
      () => _probe.testStreaming(
        officialProtocolService,
        maxTokens: 128,
        payloadOverrides: official.availabilityPayloadOverrides,
      ),
      overallDeadline,
    );
    if (configTest == null) return null;

    // 配置测试失败（Key/模型不可用），整场检测失败。
    if (!configTest.isSupported) return null;

    // 五项能力直接取官方目录结论。
    final results = <ModelCapabilityProbeResult>[];
    var completed = 1;
    for (final entry in official.verdicts.entries.where(
      (entry) => entry.key != 'audio_input',
    )) {
      if (_cancelled) return null;
      final isStreaming = entry.key == 'streaming';
      final supported = entry.value == ModelCapabilityVerdict.supported;
      onProgress?.call(
        completed,
        totalCapabilities,
        _capabilityLabel(entry.key),
      );
      results.add(
        ModelCapabilityProbeResult(
          capability: entry.key,
          verdict: entry.value,
          elapsedMs: isStreaming ? configTest.elapsedMs : 0,
          detail: supported
              ? '${official.sourceDescription}：支持'
              : '${official.sourceDescription}：不支持',
          protocol: official.protocol,
          diagnosis: isStreaming ? configTest.diagnosis : null,
          requestWasSent: isStreaming ? configTest.requestSent : false,
          evidenceSource: 'official_catalog',
        ),
      );
      completed++;
    }

    _completed = true;
    _completedCount = totalCapabilities;
    return List.unmodifiable(results);
  }

  /// 真实探针路径：逐项发送请求，保留各项已确认和未确认结果。
  Future<List<ModelCapabilityProbeResult>?> _runWithRealProbes(
    DateTime overallDeadline,
  ) async {
    // 1. 合并文本 + 流式：一次流式请求同时验证两项。
    final streaming = await _guardedRun(
      '文本与流式',
      () => _probe.testStreaming(service),
      overallDeadline,
    );
    if (streaming == null) return null;

    _results.add(streaming);
    _completedCount++;

    if (streaming.isSupported) {
      _results.add(_textFromStreaming(streaming));
      _completedCount++;
    } else {
      final text = await _guardedRun(
        '文本',
        () => _probe.testText(service),
        overallDeadline,
      );
      if (text == null) return null;
      _results.add(text);
      _completedCount++;

      // 基础文本失败，整场检测失败。
      if (!text.isSupported) return null;
    }

    // 2. 视觉（denylist 直接 unsupported，否则真实探针）。
    final vision = await _deniedOr(
      'vision_input',
      '图片理解',
      () => _probe.testVision(service),
      overallDeadline,
      timeout: visionTimeout,
    );
    if (vision == null) return null;
    _results.add(vision);
    _completedCount++;

    // 3. 工具（denylist 直接 unsupported，否则真实探针）。
    final tool = await _deniedOr(
      'client_tool_calling',
      '工具调用',
      () => _probe.testTool(service),
      overallDeadline,
    );
    if (tool == null) return null;
    _results.add(tool);
    _completedCount++;

    // 4. 结构化输出（真实探针）。
    final structured = await _guardedRun(
      '结构化输出',
      () => _probe.testStructured(service),
      overallDeadline,
    );
    if (structured == null) return null;
    _results.add(structured);
    _completedCount++;

    _completed = true;
    return List.unmodifiable(_results);
  }

  Future<ModelCapabilityProbeResult?> _deniedOr(
    String capability,
    String label,
    Future<ModelCapabilityProbeResult> Function() action,
    DateTime overallDeadline, {
    Duration? timeout,
  }) async {
    final reason = OfficialCapabilityDenylist.reasonFor(
      providerId,
      service.model,
      capability,
    );
    if (reason != null) {
      if (_cancelled) return null;
      onProgress?.call(_completedCount, totalCapabilities, label);
      return ModelCapabilityProbeResult(
        capability: capability,
        verdict: ModelCapabilityVerdict.unsupported,
        elapsedMs: 0,
        detail: '$reason：不支持',
        requestWasSent: false,
        evidenceSource: 'official_catalog',
      );
    }
    return _guardedRun(label, action, overallDeadline, timeout: timeout);
  }

  Future<ModelCapabilityProbeResult?> _guardedRun(
    String label,
    Future<ModelCapabilityProbeResult> Function() action,
    DateTime overallDeadline, {
    Duration? timeout,
  }) async {
    if (_cancelled) return null;
    if (DateTime.now().isAfter(overallDeadline)) {
      _failureLabel = label;
      _failureMessage = '整体检测已超时';
      return _unconfirmedFor(label, '检测超时，请稍后单独重试', requestWasSent: false);
    }
    onProgress?.call(_completedCount, totalCapabilities, label);
    final watch = Stopwatch()..start();
    try {
      var result = await action().timeout(timeout ?? itemTimeout);
      if (!_cancelled && _shouldRetry(result)) {
        final remaining = overallDeadline.difference(DateTime.now());
        if (remaining > const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          final retryTimeout = remaining < (timeout ?? itemTimeout)
              ? remaining
              : (timeout ?? itemTimeout);
          result = await action().timeout(retryTimeout);
        }
      }
      watch.stop();
      if (_cancelled) return null;
      result = _withElapsedIfMissing(result, watch.elapsedMilliseconds);
      if (result.verdict == ModelCapabilityVerdict.unconfirmed) {
        _failureLabel = label;
        _failureMessage = result.detail.isEmpty ? '未能确认该项能力' : result.detail;
      }
      return result;
    } on TimeoutException {
      watch.stop();
      _failureLabel = label;
      _failureMessage = '该项检测已超时';
      return _unconfirmedFor(
        label,
        '检测超时，请稍后单独重试',
        elapsedMs: watch.elapsedMilliseconds,
      );
    } on DioException {
      watch.stop();
      _failureLabel = label;
      _failureMessage = '网络请求失败，请检查网络和接口地址';
      return _unconfirmedFor(
        label,
        '网络请求失败，请稍后单独重试',
        elapsedMs: watch.elapsedMilliseconds,
      );
    } catch (_) {
      watch.stop();
      _failureLabel = label;
      _failureMessage = '该项检测失败';
      return _unconfirmedFor(
        label,
        '检测失败，请稍后单独重试',
        elapsedMs: watch.elapsedMilliseconds,
      );
    }
  }

  bool _shouldRetry(ModelCapabilityProbeResult result) {
    if (result.verdict != ModelCapabilityVerdict.unconfirmed) return false;
    return const {
      'RATE_LIMITED',
      'SERVER_ERROR',
      'NETWORK_ERROR',
      'TIMEOUT',
    }.contains(result.diagnosis?.errorCode);
  }

  ModelCapabilityProbeResult _withElapsedIfMissing(
    ModelCapabilityProbeResult result,
    int elapsedMs,
  ) {
    if (!result.requestSent || result.elapsedMs > 0) return result;
    return ModelCapabilityProbeResult(
      capability: result.capability,
      verdict: result.verdict,
      elapsedMs: elapsedMs <= 0 ? 1 : elapsedMs,
      detail: result.detail,
      protocol: result.protocol,
      diagnosis: result.diagnosis,
      requestWasSent: result.requestWasSent,
      evidenceSource: result.evidenceSource,
    );
  }

  ModelCapabilityProbeResult _unconfirmedFor(
    String label,
    String detail, {
    int elapsedMs = 0,
    bool requestWasSent = true,
  }) => ModelCapabilityProbeResult(
    capability: switch (label) {
      '图片理解' => 'vision_input',
      '工具调用' => 'client_tool_calling',
      '结构化输出' => 'structured_output',
      '文本' => 'text_chat',
      _ => 'streaming',
    },
    verdict: ModelCapabilityVerdict.unconfirmed,
    elapsedMs: requestWasSent && elapsedMs <= 0 ? 1 : elapsedMs,
    detail: detail,
    protocol: _probe.resolvedProtocol,
    requestWasSent: requestWasSent,
    evidenceSource: 'real_probe',
  );

  String _capabilityLabel(String capability) => switch (capability) {
    'text_chat' => '文本对话',
    'streaming' => '流式输出',
    'vision_input' => '图片理解',
    'audio_input' => '音频理解',
    'client_tool_calling' => '工具调用',
    'structured_output' => '结构化输出',
    _ => capability,
  };

  ModelCapabilityProbeResult _textFromStreaming(
    ModelCapabilityProbeResult streaming,
  ) => ModelCapabilityProbeResult(
    capability: 'text_chat',
    verdict: ModelCapabilityVerdict.supported,
    elapsedMs: streaming.elapsedMs,
    detail: '已收到真实 SSE 文本增量，同时验证文本与流式',
    protocol: streaming.protocol,
    diagnosis: streaming.diagnosis,
    requestWasSent: streaming.requestSent,
    evidenceSource: 'real_probe',
  );
}
