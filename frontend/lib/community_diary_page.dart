import 'package:asone_contracts/asone_contracts.dart';
import 'package:flutter/material.dart';

import 'public_core.dart';

/// 社区版手动日记入口，只提供近期对话降级生成。
class CommunityDiaryPage extends StatefulWidget {
  const CommunityDiaryPage({super.key});

  @override
  State<CommunityDiaryPage> createState() => _CommunityDiaryPageState();
}

class _CommunityDiaryPageState extends State<CommunityDiaryPage> {
  List<Conversation> _conversations = const [];
  String? _error;
  bool _loading = true;
  String? _generating;

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
      setState(() {
        _loading = false;
        _error = '日记功能需要社区版本地核心。';
      });
      return;
    }
    final conversations = await core.conversations.getConversations();
    if (!mounted) return;
    setState(() {
      _conversations = conversations;
      _loading = false;
    });
  }

  Future<void> _generate(Conversation conversation) async {
    final core = _core;
    if (core == null || _generating != null) return;
    setState(() {
      _generating = conversation.id;
      _error = null;
    });
    try {
      final entry = await core.diary.generate(conversationId: conversation.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(entry.title),
          content: SingleChildScrollView(child: Text(entry.content)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _generating = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('对话日记')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('社区版日记仅根据该对话最近的基础文本生成，不使用长期记忆或后台自动任务。'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Expanded(
                child: _conversations.isEmpty
                    ? const Center(child: Text('暂无可生成日记的 API 对话'))
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = _conversations[index];
                          final generating = _generating == conversation.id;
                          return ListTile(
                            title: Text(conversation.title),
                            subtitle: const Text('仅近期对话文本'),
                            trailing: FilledButton(
                              onPressed: _generating == null
                                  ? () => _generate(conversation)
                                  : null,
                              child: Text(generating ? '生成中…' : '生成日记'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
  );
}
