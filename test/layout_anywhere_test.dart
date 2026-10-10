import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

// LeveledTextView should work anywhere Text works.

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

final _text = LeveledText.parse(
  'Short [and a longer summary] {with the full details at the end.}',
);

final _layouts = <String, Widget Function(Widget)>{
  'Row without Expanded': (w) => Row(children: [w]),
  'Row with Flexible': (w) => Row(children: [Flexible(child: w)]),
  'IntrinsicHeight': (w) =>
      IntrinsicHeight(child: Row(children: [Expanded(child: w)])),
  'IntrinsicWidth': (w) => IntrinsicWidth(child: w),
  'horizontal ListView': (w) => SizedBox(
        height: 200,
        child: ListView(scrollDirection: Axis.horizontal, children: [w]),
      ),
  'Chip label': (w) => Wrap(children: [Chip(label: w)]),
  'Wrap': (w) => Wrap(children: [w]),
  'UnconstrainedBox': (w) => UnconstrainedBox(child: w),
  'Table cell': (w) => Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(children: [w])
        ],
      ),
  'Stack, unpositioned': (w) => Stack(children: [w]),
  'ListTile title': (w) => ListTile(title: w, trailing: const Icon(Icons.star)),
};

void main() {
  for (final MapEntry(key: name, value: wrap) in _layouts.entries) {
    testWidgets('works in: $name', (tester) async {
      late SemanticZoomController zoom;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Host((z) {
              zoom = z;
              // Small enough that even the full text fits on the screen,
              // so nothing overflows (Text would overflow too otherwise).
              return wrap(
                LeveledTextView(
                  _text,
                  controller: z,
                  key: const Key('v'),
                  style: const TextStyle(fontSize: 10),
                ),
              );
            }),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final brief = tester.getSize(find.byKey(const Key('v')));
      expect(brief.width, greaterThan(0));
      expect(brief.width.isFinite, isTrue);

      zoom.jumpToLevel(2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final full = tester.getSize(find.byKey(const Key('v')));
      // More text never takes less room. (It may take the same room when
      // the full text still fits on one line of a bounded width.)
      expect(full.width, greaterThanOrEqualTo(brief.width));
      expect(full.height, greaterThanOrEqualTo(brief.height));
    });
  }

  testWidgets('with unbounded width it is as wide as its text', (tester) async {
    late SemanticZoomController zoom;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Host((z) {
            zoom = z;
            return Row(
              children: [
                LeveledTextView(_text, controller: z, key: const Key('v')),
              ],
            );
          }),
        ),
      ),
    );
    final brief = tester.getSize(find.byKey(const Key('v'))).width;
    zoom.value = 0.5;
    await tester.pump();
    final half = tester.getSize(find.byKey(const Key('v'))).width;
    zoom.value = 1;
    await tester.pump();
    final medium = tester.getSize(find.byKey(const Key('v'))).width;
    expect(brief, lessThan(half));
    expect(half, lessThan(medium), reason: 'width animates with the level');
  });

  testWidgets('in bounded width it still fills it, as before', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Host(
            (z) => Center(
              child: SizedBox(
                width: 300,
                child:
                    LeveledTextView(_text, controller: z, key: const Key('v')),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('v'))).width, 300);
  });

  testWidgets('intrinsic height follows the zoom', (tester) async {
    late SemanticZoomController zoom;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Host((z) {
            zoom = z;
            return Center(
              child: SizedBox(
                width: 120,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: LeveledTextView(_text, controller: z)),
                      const ColoredBox(
                        key: Key('side'),
                        color: Colors.red,
                        child: SizedBox(width: 10),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
    final brief = tester.getSize(find.byKey(const Key('side'))).height;
    zoom.jumpToLevel(2);
    await tester.pumpAndSettle();
    final full = tester.getSize(find.byKey(const Key('side'))).height;
    expect(full, greaterThan(brief),
        reason: 'the side bar grows with the text');
  });
}
