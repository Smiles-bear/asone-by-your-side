import 'package:asone_contracts/asone_contracts.dart';
import 'local_core/group_chat/group_models.dart';
import 'pages/model_service_list_page.dart';
import 'package:flutter/material.dart';

import 'community_group_service.dart';
import 'public_core.dart';

/// 社区版 API 群聊入口。
///
/// 群成员由用户选中的模型服务组成；每次发送均在前台按成员顺序完成，且只
/// 发送本群基础文本历史。
class CommunityGroupPage extends StatefulWidget {
  const CommunityGroupPage({super.key, this.initialRoomId});

  final String? initialRoomId;

  @override
  State<CommunityGroupPage> createState() => _CommunityGroupPageState();
}

class _CommunityGroupPageState extends State<CommunityGroupPage> {
  List<GroupRoom> _rooms = const [];
  List<ModelService> _services = const [];
  GroupRoom? _room;
  List<GroupMessage> _messages = const [];
  Map<String, String> _assistantNames = const {};
  String? _targetAssistantId;
  String? _error;
  bool _loading = true;
  bool _sending = false;

  PublicCore? get _core {
    final core = OpenCoreBinding.instance;
    return core is PublicCore ? core : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final core = _core;
    if (core == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '群聊需要社区版本地核心。';
        });
      }
      return;
    }
    final results = await Future.wait<Object>([
      core.groupChat.listRooms(),
      OpenCoreBinding.instance.modelServices.getModelServices(),
    ]);
    if (!mounted) return;
    setState(() {
      _rooms = results[0] as List<GroupRoom>;
      _services = results[1] as List<ModelService>;
      _loading = false;
    });
    final initialRoomId = widget.initialRoomId;
    if (initialRoomId != null &&
        _rooms.any((room) => room.roomId == initialRoomId)) {
      await _openRoom(
        _rooms.firstWhere((room) => room.roomId == initialRoomId),
      );
    }
  }

  Future<void> _openModelServices() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ModelServiceListPage()),
    );
    await _load();
  }

  Future<void> _createRoom() async {
    final core = _core;
    if (core == null) return;
    final room = await Navigator.of(context).push<GroupRoom>(
      MaterialPageRoute(
        builder: (_) => _CommunityGroupCreatePage(
          services: _services,
          groupChat: core.groupChat,
        ),
      ),
    );
    if (room == null || !mounted) return;
    await _load();
    await _openRoom(room);
  }

  Future<void> _openRoom(GroupRoom room) async {
    final core = _core;
    if (core == null) return;
    setState(() {
      _room = room;
      _messages = const [];
      _assistantNames = const {};
      _targetAssistantId = null;
      _error = null;
      _loading = true;
    });
    try {
      final participants = await core.groupChat.participantsForRoom(
        room.roomId,
      );
      final names = <String, String>{};
      for (final participant in participants) {
        final assistant = await OpenCoreBinding.instance.assistants
            .getAssistant(participant.assistantId);
        names[participant.assistantId] = assistant?.name ?? '未知成员';
      }
      final messages = await core.groupChat.messagesForRoom(room.roomId);
      if (!mounted || _room?.roomId != room.roomId) return;
      setState(() {
        _messages = messages;
        _assistantNames = names;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '群聊记录加载失败，请稍后重试。';
        });
      }
    }
  }

  Future<void> _send(String value) async {
    final room = _room;
    final core = _core;
    final text = value.trim();
    if (room == null || core == null || text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final target = _targetAssistantId;
      final messages = target == null
          ? await core.groupChat.sendUserMessage(
              roomId: room.roomId,
              content: text,
            )
          : await core.groupChat.sendUserMessageToAssistant(
              roomId: room.roomId,
              assistantId: target,
              content: text,
            );
      if (mounted) setState(() => _messages = messages);
    } catch (_) {
      if (mounted) setState(() => _error = '发送失败，请检查模型服务配置后重试。');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _regenerate(GroupMessage message) async {
    final core = _core;
    if (core == null || _sending || message.speakerType != 'assistant') return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final messages = await core.groupChat.regenerateAssistantMessage(
        message.messageId,
      );
      if (mounted) setState(() => _messages = messages);
    } catch (_) {
      if (mounted) setState(() => _error = '重新生成失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) return _buildRoomList(context);
    return _buildRoomDetail(context);
  }

  Widget _buildRoomList(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('API 群聊'),
      actions: [
        IconButton(
          key: const Key('community-group-model-services'),
          tooltip: '模型服务',
          onPressed: _openModelServices,
          icon: const Icon(Icons.tune_outlined),
        ),
        IconButton(
          key: const Key('community-group-create'),
          tooltip: '新建群聊',
          onPressed: _services.length >= 2 ? _createRoom : null,
          icon: const Icon(Icons.group_add_outlined),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _rooms.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('选择两个或以上模型服务，创建一个 API 群聊。'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('community-group-empty-action'),
                    onPressed: _services.length >= 2
                        ? _createRoom
                        : _openModelServices,
                    icon: Icon(
                      _services.length >= 2 ? Icons.group_add : Icons.tune,
                    ),
                    label: Text(_services.length >= 2 ? '新建群聊' : '先配置两个模型服务'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              itemCount: _rooms.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return ListTile(
                  key: ValueKey('community-group-room-${room.roomId}'),
                  leading: const CircleAvatar(child: Icon(Icons.groups)),
                  title: Text(room.title),
                  subtitle: const Text('仅基础文本 · 成员按顺序回复'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openRoom(room),
                );
              },
            ),
          ),
  );

  Widget _buildRoomDetail(BuildContext context) {
    final room = _room!;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            setState(() {
              _room = null;
              _messages = const [];
            });
            _load();
          },
        ),
        title: Text(room.title),
        actions: [
          PopupMenuButton<String?>(
            key: const Key('community-group-target-selector'),
            tooltip: '选择发言成员',
            initialValue: _targetAssistantId,
            onSelected: (assistantId) => setState(
              () => _targetAssistantId = assistantId,
            ),
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('所有成员依次回复'),
              ),
              for (final entry in _assistantNames.entries)
                PopupMenuItem<String?>(
                  value: entry.key,
                  child: Text('点名：${entry.value}'),
                ),
            ],
            icon: const Icon(Icons.alternate_email_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              _targetAssistantId == null
                  ? '成员按顺序使用各自 API 回复；不使用记忆、工具、语音或后台任务。'
                  : '本条仅点名 ${_assistantNames[_targetAssistantId] ?? '成员'} 回复；不使用记忆、工具、语音或后台任务。',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(child: Text('向群聊发送第一条消息吧'))
                : ListView.builder(
                    key: const Key('community-group-messages'),
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.speakerType == 'user';
                      final name = isUser
                          ? '你'
                          : _assistantNames[message.speakerAssistantId] ?? '成员';
                      final text =
                          message.content.isEmpty &&
                              message.answerStatus == 'failed'
                          ? message.failureHint ?? '回复失败'
                          : message.content;
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(text),
                              if (!isUser &&
                                  message.answerStatus == 'completed')
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: ValueKey(
                                      'community-group-regenerate-${message.messageId}',
                                    ),
                                    onPressed: _sending
                                        ? null
                                        : () => _regenerate(message),
                                    child: const Text('重新生成后续回复'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _GroupComposer(enabled: !_sending, onSend: _send),
        ],
      ),
    );
  }
}

class _CommunityGroupCreatePage extends StatefulWidget {
  const _CommunityGroupCreatePage({
    required this.services,
    required this.groupChat,
  });

  final List<ModelService> services;
  final CommunityGroupService groupChat;

  @override
  State<_CommunityGroupCreatePage> createState() =>
      _CommunityGroupCreatePageState();
}

class _CommunityGroupCreatePageState extends State<_CommunityGroupCreatePage> {
  final _title = TextEditingController();
  final Set<String> _selected = <String>{};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selected.length < 2) {
      setState(() => _error = '请至少选择两个模型服务。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final room = await widget.groupChat.createRoom(
        title: _title.text,
        serviceIds: _selected.toList(growable: false),
      );
      if (mounted) Navigator.of(context).pop(room);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新建 API 群聊')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: '群聊名称（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('选择模型服务（至少两个，选择顺序即回复顺序）'),
        const SizedBox(height: 8),
        for (final service in widget.services)
          CheckboxListTile(
            value: _selected.contains(service.id),
            title: Text(service.name),
            subtitle: Text(service.model),
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(service.id);
                    } else {
                      _selected.remove(service.id);
                    }
                  }),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('community-group-create-confirm'),
          onPressed: _saving ? null : _create,
          icon: const Icon(Icons.group_add),
          label: Text(_saving ? '创建中…' : '创建群聊'),
        ),
      ],
    ),
  );
}

class _GroupComposer extends StatefulWidget {
  const _GroupComposer({required this.enabled, required this.onSend});

  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  State<_GroupComposer> createState() => _GroupComposerState();
}

class _GroupComposerState extends State<_GroupComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('community-group-composer'),
              controller: _controller,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: '发送消息给群聊',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const Key('community-group-send'),
            onPressed: widget.enabled ? _send : null,
            tooltip: '发送',
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    ),
  );
}
