import 'dart:math' as math;
import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart'
    show FeatureUnreadSnapshot, OpenCoreBinding;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/asone_theme.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import 'sticky_note_wall_page.dart';
import 'message_board_page.dart';
import 'calendar_page.dart';

/// 版本可注入的功能页导航目标。
///
/// 私有版在构造时注入真实页面；构建器缺省时磁贴回退为"暂未开放"提示，
/// 使本页面可在社区版（无闭源页面）中独立编译。
class FeaturePageRoutes {
  const FeaturePageRoutes({
    this.game,
    this.moreTools,
    this.heartbeat,
    this.togetherWatch,
    this.togetherListen,
    this.togetherPlay,
    this.myDevices,
  });

  final WidgetBuilder? game;
  final WidgetBuilder? moreTools;
  final WidgetBuilder? heartbeat;
  final WidgetBuilder? togetherWatch;
  final WidgetBuilder? togetherListen;
  final WidgetBuilder? togetherPlay;
  final WidgetBuilder? myDevices;
}

class FeaturePage extends StatelessWidget {
  const FeaturePage({super.key, this.routes = const FeaturePageRoutes()});

  final FeaturePageRoutes routes;

  static const pageColor = AsOneTheme.pageBg;
  static const headerColor = AsOneTheme.pageBg;
  static const textColor = Color(0xFF575757);
  static const descriptionColor = AsOneTheme.textTertiary;
  static const dividerColor = AsOneTheme.divider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        backgroundColor: headerColor,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: headerColor,
        ),
        automaticallyImplyLeading: false,
        title: const Text('功能'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: dividerColor),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scale = math.min(constraints.maxWidth / 360, 1.18);
          return Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              child: SizedBox(
                width: 360 * scale,
                height: 620 * scale,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 360,
                    height: 620,
                    child: _FeatureDesignCanvas(routes: routes),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureDesignCanvas extends StatefulWidget {
  const _FeatureDesignCanvas({required this.routes});

  final FeaturePageRoutes routes;

  @override
  State<_FeatureDesignCanvas> createState() => _FeatureDesignCanvasState();
}

class _FeatureDesignCanvasState extends State<_FeatureDesignCanvas> {
  bool _openingGame = false;
  bool _openingMoreTools = false;

  @override
  void initState() {
    super.initState();
    unawaited(OpenCoreBinding.instance.featureUnread.refresh());
  }

  static const _tiles = [
    _TileSpec(
      'message_board',
      '留言板，彼此留言互动',
      23.24,
      34,
      152,
      168,
      Color(0xFFFEF3E2),
    ),
    _TileSpec('note', '小纸条，记录近期事项', 186.14, 34, 158.937, 75, Color(0xFFFCEADD)),
    _TileSpec(
      'calendar',
      '日历，记录重要日期',
      186.14,
      127,
      158.937,
      75,
      Color(0xFFFDEBE8),
    ),
    _TileSpec('game', '游戏，和助手玩游戏', 23.24, 231, 152, 65, Color(0xFFF0EAF7)),
    _TileSpec('pet', '宠物，养只电子宠物', 23.24, 317, 152, 65, Color(0xFFF4F4EB)),
    _TileSpec(
      'heartbeat',
      '心跳，设置主动行为',
      186.08,
      214,
      159,
      167,
      Color(0xFFECF5FD),
      shadowOffset: Offset(0, 4),
    ),
    _TileSpec(
      'watch_together',
      '一起看，一起看视频',
      22.76,
      420,
      100,
      84,
      Color(0xFFFDEDE6),
    ),
    _TileSpec(
      'listen_together',
      '一起听，一起听音乐',
      133.56,
      420,
      100,
      84,
      Color(0xFFFBF2EA),
    ),
    _TileSpec(
      'my_devices',
      '我的设备，连接身边设备',
      245.08,
      420,
      100,
      84,
      Color(0xFFF6F5E7),
    ),
    _TileSpec(
      'play_together',
      '一起玩，拓展更多游戏',
      22.76,
      537,
      155,
      67,
      Color(0xFFECF3F8),
    ),
    _TileSpec(
      'more_tools',
      '更多工具，更多实用工具',
      190.08,
      537,
      155,
      67,
      Color(0xFFFEF2E2),
    ),
  ];

  static const _images = [
    _ImageSpec('message_board.png', 32, 18, 132, 126),
    _ImageSpec('note.png', 278, 17, 60, 60),
    _ImageSpec('calendar.png', 281, 109, 56, 56),
    _ImageSpec('game.png', 110, 220, 60, 60),
    _ImageSpec('pet.png', 108, 303, 62, 62),
    _ImageSpec('heartbeat.png', 244, 238, 82, 60),
    _ImageSpec('watch_together.png', 43, 401, 60, 60),
    _ImageSpec('listen_together.png', 154, 399, 60, 62),
    _ImageSpec('bluetooth.png', 266, 401, 58, 58),
    _ImageSpec('play_together.png', 111, 516, 68, 70),
    _ImageSpec('more_tools.png', 277, 520, 68, 66),
  ];
  static const _texts = [
    _TextSpec('留言板', 36.05, 151.5, width: 120, title: true),
    _TextSpec('彼此留言互动', 36.05, 175, width: 120),
    _TextSpec('小纸条', 199, 57, width: 74, title: true),
    _TextSpec('记录近期事项', 199, 80, width: 74),
    _TextSpec('日历', 199, 144.5, width: 74, title: true),
    _TextSpec('记录重要日期', 199, 167, width: 74),
    _TextSpec('游戏', 36, 246, width: 68, title: true),
    _TextSpec('和助手玩游戏', 36, 270, width: 74),
    _TextSpec('宠物', 35, 332, width: 74, title: true),
    _TextSpec('养只电子宠物', 35, 356, width: 74),
    _TextSpec('心跳', 206, 325, width: 120, title: true),
    _TextSpec('设置主动行为', 206, 352, width: 120),
    _TextSpec('一起看', 22.76, 462, width: 100, title: true, centered: true),
    _TextSpec('一起看视频', 22.76, 483, width: 100, centered: true),
    _TextSpec('一起听', 133.56, 462, width: 100, title: true, centered: true),
    _TextSpec('一起听音乐', 133.56, 483, width: 100, centered: true),
    _TextSpec('我的设备', 245.08, 462, width: 100, title: true, centered: true),
    _TextSpec('连接身边设备', 245.08, 483, width: 100, centered: true),
    _TextSpec('一起玩', 36, 550, width: 66, title: true),
    _TextSpec('拓展更多游戏', 36, 575, width: 100),
    _TextSpec('更多工具', 203, 550, width: 68, title: true),
    _TextSpec('更多实用工具', 203, 575, width: 80),
  ];

  void _openUnavailable() {
    AsOneToast.show(context, '暂未开放，敬请期待', icon: AsOneIconName.info);
  }

  void _openRouted(WidgetBuilder? builder) {
    if (builder == null) {
      _openUnavailable();
      return;
    }
    _openPage(builder(context));
  }

  void _openGameLobby() {
    final builder = widget.routes.game;
    if (builder == null) {
      _openUnavailable();
      return;
    }
    if (_openingGame) return;
    setState(() => _openingGame = true);
    unawaited(
      Navigator.push(context, MaterialPageRoute(builder: builder)).whenComplete(
        () {
          if (mounted) setState(() => _openingGame = false);
        },
      ),
    );
  }

  void _openMoreTools() {
    final builder = widget.routes.moreTools;
    if (builder == null) {
      _openUnavailable();
      return;
    }
    if (_openingMoreTools) return;
    setState(() => _openingMoreTools = true);
    unawaited(
      Navigator.push(context, MaterialPageRoute(builder: builder)).whenComplete(
        () {
          if (mounted) setState(() => _openingMoreTools = false);
        },
      ),
    );
  }

  void _openPage(Widget page) {
    unawaited(
      Navigator.push(context, MaterialPageRoute(builder: (context) => page)),
    );
  }

  Future<void> _openHeartbeat() async {
    final builder = widget.routes.heartbeat;
    if (builder == null) {
      _openUnavailable();
      return;
    }
    final assistants = await OpenCoreBinding.instance.assistants
        .getAssistants();
    if (!mounted) return;
    if (assistants.isEmpty) {
      AsOneToast.show(context, '请先创建一个助手', icon: AsOneIconName.info);
      return;
    }
    _openPage(builder(context));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FeatureUnreadSnapshot>(
      valueListenable: OpenCoreBinding.instance.featureUnread.changes,
      builder: (context, unread, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final tile in _tiles) tile.build(),
          for (final image in _images) image.build(),
          for (final text in _texts) text.build(),
          Positioned(
            left: 23.24,
            top: 317,
            width: 152,
            height: 65,
            child: Semantics(
              key: const Key('feature-pet-disabled'),
              container: true,
              button: true,
              label: '宠物，养只电子宠物，暂未开放',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => AsOneToast.show(
                  context,
                  '暂未开放，敬请期待',
                  icon: AsOneIconName.info,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 22.76,
            top: 420,
            width: 100,
            height: 84,
            child: Semantics(
              button: true,
              label: '一起看，一起看视频',
              child: GestureDetector(
                key: const Key('feature-together-watch-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openRouted(widget.routes.togetherWatch),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 190.08,
            top: 537,
            width: 155,
            height: 67,
            child: Semantics(
              button: true,
              label: '更多工具，管理远程 MCP',
              child: GestureDetector(
                key: const Key('feature-more-tools-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: _openingMoreTools ? null : _openMoreTools,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 245.08,
            top: 420,
            width: 100,
            height: 84,
            child: Semantics(
              button: true,
              label: '我的设备，连接身边设备',
              child: GestureDetector(
                key: const Key('feature-my-devices-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openRouted(widget.routes.myDevices),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 133.56,
            top: 420,
            width: 100,
            height: 84,
            child: Semantics(
              button: true,
              label: '一起听，一起听音乐',
              child: GestureDetector(
                key: const Key('feature-together-listen-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openRouted(widget.routes.togetherListen),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 22.76,
            top: 537,
            width: 155,
            height: 67,
            child: Semantics(
              button: true,
              label: '一起玩，拓展更多游戏',
              child: GestureDetector(
                key: const Key('feature-together-play-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openRouted(widget.routes.togetherPlay),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 23.24,
            top: 231,
            width: 152,
            height: 65,
            child: Semantics(
              button: true,
              enabled: !_openingGame,
              label: '游戏，和助手玩游戏',
              child: GestureDetector(
                key: const Key('feature-game-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: _openingGame ? null : _openGameLobby,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 186.08,
            top: 214,
            width: 159,
            height: 167,
            child: Semantics(
              button: true,
              label: '心跳，设置主动行为',
              child: GestureDetector(
                key: const Key('feature-heartbeat-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: _openHeartbeat,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // 持续心智批次 1：留言板 / 小纸条 / 日历入口（M4 §23）
          Positioned(
            left: 23.24,
            top: 34,
            width: 152,
            height: 168,
            child: Semantics(
              button: true,
              label: '留言板，彼此留言互动',
              child: GestureDetector(
                key: const Key('feature-message-board-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPage(const MessageBoardPage()),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 186.14,
            top: 34,
            width: 158.937,
            height: 75,
            child: Semantics(
              button: true,
              label: '小纸条，记录近期事项',
              child: GestureDetector(
                key: const Key('feature-note-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPage(const StickyNoteWallPage()),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 186.14,
            top: 127,
            width: 158.937,
            height: 75,
            child: Semantics(
              button: true,
              label: '日历，记录重要日期',
              child: GestureDetector(
                key: const Key('feature-calendar-hit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPage(const CalendarPage()),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 619,
            child: Divider(
              height: 1,
              thickness: 1,
              color: FeaturePage.dividerColor,
            ),
          ),
          if (unread.messageBoardCount > 0)
            _FeatureUnreadBadge(
              key: const Key('feature-message-board-unread-dot'),
              left: 157.24,
              top: 42,
              count: unread.messageBoardCount,
            ),
          if (unread.stickyNote)
            const _FeatureUnreadDot(
              key: Key('feature-note-unread-dot'),
              left: 327.08,
              top: 42,
            ),
          if (unread.calendar)
            const _FeatureUnreadDot(
              key: Key('feature-calendar-unread-dot'),
              left: 327.08,
              top: 135,
            ),
        ],
      ),
    );
  }
}

class _FeatureUnreadDot extends StatelessWidget {
  const _FeatureUnreadDot({super.key, required this.left, required this.top});

  final double left;
  final double top;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    top: top,
    child: const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AsOneTheme.notificationBadge,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 8),
      ),
    ),
  );
}

class _FeatureUnreadBadge extends StatelessWidget {
  const _FeatureUnreadBadge({
    super.key,
    required this.left,
    required this.top,
    required this.count,
  });

  final double left;
  final double top;
  final int count;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    top: top,
    child: IgnorePointer(
      child: Semantics(
        label: '$count 条未读留言',
        child: Container(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AsOneTheme.notificationBadge,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white, width: 1.2),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}

class _TileSpec {
  const _TileSpec(
    this.id,
    this.label,
    this.left,
    this.top,
    this.width,
    this.height,
    this.color, {
    this.shadowOffset = const Offset(4, 4),
  });

  final String id;
  final String label;
  final double left;
  final double top;
  final double width;
  final double height;
  final Color color;
  final Offset shadowOffset;

  Widget build() {
    final child = Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            offset: shadowOffset,
            blurRadius: 4,
          ),
        ],
      ),
    );

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: KeyedSubtree(
        key: Key('feature-tile-$id'),
        child: ExcludeSemantics(
          child: KeyedSubtree(key: ValueKey(label), child: child),
        ),
      ),
    );
  }
}

class _ImageSpec {
  const _ImageSpec(this.name, this.left, this.top, this.width, this.height);

  final String name;
  final double left;
  final double top;
  final double width;
  final double height;

  Widget build() {
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Image.asset(
        key: Key('feature-image-$name'),
        'assets/features/$name',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}

class _TextSpec {
  const _TextSpec(
    this.text,
    this.left,
    this.top, {
    this.width,
    this.title = false,
    this.centered = false,
  });

  final String text;
  final double left;
  final double top;
  final double? width;
  final bool title;
  final bool centered;

  Widget build() {
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: centered ? TextAlign.center : TextAlign.left,
        style: title ? _titleStyle : _descriptionStyle,
      ),
    );
  }

  static final _titleStyle = AsOneTheme.secondaryStyle.copyWith(
    color: FeaturePage.textColor,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static final _descriptionStyle = AsOneTheme.captionStyle.copyWith(
    color: FeaturePage.descriptionColor,
  );
}
