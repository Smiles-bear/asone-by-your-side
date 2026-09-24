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

  bool _finished = false;
  bool _htmlLiteralMode = false;
  String _recentInput = '';

  /// 累积的所有安全正文（用于测试验证）
  final StringBuffer _accumulatedText = StringBuffer();

  /// 已产生的 boundary 计数（用于测试验证）
  int _boundaryCount = 0;

  /// 句末标点
  static const _sentenceEnders = ['。', '！', '？', '…'];

  /// 闭合符号（可以紧跟句末标点）
  static const _closingMarks = ['"', "'", '"', '’', '》', '）', '】', '」', '』'];

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
    if (_finished) {
      return [];
    }

    final events = <ParserEvent>[];

    for (int i = 0; i < delta.length; i++) {
      final char = delta[i];

      _recentInput = '$_recentInput$char';
      if (_recentInput.length > 40) {
        _recentInput = _recentInput.substring(_recentInput.length - 40);
      }
      if (!_htmlLiteralMode &&
          (RegExp(
                r'```html[ \t]*\r?\n$',
                caseSensitive: false,
              ).hasMatch(_recentInput) ||
              RegExp(
                r'(?:<html|<!doctype\s+html)$',
                caseSensitive: false,
              ).hasMatch(_recentInput))) {
        _htmlLiteralMode = true;
      }
      if (_htmlLiteralMode) {
        _buffer.write(char);
        events.add(TextAppendEvent(char));
        _accumulatedText.write(char);
        _awaitingNextSegment = false;
        continue;
      }

      if (_boundaryCount >= maxSegments - 1) {
        _buffer.write(char);
        events.add(TextAppendEvent(char));
        _accumulatedText.write(char);
        _awaitingNextSegment = false;
        continue;
      }

      if (_awaitingNextSegment) {
        // 已经看到句末，等待确认下一 segment 是否开始

        if (_isInterSentenceWhitespace(char)) {
          // 句间空白：忽略，不输出，继续等待
          continue;
        } else if (_isSentenceEnder(char) || _closingMarks.contains(char)) {
          // 连续句末标点或闭合符号：追加到当前 segment
          _buffer.write(char);
          events.add(TextAppendEvent(char));
          _accumulatedText.write(char);
          // 继续等待（可能还有更多）
        } else {
          // 遇到下一句正文：产生 boundary
          events.add(SegmentBoundaryEvent());
          _boundaryCount++;
          _awaitingNextSegment = false;
          _buffer.clear();

          // 输出当前字符（新 segment 的开始）
          _buffer.write(char);
          events.add(TextAppendEvent(char));
          _accumulatedText.write(char);
        }
      } else {
        // 正常积累文本
        if (char == '\n' || char == '\r') {
          // 主动换行：等待下一份正文时产生 boundary。
          // 连续换行由 awaiting 分支当作句间空白忽略，不产生空 segment。
          if (_buffer.length > 0) {
            _awaitingNextSegment = true;
          }
          continue;
        }

        _buffer.write(char);
        events.add(TextAppendEvent(char));
        _accumulatedText.write(char);

        // 检查是否是句末标点
        if (_isSentenceEnder(char) && _boundaryCount < maxSegments - 1) {
          _awaitingNextSegment = true;
        }
      }
    }

    return events;
  }

  /// 判断是否是句末标点
  bool _isSentenceEnder(String char) {
    return _sentenceEnders.contains(char);
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
