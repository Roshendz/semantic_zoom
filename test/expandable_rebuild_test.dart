import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

// Regressions found in 0.2.0: rebuilding with new levels or labels crashed
// with "multiple tickers were created".
void main() {
  Widget app(LeveledText text, {List<String>? labels, Key? key}) => MaterialApp(
        home: Scaffold(
          body: ExpandableLeveledText(text, key: key, levelLabels: labels),
        ),
      );

  testWidgets('a new, equal levelLabels list on every build is fine',
      (tester) async {
    final key = GlobalKey<ExpandableLeveledTextState>();
    final text = LeveledText.parse('a [b] {c}');
    await tester.pumpWidget(app(text, labels: ['A', 'B', 'C'], key: key));
    key.currentState!.expand();
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(text, labels: ['A', 'B', 'C'], key: key));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(key.currentState!.level, 2, reason: 'level kept');
  });

  testWidgets('text with a different number of levels', (tester) async {
    final key = GlobalKey<ExpandableLeveledTextState>();
    await tester.pumpWidget(app(LeveledText.parse('a [b] {c}'), key: key));
    await tester.pumpWidget(app(LeveledText.parse('a [b]'), key: key));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(key.currentState!.maxLevel, 1);
    await tester.pumpWidget(app(LeveledText.parse('a [b] {c}'), key: key));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(key.currentState!.maxLevel, 2);
  });

  testWidgets('different labels still take effect', (tester) async {
    final handle = tester.ensureSemantics();
    final text = LeveledText.parse('a [b] {c}');
    await tester.pumpWidget(app(text, labels: ['A', 'B', 'C']));
    await tester.pumpWidget(app(text, labels: ['X', 'Y', 'Z']));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSemantics(find.bySemanticsLabel('a')).value, 'X');
    handle.dispose();
  });
}
