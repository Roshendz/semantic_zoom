import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

List<String> _texts(LeveledText t) => [for (final k in t.tokens) k.text];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chinese', () {
    test('parse splits characters so levels can grow inside a sentence', () {
      final t = LeveledText.parse('我[非常]喜欢猫{和狗}。');
      expect(t.textAt(0), '我喜欢猫。');
      expect(t.textAt(1), '我非常喜欢猫。');
      expect(t.textAt(2), '我非常喜欢猫和狗。');
      expect(_texts(t), ['我', '非', '常', '喜', '欢', '猫', '和', '狗', '。']);
      expect(t.tokens.skip(1).every((k) => k.glued), isTrue);
    });

    test('fromVersions keeps shared characters in place', () {
      const versions = ['我喜欢猫', '我非常喜欢猫', '我非常喜欢我的猫。'];
      final t = LeveledText.fromVersions(versions);
      for (var i = 0; i < versions.length; i++) {
        expect(t.textAt(i), versions[i]);
      }
      final report = LeveledText.checkVersions(versions);
      expect(report.isStrict, isTrue);
      expect(report.smoothness, 1);
      expect(report.transitions.first.kept, 4);
    });

    test('Latin words and numbers inside Chinese stay whole', () {
      final t = LeveledText.parse('我用Flutter开发了3个App');
      expect(
        _texts(t),
        ['我', '用', 'Flutter', '开', '发', '了', '3', '个', 'App'],
      );
      expect(t.textAt(0), '我用Flutter开发了3个App');
    });

    test('spaces the author wrote are kept', () {
      final t = LeveledText.parse('中文 English 中文');
      expect(t.textAt(0), '中文 English 中文');
      expect(t.tokens.map((k) => k.glued), [false, true, false, false, true]);
    });

    test('rich markup works around characters', () {
      final t = LeveledText.parse('**北京**[和*上海*]');
      expect(t.textAt(1), '北京和上海');
      expect(t.tokens[0].style?.fontWeight, FontWeight.bold);
      expect(t.tokens[1].style?.fontWeight, FontWeight.bold);
      expect(t.tokens[2].style, isNull);
      expect(t.tokens[3].style?.fontStyle, FontStyle.italic);
    });
  });

  test('Japanese mixes kanji and kana per character', () {
    final t = LeveledText.parse('今日は[とても]いい天気です。');
    expect(t.textAt(0), '今日はいい天気です。');
    expect(t.textAt(1), '今日はとてもいい天気です。');
    expect(_texts(t).take(3), ['今', '日', 'は']);
  });

  group('Thai', () {
    test('splits into whole grapheme clusters and round-trips', () {
      const src = 'สวัสดีครับ วันนี้อากาศดี';
      final t = LeveledText.parse(src);
      expect(t.textAt(0), src);
      for (final k in t.tokens) {
        expect(
          k.text.characters.length,
          1,
          reason: '"${k.text}" must be one cluster, marks kept with base',
        );
      }
    });

    test('levels grow inside a Thai sentence', () {
      final t = LeveledText.fromVersions(const ['ไปตลาด', 'ไปตลาดเช้านี้']);
      expect(t.textAt(0), 'ไปตลาด');
      expect(t.textAt(1), 'ไปตลาดเช้านี้');
      expect(
          LeveledText.checkVersions(const ['ไปตลาด', 'ไปตลาดเช้านี้']).isStrict,
          isTrue);
    });
  });

  test('Sinhala keeps whole words, including joined letters', () {
    // "ශ්‍රී" contains a zero-width joiner (U+200D) that forms the conjunct.
    const sri = 'ශ්‍රී';
    expect(sri.runes, contains(0x200D));
    final t = LeveledText.parse(
      'ඇල්ල දක්වා **දුම්රිය** ගමන[, $sri ලංකාවේ ලස්සනම]',
    );
    expect(_texts(t), [
      'ඇල්ල',
      'දක්වා',
      'දුම්රිය',
      'ගමන',
      ',',
      sri,
      'ලංකාවේ',
      'ලස්සනම',
    ]);
    expect(t.textAt(0), 'ඇල්ල දක්වා දුම්රිය ගමන');
    expect(t.textAt(1), 'ඇල්ල දක්වා දුම්රිය ගමන, $sri ලංකාවේ ලස්සනම');
    expect(t.tokens[2].style?.fontWeight, FontWeight.bold);
  });

  test('Korean keeps its space-separated words', () {
    final t = LeveledText.parse('한국어 문장[ 입니다]');
    expect(_texts(t), ['한국어', '문장', '입니다']);
  });

  test('a long Chinese paragraph wraps without overflowing the line', () {
    final text = LeveledText.parse(
      '今天早上我们坐火车去了波尔图，沿着海岸线一路向北，窗外的风景非常美丽。'
      '[下午我们在河边散步，晚上在一家小餐馆吃了晚饭。]',
    );
    const width = 200.0;
    final layout = LeveledTextLayout(
      text,
      style: const TextStyle(fontSize: 14),
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
    for (final level in [0, 1]) {
      final l = layout.layoutFor(level, width);
      final lines = <double>{};
      for (var i = 0; i < text.tokens.length; i++) {
        final o = l.offsets[i];
        if (o == null) continue;
        final size = layout.painters[i].size;
        expect(o.dx + size.width, lessThanOrEqualTo(width + 0.5));
        expect(size.height, lessThan(20), reason: 'token must fit one line');
        lines.add(o.dy);
      }
      expect(lines.length, greaterThanOrEqualTo(3), reason: 'text wraps');
    }
    layout.dispose();
  });
}
