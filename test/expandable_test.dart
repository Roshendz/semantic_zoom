import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _text = LeveledText.parse(
  'Knee review[: swelling reduced, cleared to run]'
  '{ twice a week. Keep strength exercises daily.}',
);

// InkRipple: Flutter 3.22's default InkSparkle shader can't run in tests.
Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: SizedBox(width: 300, child: child)),
      ),
    );

void main() {
  double height(WidgetTester t) =>
      t.getSize(find.byType(LeveledTextView)).height;

  testWidgets('each tap expands a level, then wraps back', (tester) async {
    final levels = <int>[];
    await tester.pumpWidget(
      _app(ExpandableLeveledText(_text, onLevelChanged: levels.add)),
    );
    final h0 = height(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(ExpandableLeveledText));
      await tester.pumpAndSettle();
    }
    expect(levels, [1, 2, 0]);
    expect(height(tester), h0);

    await tester.tap(find.byType(ExpandableLeveledText));
    await tester.pumpAndSettle();
    expect(height(tester), greaterThan(h0));
  });

  testWidgets('wrap: false stops at the last level', (tester) async {
    final key = GlobalKey<ExpandableLeveledTextState>();
    await tester.pumpWidget(
      _app(ExpandableLeveledText(_text, key: key, wrap: false)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(ExpandableLeveledText));
      await tester.pumpAndSettle();
    }
    expect(key.currentState!.level, 2);
    expect(key.currentState!.isExpanded, isTrue);
    key.currentState!.collapse();
    await tester.pumpAndSettle();
    expect(key.currentState!.level, 0);
  });

  testWidgets('footer builder gets the level and a toggle', (tester) async {
    await tester.pumpWidget(
      _app(
        ExpandableLeveledText(
          _text,
          expandOnTap: false,
          footerBuilder: (context, level, max, toggle) => TextButton(
            onPressed: toggle,
            child: Text(level < max ? 'Show more' : 'Show less'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('levels default to what the text uses', (tester) async {
    final key = GlobalKey<ExpandableLeveledTextState>();
    await tester.pumpWidget(
      _app(
        ExpandableLeveledText(
          LeveledText.parse('Title[ and summary]'),
          key: key,
        ),
      ),
    );
    expect(key.currentState!.maxLevel, 1);
  });

  testWidgets('reduce motion jumps without animating', (tester) async {
    await tester.pumpWidget(
      _app(ExpandableLeveledText(_text), reduceMotion: true),
    );
    final h0 = height(tester);
    await tester.tap(find.byType(ExpandableLeveledText));
    await tester.pump();
    expect(height(tester), greaterThan(h0));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('screen readers get the text, a tap action and a hint',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(ExpandableLeveledText(_text)));
    SemanticsNode node() =>
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Knee review')));
    SemanticsData data() => node().getSemanticsData();

    expect(data().hasAction(SemanticsAction.tap), isTrue);
    expect(node().hintOverrides?.onTapHint, 'Show more');

    await tester.tap(find.byType(ExpandableLeveledText));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpandableLeveledText));
    await tester.pumpAndSettle();
    expect(data().label, contains('strength exercises'));
    expect(node().hintOverrides?.onTapHint, 'Show less');
    handle.dispose();
  });
}
