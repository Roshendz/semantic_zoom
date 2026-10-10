import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _texts = [
  for (var i = 0; i < 20; i++)
    LeveledText.parse('Entry $i [with a summary] {and the full notes.}'),
];

Widget _app({
  int levelCount = 3,
  int initialLevel = 0,
  ValueChanged<int>? onLevelChanged,
}) =>
    MaterialApp(
      home: Scaffold(
        body: DefaultSemanticZoomController(
          levelCount: levelCount,
          initialLevel: initialLevel,
          onLevelChanged: onLevelChanged,
          builder: (context, zoom) => Column(
            children: [
              Expanded(
                child: SemanticZoomListView.builder(
                  controller: zoom,
                  itemCount: _texts.length,
                  itemBuilder: (context, i) => Padding(
                    key: ValueKey('i$i'),
                    padding: const EdgeInsets.all(8),
                    child: LeveledTextView(_texts[i], itemId: i),
                  ),
                ),
              ),
              const _Buttons(),
            ],
          ),
        ),
      ),
    );

/// Finds the controller from context, as a real app's buttons would.
class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    final zoom = DefaultSemanticZoomController.of(context);
    return ListenableBuilder(
      listenable: zoom,
      builder: (context, _) => Row(
        children: [
          for (var level = 0; level < zoom.levelCount; level++)
            TextButton(
              onPressed: () => zoom.animateToLevel(level),
              child: Text(level == zoom.level ? '[$level]' : '$level'),
            ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('works with no controller code of your own', (tester) async {
    tester.view
      ..physicalSize = const Size(300, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    final brief = tester.getSize(find.byKey(const ValueKey('i0'))).height;
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('[2]'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('i0'))).height,
      greaterThan(brief),
    );
  });

  testWidgets('initialLevel and onLevelChanged', (tester) async {
    final changes = <int>[];
    await tester.pumpWidget(
      _app(initialLevel: 1, onLevelChanged: changes.add),
    );
    expect(find.text('[1]'), findsOneWidget);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0'));
    await tester.pumpAndSettle();
    expect(changes, [2, 0]);
  });

  testWidgets('a new levelCount keeps the level where possible',
      (tester) async {
    await tester.pumpWidget(_app(initialLevel: 2));
    await tester.pumpWidget(_app(levelCount: 4, initialLevel: 2));
    await tester.pumpAndSettle();
    expect(find.text('[2]'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'four levels now');
    await tester.pumpWidget(_app(levelCount: 2, initialLevel: 2));
    await tester.pumpAndSettle();
    expect(find.text('[1]'), findsOneWidget, reason: 'clamped to the top');
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes its controller', (tester) async {
    late SemanticZoomController zoom;
    await tester.pumpWidget(
      DefaultSemanticZoomController(
        builder: (context, z) {
          zoom = z;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(() => zoom.addListener(() {}), throwsFlutterError);
  });

  testWidgets('maybeOf is null without one', (tester) async {
    SemanticZoomController? found;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          found = DefaultSemanticZoomController.maybeOf(context);
          return const SizedBox();
        },
      ),
    );
    expect(found, isNull);
  });
}
