import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

// Ahem test font: every glyph is a square of side fontSize.
const _style = TextStyle(fontSize: 10, height: 1);

LeveledTextLayout _layout(
  LeveledText text, {
  TextAlign textAlign = TextAlign.start,
  int? maxLines,
  TextOverflow overflow = TextOverflow.clip,
  TextDirection dir = TextDirection.ltr,
}) =>
    LeveledTextLayout(
      text,
      style: _style,
      textScaler: TextScaler.noScaling,
      textDirection: dir,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final short = LeveledText.parse('aa [bb]');
  // 7 words of 4 letters: 3 per 150 px line.
  final long = LeveledText.parse('aaaa bbbb cccc [dddd eeee] {ffff gggg}');
  int indexOf(LeveledText t, String word) =>
      t.tokens.indexWhere((k) => k.text == word);

  group('textAlign', () {
    test('center', () {
      final l = _layout(short, textAlign: TextAlign.center);
      // "aa" is 20 px wide in 100 px: starts at 40.
      expect(l.layoutFor(0, 100).offsets[0]!.dx, 40);
      // "aa bb" is 50 px: starts at 25.
      expect(l.layoutFor(1, 100).offsets[0]!.dx, 25);
    });

    test('end, in left-to-right text', () {
      final l = _layout(short, textAlign: TextAlign.end);
      expect(l.layoutFor(1, 100).offsets[1]!.dx + 20, 100);
    });

    test('justify spreads all lines but the last', () {
      final l = _layout(long, textAlign: TextAlign.justify);
      final layout = l.layoutFor(2, 150);
      final c = indexOf(long, 'cccc');
      expect(layout.offsets[c]!.dx + 40, closeTo(150, 0.01));
    });

    test('start is the default and unchanged', () {
      final l = _layout(short);
      expect(l.layoutFor(1, 100).offsets[0]!.dx, 0);
    });
  });

  group('maxLines', () {
    test('clip hides words past the limit and caps the height', () {
      final l = _layout(long, maxLines: 2);
      final full = l.layoutFor(2, 150);
      expect(full.height, 20);
      expect(full.offsets[indexOf(long, 'ffff')], isNotNull);
      expect(full.offsets[indexOf(long, 'gggg')], isNull);
      expect(full.ellipsis, isNull);
    });

    test('ellipsis ends the last line with "…" after a whole word', () {
      final l = _layout(long, maxLines: 2, overflow: TextOverflow.ellipsis);
      final full = l.layoutFor(2, 150);
      expect(full.height, 20);
      final e = full.ellipsis!;
      expect(e.dy, 10, reason: 'on the second line');
      final kept = [
        for (var i = 0; i < long.tokens.length; i++)
          if (full.offsets[i] != null) long.tokens[i].text,
      ];
      expect(kept.last, isNot('gggg'));
      final last = indexOf(long, kept.last);
      expect(e.dx, full.offsets[last]!.dx + 40, reason: 'right after it');
      expect(e.dx + 10, lessThanOrEqualTo(150), reason: 'fits the line');
    });

    test('no ellipsis when the text fits', () {
      final l = _layout(long, maxLines: 2, overflow: TextOverflow.ellipsis);
      expect(l.layoutFor(0, 150).ellipsis, isNull);
      expect(l.layoutFor(0, 150).height, 10);
    });

    test('ellipsis on the left in right-to-left text', () {
      final t = LeveledText.parse('אאאא בבבב גגגג דדדד הההה וווו');
      final l = _layout(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        dir: TextDirection.rtl,
      );
      final layout = l.layoutFor(0, 150);
      final e = layout.ellipsis!;
      final kept = [
        for (var i = 0; i < t.tokens.length; i++)
          if (layout.offsets[i] != null) layout.offsets[i]!.dx,
      ];
      expect(e.dx, lessThan(kept.reduce((a, b) => a < b ? a : b)));
    });
  });

  group('in a view', () {
    testWidgets('morphs between truncated levels without errors',
        (tester) async {
      late SemanticZoomController zoom;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              child: _Host((z) {
                zoom = z;
                return LeveledTextView(
                  long,
                  controller: z,
                  key: const Key('v'),
                  style: _style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                );
              }),
            ),
          ),
        ),
      );
      for (var v = 0.0; v <= 2.0; v += 0.1) {
        zoom.value = v;
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const Key('v'))).height,
          lessThanOrEqualTo(20.001),
        );
      }
    });

    testWidgets('screen readers still get the whole text', (tester) async {
      final handle = tester.ensureSemantics();
      late SemanticZoomController zoom;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              child: _Host((z) {
                zoom = z;
                return LeveledTextView(
                  long,
                  controller: z,
                  style: _style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              }),
            ),
          ),
        ),
      );
      zoom.jumpToLevel(2);
      await tester.pump();
      expect(find.bySemanticsLabel(long.textAt(2)), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ExpandableLeveledText passes them on', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              child: ExpandableLeveledText(
                long,
                style: _style,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
      final view = tester.widget<LeveledTextView>(find.byType(LeveledTextView));
      expect(view.textAlign, TextAlign.center);
      expect(view.maxLines, 1);
      expect(view.overflow, TextOverflow.ellipsis);
    });
  });
}

class _Host extends StatefulWidget {
  const _Host(this.build);
  final Widget Function(SemanticZoomController) build;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(vsync: this);

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(zoom);
}
