import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/assistant.dart';
import '../models/sticky_note_item.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_line_asset_icon.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/anchored_popup_menu.dart';
import 'sticky_note_editor_page.dart';
import 'sticky_note_history_page.dart';

class StickyNoteWallPage extends StatefulWidget {
  const StickyNoteWallPage({super.key, this.stickyNotes, this.coreRepository});

  final StickyNoteRepositoryApi? stickyNotes;
  final AssistantRepositoryApi? coreRepository;

  @override
  State<StickyNoteWallPage> createState() => _StickyNoteWallPageState();
}

class _StickyNoteWallPageState extends State<StickyNoteWallPage> {
  late final StickyNoteRepositoryApi _repository =
      widget.stickyNotes ?? OpenCoreBinding.instance.stickyNotes;
  late final AssistantRepositoryApi _core =
      widget.coreRepository ?? OpenCoreBinding.instance.assistants;
  final ScrollController _scrollController = ScrollController();
  List<StickyNoteDetail> _wallDetails = const [];
  StickyNoteDetail? _displayed;
  Map<String, Assistant> _assistants = const {};
  bool _loading = true;
  bool _heroDropInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final readThrough = DateTime.now().toUtc();
    try {
      final notes = await _repository.listOpen();
      final assistants = await _core.getAssistants();
      final details = (await Future.wait(
        notes.map((note) => _repository.loadDetail(note.noteId)),
      )).whereType<StickyNoteDetail>().toList(growable: false);
      if (!mounted) return;
      setState(() {
        _displayed = details.where((item) => item.note.displayed).firstOrNull;
        _wallDetails = details
            .where((item) => !item.note.displayed)
            .toList(growable: false);
        _assistants = {
          for (final assistant in assistants) assistant.id: assistant,
        };
        _loading = false;
      });
      if (widget.stickyNotes == null) {
        await OpenCoreBinding.instance.featureUnread.markRead(
          FeatureUnreadKind.stickyNote,
          through: readThrough,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('加载失败，请稍后重试');
    }
  }

  Future<void> _openEditor([StickyNoteDetail? detail]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StickyNoteEditorPage(
          repository: _repository,
          detail: detail,
          assistants: _assistants,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StickyNoteHistoryPage(
          repository: _repository,
          assistants: _assistants,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(StickyNoteItem note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除小纸条'),
        content: const Text('删除后无法恢复，确定删除这张纸条吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AsOneTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!await _repository.hardDelete(note.noteId)) {
      _message('纸条已不存在');
    }
    await _load();
  }

  Future<void> _action(StickyNoteDetail detail, String action) async {
    final note = detail.note;
    try {
      switch (action) {
        case 'edit':
          await _openEditor(detail);
          return;
        case 'complete':
          await _repository.setCompletion(note.noteId, 'completed');
          break;
        case 'cancel':
          await _repository.setCompletion(note.noteId, 'cancelled');
          break;
        case 'delete':
          await _delete(note);
          return;
      }
      await _load();
    } catch (_) {
      _message('操作失败，请稍后重试');
    }
  }

  Future<void> _togglePin(StickyNoteDetail detail) async {
    try {
      final note = detail.note;
      if (!await _repository.setPinned(note.noteId, !note.pinned)) {
        _message('纸条已不存在');
      }
      await _load();
    } catch (_) {
      _message('操作失败，请稍后重试');
    }
  }

  Future<void> _putOnHero(String noteId) async {
    _heroDropInProgress = true;
    await HapticFeedback.mediumImpact();
    try {
      if (!await _repository.setDisplayed(noteId)) {
        _message('纸条已不存在');
      }
      await _load();
    } catch (_) {
      _message('暂时无法展示这张纸条');
    } finally {
      _heroDropInProgress = false;
    }
  }

  Future<void> _returnFromHero(String noteId) async {
    await HapticFeedback.mediumImpact();
    try {
      if (!await _repository.clearDisplayed(noteId)) {
        _message('纸条已不在展示位');
      }
      await _load();
    } catch (_) {
      _message('暂时无法放回纸条');
    }
  }

  Future<void> _persistOrder(
    ReorderedListFunction<StickyNoteDetail> reorderedList,
  ) async {
    if (_heroDropInProgress) return;
    late final List<StickyNoteDetail> reordered;
    try {
      reordered = reorderedList(_wallDetails).cast<StickyNoteDetail>();
    } on RangeError {
      await HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() => _wallDetails = List<StickyNoteDetail>.of(_wallDetails));
      }
      _message('纸条已回到原位');
      return;
    }
    final pinnedCount = _wallDetails.where((item) => item.note.pinned).length;
    final validBoundary =
        reordered.take(pinnedCount).every((item) => item.note.pinned) &&
        reordered.skip(pinnedCount).every((item) => !item.note.pinned);
    if (!validBoundary) {
      await HapticFeedback.heavyImpact();
      _message('置顶纸条只能在置顶区域内排序');
      return;
    }
    setState(() => _wallDetails = reordered);
    try {
      await _repository.reorderGroup(
        reordered
            .where((detail) => detail.note.pinned)
            .map((detail) => detail.note.noteId)
            .toList(growable: false),
        pinned: true,
      );
      await _repository.reorderGroup(
        reordered
            .where((detail) => !detail.note.pinned)
            .map((detail) => detail.note.noteId)
            .toList(growable: false),
        pinned: false,
      );
    } catch (_) {
      _message('纸条顺序已变化，请重试');
      await _load();
    }
  }

  void _message(String text) {
    if (!mounted) return;
    AsOneToast.show(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsOneTheme.pageBg,
      appBar: AsOneAppBar(
        title: '小纸条',
        leading: AsOneIconButton(
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
          icon: AsOneIconName.back,
        ),
        actions: [
          AsOneIconButton(
            tooltip: '历史纸条',
            onPressed: _openHistory,
            icon: AsOneIconName.clock,
          ),
          AsOneIconButton(
            tooltip: '新建纸条',
            onPressed: _openEditor,
            icon: AsOneIconName.edit,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _StickyNoteHero(
                      detail: _displayed,
                      onOpen: _displayed == null
                          ? null
                          : () => _openEditor(_displayed),
                      onAccept: _putOnHero,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 34),
                    sliver: SliverToBoxAdapter(child: _buildWall()),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWall() {
    final displayedId = _displayed?.note.noteId;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data == displayedId,
      onAcceptWithDetails: (details) => _returnFromHero(details.data),
      builder: (context, candidates, rejected) {
        if (_wallDetails.isEmpty) {
          return SizedBox(
            height: 350,
            child: Center(
              child: Text(
                _displayed == null ? '还没有小纸条' : '长按上方纸条可放回这里',
                style: const TextStyle(color: Color(0xFF77706B), fontSize: 13),
              ),
            ),
          );
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: candidates.isEmpty
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0x0FEC9B83),
                ),
          child: _buildGrid(_wallDetails),
        );
      },
    );
  }

  Widget _buildGrid(List<StickyNoteDetail> group) {
    final mediaQuery = MediaQuery.of(context);
    final oneColumn =
        mediaQuery.size.width < 340 || mediaQuery.textScaler.scale(12) > 15;
    final children = group
        .map(
          (detail) => CustomDraggable(
            key: ValueKey(detail.note.noteId),
            data: detail.note.noteId,
            child: _StickyNoteCard(
              detail: detail,
              assistants: _assistants,
              onOpen: () => _openEditor(detail),
              onPin: () => _togglePin(detail),
              onChecklist: (item, checked) async {
                try {
                  await _repository.setChecklistItemChecked(
                    item.itemId,
                    checked,
                  );
                  await _load();
                } catch (_) {
                  _message('操作失败，请稍后重试');
                }
              },
              onAction: (action) => _action(detail, action),
            ),
          ),
        )
        .toList(growable: false);
    return ReorderableBuilder<StickyNoteDetail>(
      longPressDelay: const Duration(milliseconds: 360),
      enableScrollingWhileDragging: true,
      automaticScrollExtent: 92,
      feedbackScaleFactor: 1.035,
      dragChildBoxDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      onDragStarted: (_) => HapticFeedback.selectionClick(),
      onReorder: _persistOrder,
      builder: (reorderableChildren) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: oneColumn ? 1 : 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          mainAxisExtent: oneColumn ? 142 : 148,
        ),
        children: reorderableChildren,
      ),
      children: children,
    );
  }
}

class _StickyNoteHero extends StatelessWidget {
  const _StickyNoteHero({
    required this.detail,
    required this.onOpen,
    required this.onAccept,
  });

  final StickyNoteDetail? detail;
  final VoidCallback? onOpen;
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final hero = DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != detail?.note.noteId,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) => AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: candidates.isEmpty ? 1 : 1.025,
        child: GestureDetector(
          onTap: onOpen,
          child: SizedBox(
            width: 340,
            height: 213,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/sticky/note_paper_transparent.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                if (detail != null)
                  Positioned(
                    left: 92,
                    top: 58,
                    width: 174,
                    height: 106,
                    child: LongPressDraggable<String>(
                      data: detail!.note.noteId,
                      delay: const Duration(milliseconds: 360),
                      onDragStarted: HapticFeedback.selectionClick,
                      feedback: Material(
                        color: Colors.transparent,
                        child: _StickyHeroDragPreview(detail: detail!),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.25,
                        child: _HeroNoteContent(detail: detail!),
                      ),
                      child: _HeroNoteContent(detail: detail!),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Center(child: hero),
    );
  }
}

class _StickyHeroDragPreview extends StatelessWidget {
  const _StickyHeroDragPreview({required this.detail});

  final StickyNoteDetail detail;

  @override
  Widget build(BuildContext context) {
    final note = detail.note;
    final colorIndex = note.paletteKey % _StickyNoteCard.palette.length;
    return SizedBox(
      width: 160,
      height: 138,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _StickyNoteCard.palette[colorIndex],
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 22, 14, 12),
                child: _HeroNoteContent(detail: detail),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 57,
            child: SvgPicture.asset(
              note.tapeStyle == 0
                  ? 'assets/sticky/tape_a.svg'
                  : 'assets/sticky/tape_c.svg',
              width: 46,
              height: 13,
              colorFilter: ColorFilter.mode(
                _StickyNoteCard.tapeColors[colorIndex],
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroNoteContent extends StatelessWidget {
  const _HeroNoteContent({required this.detail});

  final StickyNoteDetail detail;

  @override
  Widget build(BuildContext context) {
    final note = detail.note;
    final titleStyle = const TextStyle(
      color: Color(0xFF706761),
      fontSize: 12.5,
      height: 1.35,
      fontWeight: FontWeight.w500,
    );
    if (note.noteType == 'checklist') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.title?.isNotEmpty == true)
            Text(
              note.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ...detail.items
              .take(3)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFA99E97)),
                          color: item.checked
                              ? const Color(0xFFF3B2A0)
                              : Colors.transparent,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          item.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle.copyWith(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      );
    }
    return Text(
      [
        if (note.title?.isNotEmpty == true) note.title!,
        note.content,
      ].join('\n'),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );
  }
}

class _StickyNoteCard extends StatelessWidget {
  const _StickyNoteCard({
    required this.detail,
    required this.assistants,
    required this.onOpen,
    required this.onPin,
    required this.onChecklist,
    required this.onAction,
  });

  final StickyNoteDetail detail;
  final Map<String, Assistant> assistants;
  final VoidCallback onOpen;
  final VoidCallback onPin;
  final void Function(StickyNoteChecklistItem item, bool checked) onChecklist;
  final ValueChanged<String> onAction;

  static const palette = [
    Color(0xFFFDF2DF),
    Color(0xFFFAECE8),
    Color(0xFFF1F0E3),
    Color(0xFFEBF0F4),
    Color(0xFFF1EAF3),
    Color(0xFFF5EDE3),
  ];

  static const tapeColors = [
    Color(0xFFFBD59D),
    Color(0xFFF3CDC8),
    Color(0xFFDDE2BF),
    Color(0xFFC9DCEB),
    Color(0xFFE5D7E9),
    Color(0xFFEBD7BE),
  ];

  @override
  Widget build(BuildContext context) {
    final note = detail.note;
    final colorIndex = note.paletteKey % palette.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette[colorIndex],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1FC9A98F), width: 0.8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 22, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (note.title?.trim().isNotEmpty == true ||
                          note.noteType == 'checklist') ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 70),
                          child: Text(
                            note.title?.trim().isNotEmpty == true
                                ? note.title!
                                : '清单',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF36312E),
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(child: _body(note)),
                      Text(
                        _footer(note),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFAAA29D),
                          fontSize: 10.5,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: note.tapeStyle == 0 ? 0 : 1,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: note.tapeStyle == 0 ? -0.018 : 0.055,
              child: SvgPicture.asset(
                note.tapeStyle == 0
                    ? 'assets/sticky/tape_a.svg'
                    : 'assets/sticky/tape_c.svg',
                width: note.tapeStyle == 0 ? 48 : 44,
                height: 14,
                colorFilter: ColorFilter.mode(
                  tapeColors[colorIndex],
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 36,
          top: 2,
          child: Semantics(
            button: true,
            label: note.pinned ? '取消置顶' : '置顶',
            child: InkResponse(
              key: ValueKey('sticky-pin-${note.noteId}'),
              onTap: onPin,
              radius: 20,
              child: SizedBox(
                width: 40,
                height: 40,
                child: note.pinned
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.asset(
                          'assets/sticky/star_a.png',
                          filterQuality: FilterQuality.high,
                        ),
                      )
                    : const Icon(
                        Icons.star_border_rounded,
                        size: 24,
                        color: Color(0xFFB9AAA1),
                      ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 2,
          child: _StickyNoteMenuButton(
            key: ValueKey('sticky-menu-${note.noteId}'),
            onSelected: onAction,
          ),
        ),
      ],
    );
  }

  Widget _body(StickyNoteItem note) {
    const bodyStyle = TextStyle(
      color: Color(0xFF5F5853),
      fontSize: 13,
      height: 1.45,
    );
    if (note.noteType != 'checklist') {
      return Text(
        note.content,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: bodyStyle,
      );
    }
    return Column(
      children: detail.items
          .take(3)
          .map((item) {
            return SizedBox(
              height: 24,
              child: InkWell(
                onTap: () => onChecklist(item, !item.checked),
                child: Row(
                  children: [
                    Container(
                      width: 13,
                      height: 13,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: item.checked
                              ? const Color(0xFFEAAA97)
                              : const Color(0xFF9C928B),
                        ),
                        color: item.checked
                            ? const Color(0xFFF5B6A4)
                            : Colors.transparent,
                      ),
                      child: item.checked
                          ? const Icon(
                              Icons.check,
                              size: 9,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle.copyWith(
                          decoration: item.checked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  String _footer(StickyNoteItem note) {
    final date = note.updatedAt.toLocal();
    final author = note.authorType == 'assistant'
        ? assistants[note.authorAssistantId]?.name ?? '助手'
        : note.authorType == 'user'
        ? '我'
        : '系统';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$author  ${date.month}月${date.day}日 $hour:$minute';
  }
}

class _StickyNoteMenuButton extends StatefulWidget {
  const _StickyNoteMenuButton({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  State<_StickyNoteMenuButton> createState() => _StickyNoteMenuButtonState();
}

class _StickyNoteMenuButtonState extends State<_StickyNoteMenuButton> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _showMenu() async {
    final selected = await showAnchoredPopupMenu<String>(
      context: context,
      anchorKey: _anchorKey,
      direction: AnchoredPopupDirection.below,
      rowHeight: 40,
      showDividers: true,
      dismissOnAnchorTap: true,
      entries: const [
        AnchoredPopupMenuEntry(value: 'edit', label: '编辑'),
        AnchoredPopupMenuEntry(value: 'complete', label: '完成'),
        AnchoredPopupMenuEntry(value: 'cancel', label: '取消'),
        AnchoredPopupMenuEntry(value: 'delete', label: '删除'),
      ],
    );
    if (selected != null) widget.onSelected(selected);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '纸条操作',
    child: InkResponse(
      key: _anchorKey,
      onTap: _showMenu,
      radius: 20,
      child: const SizedBox(
        width: 34,
        height: 40,
        child: Center(
          child: RotatedBox(
            quarterTurns: 1,
            child: AsOneLineAssetIcon.bubbleMore(),
          ),
        ),
      ),
    ),
  );
}
