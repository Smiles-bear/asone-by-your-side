import 'package:flutter/material.dart';

/// 如一 AsOne 主题配置
class AsOneTheme {
  // 页面背景：设计图暖米色
  static const Color pageBg = Color(0xFFFFF8F5);
  static const Color chatBg = Color(0xFFFFF8F5);
  static const Color aiBubble = Color(0xFFFFF0E6);
  static const Color userBubble = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFE86B5D);
  static const Color accentSoft = Color(0xFFF4A582);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color chatBodyText = Color(0xFF484848);
  static const Color textSecondary = Color(0xFF737373);
  static const Color textTertiary = Color(0xFF8A8A8A);
  static const Color textDisabled = Color(0xFFB3B3B3);
  static const Color divider = Color(0xFFE5E5E5);
  static const Color selectedBg = Color(0xFFFFF5F0);
  static const Color cardBg = Color(0xFFFFF0E6);
  static const Color tabInactive = Color(0xFF999999);
  // 底部菜单栏未选中态：设计图为浅珊瑚色（非灰）
  static const Color tabInactiveSoft = Color(0xFFF2A896);
  // 列表项按压/选中态浅杏底
  static const Color tileHighlight = Color(0xFFFBEAE3);
  // Destructive actions remain unmistakably red without the high-saturation
  // alarm tone previously used by full-width buttons.
  static const Color danger = Color(0xFFB85A55);
  // Material red reserved for unread badges and notification dots. It must not
  // inherit the deliberately muted destructive-action color above.
  static const Color notificationBadge = Color(0xFFF44336);
  static const Color iconDefault = Color(0xFF202020);
  static const Color iconAccent = Color(0xFFE78C71);
  static const Color iconDisabled = Color(0xFFC2C2C2);
  static const Color iconInverse = Color(0xFFFFFFFF);
  // Shared semantic typography for all user-facing pages.
  static const TextStyle displayTitleStyle = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  static const TextStyle pageTitleStyle = TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  static const TextStyle dialogTitleStyle = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  static const TextStyle sectionTitleStyle = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  static const TextStyle listTitleStyle = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );
  static const TextStyle bodyLargeStyle = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );
  static const TextStyle bodyStyle = TextStyle(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );
  static const TextStyle secondaryStyle = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );
  static const TextStyle captionStyle = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: textTertiary,
  );
  static const TextStyle microStyle = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: textTertiary,
  );
  static const TextStyle buttonStyle = TextStyle(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w500,
  );

  /// 主题色映射
  static Color accentFor(String key) {
    switch (key) {
      case 'coral':
        return const Color(0xFFE86B5D); // 珊瑚橙
      case 'blue':
        return const Color(0xFF4A90D9); // 海盐蓝
      case 'green':
        return const Color(0xFF3FAE8A); // 薄荷绿
      case 'purple':
        return const Color(0xFF8E6FD8); // 葡萄紫
      case 'yellow':
        return const Color(0xFFE8A33D); // 落日黄
      default:
        return const Color(0xFFE86B5D); // 默认珊瑚橙
    }
  }

  /// 聊天背景色映射
  static Color chatBgFor(String key) {
    switch (key) {
      case 'default':
        return const Color(0xFFFFF8F5); // 默认暖米
      case 'gray':
        return const Color(0xFFF5F5F5); // 浅灰
      case 'blue':
        return const Color(0xFFEEF3FA); // 淡蓝
      case 'green':
        return const Color(0xFFEEF6F0); // 浅绿
      default:
        return const Color(0xFFFFF8F5); // 默认暖米
    }
  }

  static ThemeData light(Color accentColor) => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: pageBg,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'sans-serif'],
    colorScheme: ColorScheme.fromSeed(
      seedColor: accentColor,
      primary: accentColor,
      surface: pageBg,
    ),
    textTheme: const TextTheme(
      headlineSmall: displayTitleStyle,
      titleLarge: pageTitleStyle,
      titleMedium: sectionTitleStyle,
      titleSmall: listTitleStyle,
      bodyLarge: bodyLargeStyle,
      bodyMedium: bodyStyle,
      bodySmall: secondaryStyle,
      labelLarge: buttonStyle,
      labelMedium: captionStyle,
      labelSmall: microStyle,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: pageBg,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: pageTitleStyle,
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: listTitleStyle,
      subtitleTextStyle: secondaryStyle,
      textColor: textPrimary,
    ),
    cardTheme: CardThemeData(
      color: cardBg,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFFFFCFA),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: dialogTitleStyle,
      contentTextStyle: bodyStyle,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFF0E5E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accentColor, width: 1.4),
      ),
      hintStyle: bodyLargeStyle.copyWith(color: textDisabled),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: buttonStyle,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: BorderSide(color: accentColor.withValues(alpha: 0.45)),
        textStyle: buttonStyle,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: pageBg,
      selectedItemColor: accentColor,
      unselectedItemColor: tabInactive,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      showUnselectedLabels: true,
      selectedLabelStyle: microStyle.copyWith(fontWeight: FontWeight.w500),
      unselectedLabelStyle: microStyle,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFFFFCFA),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerColor: divider,
  );
}
