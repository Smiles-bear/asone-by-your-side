import 'package:flutter_test/flutter_test.dart';
import 'package:azruiyoi_community/local_core/continuous_message_parser.dart';

void main() {
  test('引用问号逗号续句跨任意delta不拆断', () {
    const source = '你只发了“？”，我继续说明。下一句。';
    for (final chunks in [
      [source],
      source.split(''),
      ['你只发了“', '？', '”', '，我继续说明。', '下一句。'],
    ]) {
      final parser = ContinuousMessageParser();
      final segments = <String>[''];
      for (final chunk in chunks) {
        for (final event in parser.feed(chunk)) {
          if (event is SegmentBoundaryEvent) segments.add('');
          if (event is TextAppendEvent) {
            segments[segments.length - 1] += event.text;
          }
        }
      }
      expect(segments, ['你只发了“？”，我继续说明。', '下一句。']);
    }
  });

  test('嵌套引语与括号内标点只在外层句末分段', () {
    const source = '他引用“她问‘好？’，然后说好。”，接着解释（为什么？因为如此）。结束。';
    final parser = ContinuousMessageParser();
    final segments = <String>[''];
    for (final char in source.split('')) {
      for (final event in parser.feed(char)) {
        if (event is SegmentBoundaryEvent) segments.add('');
        if (event is TextAppendEvent) {
          segments[segments.length - 1] += event.text;
        }
      }
    }
    expect(segments, ['他引用“她问‘好？’，然后说好。”，接着解释（为什么？因为如此）。', '结束。']);
  });

  test('HTML 围栏逐字符流保留换行且不在代码中分段', () {
    final parser = ContinuousMessageParser();
    final source =
        '```html\n<html>\n<body>你好。\n<p>第二行</p>\n</body>\n</html>\n```';
    final events = <ParserEvent>[];
    for (final char in source.split('')) {
      events.addAll(parser.feed(char));
    }
    expect(
      events.whereType<TextAppendEvent>().map((e) => e.text).join(),
      source,
    );
    expect(parser.boundaryCount, 0);
  });

  test('完整 HTML 文档逐字符流保留换行', () {
    final parser = ContinuousMessageParser();
    const source = '<!DOCTYPE html>\n<html>\n<body>第一行。\n第二行</body></html>';
    for (final char in source.split('')) {
      parser.feed(char);
    }
    expect(parser.accumulatedText, source);
    expect(parser.boundaryCount, 0);
  });

  test('Markdown 围栏跨任意 delta 保留原文且不在代码内分段', () {
    final parser = ContinuousMessageParser();
    final events = <ParserEvent>[];
    for (final chunk in [
      '开头。\n``',
      '``da',
      'rt\r',
      '\nvoid main() {\r\n',
      '  print("好。");\r\n}\r\n``',
      '``\r\n结尾。',
    ]) {
      events.addAll(parser.feed(chunk));
    }
    final visible = events
        .whereType<TextAppendEvent>()
        .map((event) => event.text)
        .join();
    expect(visible, contains('````dart\r\nvoid main() {\r\n'));
    expect(visible, contains('print("好。");\r\n}\r\n````\r\n'));
    expect(parser.boundaryCount, 1);
  });

  test('波浪线未闭合围栏和行内代码中的标点不会拆段', () {
    final fenced = ContinuousMessageParser();
    fenced.feed('~~~python\nprint("一。")\n仍在代码里！');
    expect(fenced.boundaryCount, 0);
    expect(fenced.accumulatedText, '~~~python\nprint("一。")\n仍在代码里！');

    final inline = ContinuousMessageParser();
    inline.feed('这里有 `a。b！c` 然后结束。');
    expect(inline.boundaryCount, 0);
    expect(inline.accumulatedText, '这里有 `a。b！c` 然后结束。');
  });

  test('长文本分块解析保持原文且在定向性能预算内完成', () {
    final source =
        '```text\n${List.generate(6000, (index) => 'code_$index = "不会在代码里拆段。";').join('\n')}\n```';
    final parser = ContinuousMessageParser();
    final stopwatch = Stopwatch()..start();
    for (var offset = 0; offset < source.length; offset += 37) {
      final end = offset + 37 < source.length ? offset + 37 : source.length;
      parser.feed(source.substring(offset, end));
    }
    parser.finish();
    stopwatch.stop();

    expect(parser.accumulatedText, source);
    expect(parser.boundaryCount, lessThanOrEqualTo(5));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  group('Continuous Parser - Punctuation Segmentation', () {
    test('最多六段，超出的长文和换行全部合并到第六段', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('一。二。三。四。五。六。\n七。八。');
      parser.finish();

      expect(parser.boundaryCount, 5);
      expect(events.whereType<SegmentBoundaryEvent>(), hasLength(5));
      expect(
        events.whereType<TextAppendEvent>().map((event) => event.text).join(),
        '一。二。三。四。五。六。\n七。八。',
      );
    });

    test('基本句末分段', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('你好。明天见。');

      expect(events.map((e) => e.toString()).toList(), [
        'TextAppend("你")',
        'TextAppend("好")',
        'TextAppend("。")',
        'SegmentBoundary',
        'TextAppend("明")',
        'TextAppend("天")',
        'TextAppend("见")',
        'TextAppend("。")',
      ]);

      expect(parser.accumulatedText, '你好。明天见。');
      expect(parser.boundaryCount, 1);
    });

    test('streaming 逐字符输入', () {
      final parser = ContinuousMessageParser();
      final events = <ParserEvent>[];

      events.addAll(parser.feed('你'));
      events.addAll(parser.feed('好'));
      events.addAll(parser.feed('。'));
      events.addAll(parser.feed('明'));
      events.addAll(parser.feed('天'));
      events.addAll(parser.feed('见'));
      events.addAll(parser.feed('。'));

      expect(events.map((e) => e.toString()).toList(), [
        'TextAppend("你")',
        'TextAppend("好")',
        'TextAppend("。")',
        'SegmentBoundary',
        'TextAppend("明")',
        'TextAppend("天")',
        'TextAppend("见")',
        'TextAppend("。")',
      ]);

      expect(parser.accumulatedText, '你好。明天见。');
      expect(parser.boundaryCount, 1);
    });

    test('chunk 任意切割不影响结果', () {
      final parser = ContinuousMessageParser();
      final events = <ParserEvent>[];

      events.addAll(parser.feed('你好'));
      events.addAll(parser.feed('。明'));
      events.addAll(parser.feed('天见。'));

      expect(events.map((e) => e.toString()).toList(), [
        'TextAppend("你")',
        'TextAppend("好")',
        'TextAppend("。")',
        'SegmentBoundary',
        'TextAppend("明")',
        'TextAppend("天")',
        'TextAppend("见")',
        'TextAppend("。")',
      ]);

      expect(parser.accumulatedText, '你好。明天见。');
    });

    test('连续句末标点', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('真的吗？！可以呀！');

      expect(parser.accumulatedText, '真的吗？！可以呀！');
      expect(parser.boundaryCount, 1);

      // 验证 ？！ 都在第一个 segment
      final textBeforeBoundary = <String>[];
      for (final event in events) {
        if (event is SegmentBoundaryEvent) break;
        if (event is TextAppendEvent) textBeforeBoundary.add(event.text);
      }
      expect(textBeforeBoundary.join(''), '真的吗？！');
    });

    test('连续省略号', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('哈哈哈……我知道啦。');

      expect(parser.accumulatedText, '哈哈哈……我知道啦。');
      expect(parser.boundaryCount, 1);

      final textBeforeBoundary = <String>[];
      for (final event in events) {
        if (event is SegmentBoundaryEvent) break;
        if (event is TextAppendEvent) textBeforeBoundary.add(event.text);
      }
      expect(textBeforeBoundary.join(''), '哈哈哈……');
    });

    test('闭合符号跟随句末', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('"真的吗？"我也觉得。');

      expect(parser.accumulatedText, '"真的吗？"我也觉得。');
      expect(parser.boundaryCount, 1);

      final textBeforeBoundary = <String>[];
      for (final event in events) {
        if (event is SegmentBoundaryEvent) break;
        if (event is TextAppendEvent) textBeforeBoundary.add(event.text);
      }
      expect(textBeforeBoundary.join(''), '"真的吗？"');
    });

    test('句间换行不进入下一 segment', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('你好。\n明天见。');

      expect(parser.accumulatedText, '你好。明天见。');
      expect(parser.boundaryCount, 1);

      final textAfterBoundary = <String>[];
      bool afterBoundary = false;
      for (final event in events) {
        if (event is SegmentBoundaryEvent) {
          afterBoundary = true;
          continue;
        }
        if (afterBoundary && event is TextAppendEvent) {
          textAfterBoundary.add(event.text);
        }
      }
      expect(textAfterBoundary.join(''), '明天见。');
      expect(textAfterBoundary.first, '明'); // 不以换行开头
    });

    test('单换行产生 segment boundary', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('第一段。\n第二段。');

      expect(_segmentsFrom(events), ['第一段。', '第二段。']);
      expect(parser.boundaryCount, 1);
    });

    test('空行产生单个 segment boundary', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('第一段。\n\n第二段。');

      expect(_segmentsFrom(events), ['第一段。', '第二段。']);
      expect(parser.boundaryCount, 1);
    });

    test('无句末标点时主动换行仍可分段', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('第一段\n第二段');

      expect(_segmentsFrom(events), ['第一段', '第二段']);
      expect(parser.boundaryCount, 1);
    });

    test('句间多个空格不进入下一 segment', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('你好。   明天见。');

      expect(parser.accumulatedText, '你好。明天见。');
      expect(parser.boundaryCount, 1);

      final textAfterBoundary = <String>[];
      bool afterBoundary = false;
      for (final event in events) {
        if (event is SegmentBoundaryEvent) {
          afterBoundary = true;
          continue;
        }
        if (afterBoundary && event is TextAppendEvent) {
          textAfterBoundary.add(event.text);
        }
      }
      expect(textAfterBoundary.join(''), '明天见。');
      expect(textAfterBoundary.first, '明'); // 不以空格开头
    });

    test('英文句号不分段（版本号）', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('3.14版本还不错。');

      expect(parser.accumulatedText, '3.14版本还不错。');
      expect(parser.boundaryCount, 0); // 只在最后中文句号处等待

      // 验证 3.14 未产生 boundary
      final boundaries = events.whereType<SegmentBoundaryEvent>().toList();
      expect(boundaries.length, 0);
    });

    test('英文点号不分段（v1.2.3）', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('v1.2.3可以用。');

      expect(parser.accumulatedText, 'v1.2.3可以用。');
      expect(parser.boundaryCount, 0); // 只在最后中文句号处等待

      final boundaries = events.whereType<SegmentBoundaryEvent>().toList();
      expect(boundaries.length, 0);
    });

    test('无句末标点', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('你好呀');

      expect(parser.accumulatedText, '你好呀');
      expect(parser.boundaryCount, 0);

      final boundaries = events.whereType<SegmentBoundaryEvent>().toList();
      expect(boundaries.isEmpty, true);
    });

    test('terminal 句末不产生空气泡', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('你好。');
      parser.finish();

      expect(parser.accumulatedText, '你好。');
      expect(parser.boundaryCount, 0); // 没有后续正文，不产生 boundary

      final boundaries = events.whereType<SegmentBoundaryEvent>().toList();
      expect(boundaries.isEmpty, true);
    });

    test('多个 segment', () {
      final parser = ContinuousMessageParser();
      parser.feed('第一句。第二句！第三句？');

      expect(parser.accumulatedText, '第一句。第二句！第三句？');
      expect(parser.boundaryCount, 2);
    });

    test('问号和感叹号', () {
      final parser = ContinuousMessageParser();
      parser.feed('真的吗？当然啦！');

      expect(parser.accumulatedText, '真的吗？当然啦！');
      expect(parser.boundaryCount, 1);
    });

    test('多种闭合符号', () {
      final parser = ContinuousMessageParser();

      // 双引号
      parser.feed('他说"好的。"');
      expect(parser.boundaryCount, 0);

      final parser2 = ContinuousMessageParser();
      // 书名号
      parser2.feed('读《论语》。后面');
      expect(parser2.boundaryCount, 1);

      final parser3 = ContinuousMessageParser();
      // 括号
      parser3.feed('可以（真的！）下次');
      expect(parser3.boundaryCount, 1);
    });

    test('中文弯引号（双引号）', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed('"真的吗？"我也觉得。');

      expect(parser.accumulatedText, '"真的吗？"我也觉得。');
      expect(parser.boundaryCount, 1);

      final textBeforeBoundary = <String>[];
      for (final event in events) {
        if (event is SegmentBoundaryEvent) break;
        if (event is TextAppendEvent) textBeforeBoundary.add(event.text);
      }
      expect(textBeforeBoundary.join(''), '"真的吗？"');
    });

    test('中文弯引号（单引号）', () {
      final parser = ContinuousMessageParser();
      final events = parser.feed("'真的？'好的。");

      expect(parser.accumulatedText, "'真的？'好的。");
      expect(parser.boundaryCount, 1);

      final textBeforeBoundary = <String>[];
      for (final event in events) {
        if (event is SegmentBoundaryEvent) break;
        if (event is TextAppendEvent) textBeforeBoundary.add(event.text);
      }
      expect(textBeforeBoundary.join(''), "'真的？'");
    });
  });
}

List<String> _segmentsFrom(List<ParserEvent> events) {
  final segments = <String>[];
  final current = StringBuffer();

  for (final event in events) {
    if (event is TextAppendEvent) {
      current.write(event.text);
    } else if (event is SegmentBoundaryEvent) {
      segments.add(current.toString());
      current.clear();
    }
  }

  if (current.length > 0) {
    segments.add(current.toString());
  }
  return segments;
}
