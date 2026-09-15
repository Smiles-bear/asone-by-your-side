// 浏览器工具 ID 与意图判定常量。
// 独立成公开文件：聊天引擎（公开侧）与浏览器工具定义（私有侧）共用，
// 避免公开引擎经 browser_tools.dart 触达专有原生桥。

class BrowserToolIds {
  static const searchWeb = 'browser.search_web';
  static const readPage = 'browser.read_page';
  static const all = {searchWeb, readPage};

  static bool matchesContinuationIntent(String text) {
    final value = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (value.isEmpty || value.length > 12) return false;
    return const <String>{
      '再试试',
      '再试试吧',
      '再试一次',
      '再试一次吧',
      '继续搜',
      '继续搜索',
      '继续查',
      '继续查询',
      '换个词试试',
      '换个关键词',
    }.contains(value);
  }

  static bool matchesIntent(String text) {
    final value = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final explicitWebIntent = const <String>[
      '网页搜索',
      '搜索网页',
      '上网搜',
      '网上查',
      '联网搜索',
      '联网查询',
      '联网查',
      '查一下最新',
      '查最新',
      '最新消息',
      '找来源',
      '核对来源',
      '公开网页',
      '链接内容',
      '这个网址',
      '这篇文章',
      '实时信息',
      '新闻',
      '官网',
    ].any(value.contains);
    if (explicitWebIntent || value.contains('https://')) return true;

    final genericSearchIntent =
        value == '搜' ||
        value == '查' ||
        const <String>[
          '帮我搜',
          '搜一下',
          '搜索一下',
          '帮我查',
          '查一下',
          '查资料',
          '搜索资料',
          '找一下',
        ].any(value.contains);
    if (!genericSearchIntent) return false;

    // 明确查询 App 内已有资料时，仅暴露对应的本地工具。
    return !const <String>[
      '记忆',
      '聊天记录',
      '群聊记录',
      '游戏记录',
      '日记',
      '日历',
      '系统通知',
      '应用使用',
      '本地文件',
    ].any(value.contains);
  }
}
