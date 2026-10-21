/// Parser 输出事件
sealed class ParserEvent {}

/// 安全正文增量（可立即显示）
class TextAppendEvent extends ParserEvent {
  final String text;
  TextAppendEvent(this.text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextAppendEvent && text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextAppend("$text")';
}

/// Segment 边界（当前消息结束，下一条即将开始）
class SegmentBoundaryEvent extends ParserEvent {
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SegmentBoundaryEvent;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'SegmentBoundary';
}

/// 连续消息 Parser（自然标点分段版本）
///
/// 核心原则：
/// - 普通正文立即输出 TextAppendEvent
/// - 识别句末标点（。！？…）+ 可选闭合符号（"'》）】」』）
/// - 模型主动换行（单换行或空行）也可标记 segment 边界
/// - 句末后遇到下一句正文时产生 SegmentBoundary
/// - 句间空白不进入下一 segment
class ContinuousMessageParser {
  ContinuousMessageParser();

  static const int maxSegments = 6;

  /// 当前积累的文本（等待确认是否产生 boundary）
  final StringBuffer _buffer = StringBuffer();

  /// 是否刚刚看到句末（等待确认下一 segment 是否开始）
  bool _awaitingNextSegment = false;
  bool _explicitLineBoundary = false;
  bool _enclosedSentenceEnd = false;
  final List<String> _enclosures = [];

  bool _finished = false;
  bool _htmlLiteralMode = false;
  String? _fenceCharacter;
  int _fenceLength = 0;
  bool _inlineCodeMode = false;
  String _recentInput = '';
  final StringBuffer _currentLine = StringBuffer();

  /// 累积的所有安全正文（用于测试验证）
  final StringBuffer _accumulatedText = StringBuffer();

  /// 已产生的 boundary 计数（用于测试验证）
  int _boundaryCount = 0;

  /// 句末标点
  static const _sentenceEnders = ['。', '！', '？', '…'];

  /// 闭合符号（可以紧跟句末标点）
  static const _closingMarks = [
    '"',
    "'",
    '”',
    '’',
    '》',
    '）',
    ')',
    '】',
    ']',
    '」',
    '』',
  ];
  static const _pairs = {
    '“': '”',
    '‘': '’',
    '「': '」',
    '『': '』',
    '（': '）',
    '(': ')',
    '【': '】',
    '[': ']',
    '《': '》',
    '"': '"',
  };
  static const _continuations = ['，', ',', '、', '：', ':', '；', ';'];

  /// 句间空白（不进入下一 segment）
  static bool _isInterSentenceWhitespace(String char) {
    return char == ' ' || char == '\n' || char == '\t' || char == '\r';
  }

  /// 喂入一个 delta 字符串
  ///
  /// 返回事件列表：
  /// - TextAppendEvent: 安全正文增量，可立即显示
  /// - SegmentBoundaryEvent: segment 边界，当前消息结束
  List<ParserEvent> feed(String delta) {
    if (_finished) return [];
    final events = <ParserEvent>[];
    for (var index = 0; index < delta.length; index++) {
      _consumeCharacter(delta[index], events);
    }
    return events;
  }

  void _consumeCharacter(String char, List<ParserEvent> events) {
    _currentLine.write(char);
    _trackRecentInput(char);
    final wasFenced = _fenceCharacter != null;
    final restoreOpeningCarriageReturn = _openFenceIfNeeded(
      char,
      wasFenced: wasFenced,
    );
    if (_htmlLiteralMode || _fenceCharacter != null) {
      _consumeProtectedCharacter(
        char,
        events,
        wasFenced: wasFenced,
        restoreOpeningCarriageReturn: restoreOpeningCarriageReturn,
      );
      return;
    }
    _consumePlainCharacter(char, events);
  }

  void _trackRecentInput(String char) {
    _recentInput = '$_recentInput$char';
    if (_recentInput.length > 40) {
      _recentInput = _recentInput.substring(_recentInput.length - 40);
    }
    if (_htmlLiteralMode) return;
    final opensHtmlFence = RegExp(
      r'```html[ \t]*\r?\n$',
      caseSensitive: false,
    ).hasMatch(_recentInput);
    final opensHtmlDocument = RegExp(
      r'(?:<html|<!doctype\s+html)$',
      caseSensitive: false,
    ).hasMatch(_recentInput);
    if (opensHtmlFence || opensHtmlDocument) _htmlLiteralMode = true;
  }

  bool _openFenceIfNeeded(String char, {required bool wasFenced}) {
    if (wasFenced || char != '\n') return false;
    final opening = RegExp(
      r'^\s{0,3}(`{3,}|~{3,})[^\r\n]*\r?\n?$',
    ).firstMatch(_currentLine.toString());
    if (opening == null) return false;
    final fence = opening.group(1)!;
    _fenceCharacter = fence[0];
    _fenceLength = fence.length;
    _inlineCodeMode = false;
    return _currentLine.toString().endsWith('\r\n');
  }

  void _consumeProtectedCharacter(
    String char,
    List<ParserEvent> events, {
    required bool wasFenced,
    required bool restoreOpeningCarriageReturn,
  }) {
    if (restoreOpeningCarriageReturn) _appendVisible('\r', events);
    _appendVisible(char, events);
    _awaitingNextSegment = false;
    if (wasFenced && char == '\n' && _isClosingFenceLine()) {
      _fenceCharacter = null;
      _fenceLength = 0;
      _awaitingNextSegment = _buffer.length > 0;
    }
    if (char == '\n') _currentLine.clear();
  }

  void _consumePlainCharacter(String char, List<ParserEvent> events) {
    if (char == '`') {
      _inlineCodeMode = !_inlineCodeMode;
      _appendVisible(char, events);
      _awaitingNextSegment = false;
      return;
    }
    if (_inlineCodeMode || _boundaryCount >= maxSegments - 1) {
      _appendVisible(char, events);
      _awaitingNextSegment = false;
      if (char == '\n') _currentLine.clear();
      return;
    }
    final closedEnclosure = _trackEnclosure(char);
    if (_awaitingNextSegment) {
      if (!_explicitLineBoundary && _continuations.contains(char)) {
        _awaitingNextSegment = false;
        _enclosedSentenceEnd = false;
        _appendVisible(char, events);
        return;
      }
      _consumeAwaitingCharacter(char, events);
      return;
    }
    _consumeCurrentSegmentCharacter(char, events, closedEnclosure);
  }

  bool _trackEnclosure(String char) {
    if (_enclosures.isNotEmpty && _enclosures.last == char) {
      _enclosures.removeLast();
      return true;
    }
    if (_pairs[char] case final closing?) _enclosures.add(closing);
    return false;
  }

  void _consumeAwaitingCharacter(String char, List<ParserEvent> events) {
    if (_isInterSentenceWhitespace(char)) {
      if (char == '\n') _currentLine.clear();
      return;
    }
    if (_isSentenceEnder(char) || _closingMarks.contains(char)) {
      _appendVisible(char, events);
      return;
    }
    events.add(SegmentBoundaryEvent());
    _boundaryCount++;
    _awaitingNextSegment = false;
    _explicitLineBoundary = false;
    _enclosedSentenceEnd = false;
    _buffer.clear();
    _appendVisible(char, events);
  }

  void _consumeCurrentSegmentCharacter(
    String char,
    List<ParserEvent> events,
    bool closedEnclosure,
  ) {
    if (char == '\n' || char == '\r') {
      if (_buffer.length > 0) {
        _awaitingNextSegment = true;
        _explicitLineBoundary = true;
      }
      if (char == '\n') _currentLine.clear();
      return;
    }
    _appendVisible(char, events);
    if (_isSentenceEnder(char) && _boundaryCount < maxSegments - 1) {
      _enclosedSentenceEnd = _enclosures.isNotEmpty;
      _awaitingNextSegment = !_enclosedSentenceEnd;
      _explicitLineBoundary = false;
    } else if (closedEnclosure && _enclosedSentenceEnd) {
      if (_enclosures.isEmpty) _awaitingNextSegment = true;
    } else {
      _enclosedSentenceEnd = false;
    }
    if (char == '\n') _currentLine.clear();
  }

  void _appendVisible(String char, List<ParserEvent> events) {
    _buffer.write(char);
    events.add(TextAppendEvent(char));
    _accumulatedText.write(char);
  }

  /// 判断是否是句末标点
  bool _isSentenceEnder(String char) {
    return _sentenceEnders.contains(char);
  }

  bool _isClosingFenceLine() {
    final marker = _fenceCharacter;
    if (marker == null) return false;
    final line = _currentLine.toString().trim();
    return RegExp(
      '^${RegExp.escape(marker)}{$_fenceLength,}\\s*\$',
    ).hasMatch(line);
  }

  /// 结束流
  ///
  /// 返回空列表（无额外事件产生）
  List<ParserEvent> finish() {
    _finished = true;
    return [];
  }

  /// 获取累积的所有正文（测试用）
  String get accumulatedText => _accumulatedText.toString();

  /// 获取产生的 boundary 计数（测试用）
  int get boundaryCount => _boundaryCount;

  /// 是否已标记完成
  bool get isFinished => _finished;
}
