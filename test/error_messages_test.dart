import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

void main() {
  testWidgets('a view without a controller explains how to fix it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LeveledTextView(LeveledText.parse('a [b]'))),
      ),
    );
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    final message = error.toString();
    expect(message, contains('No SemanticZoomController found'));
    expect(message, contains('controller: zoom'));
    expect(message, contains('ExpandableLeveledText'));
  });

  testWidgets('too few controller levels prints a hint once, in debug',
      (tester) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultSemanticZoomController(
              levelCount: 2,
              builder: (context, zoom) => Column(
                children: [
                  LeveledTextView(
                    LeveledText.parse('a [b] {c}'),
                    controller: zoom,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    } finally {
      debugPrint = original;
    }
    final hints = printed.where((m) => m.contains('levelCount: 3')).toList();
    expect(hints, hasLength(1));
    expect(hints.single, contains('has 3 levels'));
  });

  testWidgets('no hint when the levels match', (tester) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultSemanticZoomController(
              builder: (context, zoom) => LeveledTextView(
                LeveledText.parse('a [b] {c}'),
                controller: zoom,
              ),
            ),
          ),
        ),
      );
    } finally {
      debugPrint = original;
    }
    expect(printed.where((m) => m.contains('semantic_zoom')), isEmpty);
  });
}
