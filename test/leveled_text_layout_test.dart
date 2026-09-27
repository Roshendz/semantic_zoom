import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

// Tests use the Ahem font: every glyph is a square of side fontSize.
const _style = TextStyle(fontSize: 10, height: 1);

LeveledTextLayout _layout(
  String markup, {
  TextDirection dir = TextDirection.ltr,
  double gap = 6,
}) =>
    LeveledTextLayout(
      LeveledText.parse(markup),
      style: _style,
      textScaler: TextScaler.noScaling,
      textDirection: dir,
      paragraphGap: gap,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hides tokens above the level; shared words slide', () {
    final l = _layout('aa [bb] cc');
    final brief = l.layoutFor(0, 1000);
    final medium = l.layoutFor(1, 1000);
    expect(brief.offsets[1], isNull);
    expect(brief.offsets[2]!.dx, 30);
    expect(medium.offsets[2]!.dx, 60);
    expect(medium.offsets[0], brief.offsets[0]);
    expect(brief.height, 10);
  });

  test('uses the engine line breaker', () {
    final l = _layout('aaaa bbbb cccc');
    expect(l.layoutFor(0, 1000).height, 10);
    final narrow = l.layoutFor(0, 45);
    expect(narrow.height, 30);
    expect(narrow.offsets.map((o) => o!.dx), everyElement(0));
  });

  test('glued punctuation has no leading space', () {
    final full = _layout('aa{,} bb').layoutFor(2, 1000);
    expect(full.offsets[1]!.dx, 20);
    expect(full.offsets[2]!.dx, 40);
  });

  test('RTL flows right to left from the trailing edge', () {
    final l = _layout('שלום עולם', dir: TextDirection.rtl);
    final layout = l.layoutFor(0, 200);
    expect(layout.offsets[0]!.dx, greaterThan(layout.offsets[1]!.dx));
    expect(layout.offsets[0]!.dx + l.painters[0].width, closeTo(200, 0.01));
  });

  test('paragraph gap, with empty paragraphs collapsed', () {
    final l = _layout('aa\n[bb]\ncc');
    final brief = l.layoutFor(0, 1000);
    expect(brief.offsets[4]!.dy, 16);
    expect(brief.height, 26);
    final medium = l.layoutFor(1, 1000);
    expect(medium.offsets[4]!.dy, 32);
    expect(medium.height, 42);
  });

  test('dropped words are hidden above their maxLevel', () {
    final l = LeveledTextLayout(
      LeveledText.fromVersions(const ['aa bb', 'aa cc']),
      style: _style,
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
    final bb = l.text.tokens.indexWhere((t) => t.text == 'bb');
    final cc = l.text.tokens.indexWhere((t) => t.text == 'cc');
    expect(l.layoutFor(0, 1000).offsets[bb], isNotNull);
    expect(l.layoutFor(0, 1000).offsets[cc], isNull);
    expect(l.layoutFor(1, 1000).offsets[bb], isNull);
    expect(l.layoutFor(1, 1000).offsets[cc]!.dx, 30);
  });

  test('knows which levels rewrite words', () {
    LeveledTextLayout make(LeveledText t) => LeveledTextLayout(
          t,
          style: _style,
          textScaler: TextScaler.noScaling,
          textDirection: TextDirection.ltr,
        );
    expect(
      make(LeveledText.fromVersions(const ['a b', 'a b c', 'a x c']))
          .rewrittenLevels,
      {2},
    );
    expect(make(LeveledText.parse('a [b] {c}')).rewrittenLevels, isEmpty);
  });

  test('caches per level and width', () {
    final l = _layout('aa [bb]');
    expect(identical(l.layoutFor(1, 100), l.layoutFor(1, 100)), isTrue);
    expect(identical(l.layoutFor(1, 100), l.layoutFor(1, 90)), isFalse);
  });
}
