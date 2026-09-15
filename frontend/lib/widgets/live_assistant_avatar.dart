import 'dart:async';
import 'package:flutter/material.dart';
import '../local_core/core_repository.dart';
import '../models/assistant.dart';
import '../services/assistant_profile_events.dart';
import 'asone_avatar.dart';

/// 仅用于显示的助手资料投影，不参与模型身份或上下文。
class LiveAssistantAvatar extends StatefulWidget {
  const LiveAssistantAvatar({
    super.key,
    required this.assistantId,
    required this.size,
    required this.borderRadius,
    this.initialPath = '',
    this.initialName = '助手',
    this.loadAssistant,
    this.builder,
  });
  final String? assistantId;
  final double size;
  final double borderRadius;
  final String initialPath;
  final String initialName;
  final Future<Assistant?> Function(String id)? loadAssistant;
  final Widget Function(BuildContext context, Widget avatar, String name)?
  builder;
  @override
  State<LiveAssistantAvatar> createState() => _LiveAssistantAvatarState();
}

class _LiveAssistantAvatarState extends State<LiveAssistantAvatar>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _subscription;
  Assistant? _assistant;
  bool _loaded = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = AssistantProfileEvents.stream.listen((id) {
      if (id == widget.assistantId) unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(LiveAssistantAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      _assistant = null;
      _loaded = false;
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    final id = widget.assistantId;
    if (id == null || id.isEmpty) return;
    try {
      final assistant =
          await (widget.loadAssistant ?? CoreRepository().getAssistant)(id);
      if (!mounted || revision != _revision) return;
      setState(() {
        _assistant = assistant;
        _loaded = true;
      });
    } catch (_) {
      // 暂时读取失败保留首帧/最后成功资料，下次事件或恢复时重试。
    }
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _loaded ? _assistant?.name ?? '助手' : widget.initialName;
    final avatar = AsOneAvatar.assistant(
      imagePath: _loaded ? _assistant?.avatar ?? '' : widget.initialPath,
      name: name,
      size: widget.size,
      borderRadius: widget.borderRadius,
    );
    return widget.builder?.call(context, avatar, name) ?? avatar;
  }
}
