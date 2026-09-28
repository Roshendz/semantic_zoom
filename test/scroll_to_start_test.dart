import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _text = LeveledText.parse(
  'Message [with a medium summary that wraps onto a few lines of text] '
  '{and the full detailed notes that go on for quite a while longer, '
  'adding several more lines to every single entry in the list.}',
);

class _List extends StatefulWidget {
  const _List({required this.reverse, required this.header});
  final bool reverse;
  final bool header;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(vsync: this);
  final scroll = ScrollController();

  @override
  void dispose() {
    zoom.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SemanticZoomDetector(
            controller: zoom,
            builder: (context, pinching) => CustomScrollView(
              controller: scroll,
              reverse: widget.reverse,
              physics: const ClampingScrollPhysics(),
              slivers: [
                if (widget.header)
                  const SliverToBoxAdapter(
                    child: SizedBox(key: ValueKey('header'), height: 120),
                  ),
                SliverSemanticZoomList.builder(
                  controller: zoom,
                  itemCount: 40,
                  itemBuilder: (c, i) => Padding(
                    key: ValueKey('i$i'),
                    padding: const EdgeInsets.all(8),
                    child: LeveledTextView(_text, itemId: i),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

void main() {
  Future<_ListState> zoomFarDown(
    WidgetTester tester, {
    bool reverse = false,
    bool header = false,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_List(reverse: reverse, header: header));
    final s = tester.state<_ListState>(find.byType(_List));
    s.scroll.jumpTo(300);
    await tester.pump();
    // A pinch in the middle: anchoring scrolls far while items above the
    // screen grow unseen, which leaves the list's estimates stale.
    s.zoom.beginGesture(const Offset(200, 300));
    for (var z = 0.0; z <= 2.0; z += 0.1) {
      s.zoom.value = z;
      await tester.pump();
    }
    unawaited(s.zoom.endGesture(projected: 2));
    await tester.pumpAndSettle();
    expect(s.scroll.offset, greaterThan(1000), reason: 'setup');
    return s;
  }

  bool built(int i) => find.byKey(ValueKey('i$i')).evaluate().isNotEmpty;

  for (final reverse in [false, true]) {
    final start = reverse ? 'bottom' : 'top';

    testWidgets('jumpTo(0) after a pinch lands exactly at the $start',
        (tester) async {
      final s = await zoomFarDown(tester, reverse: reverse);
      s.scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(s.scroll.offset, 0);
      expect(built(0), isTrue);
      final item0 = tester.getRect(find.byKey(const ValueKey('i0')));
      expect(reverse ? item0.bottom : item0.top, closeTo(reverse ? 600 : 0, 1));
    });

    testWidgets('animateTo(0) after a pinch lands exactly at the $start',
        (tester) async {
      final s = await zoomFarDown(tester, reverse: reverse);
      unawaited(
        s.scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        ),
      );
      await tester.pumpAndSettle();
      expect(s.scroll.offset, 0);
      expect(built(0), isTrue);
    });
  }

  testWidgets('with a header above the list, jumpTo(0) shows the header',
      (tester) async {
    final s = await zoomFarDown(tester, header: true);
    s.scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(s.scroll.offset, 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey('header'))).dy, 0);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('i0'))).dy,
      closeTo(120, 1),
    );
  });

  testWidgets('slow scrolling up to the top never jumps', (tester) async {
    final s = await zoomFarDown(tester);
    // Drag up 30 px per frame and follow one item: it must move by the
    // drag distance every frame, never skip.
    final gesture = await tester.startGesture(const Offset(200, 100));
    var guard = 0;
    while (s.scroll.offset > 0 && guard++ < 400) {
      final tracked = List.generate(40, (i) => i).firstWhere(built);
      final before = tester.getTopLeft(find.byKey(ValueKey('i$tracked'))).dy;
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
      if (!built(tracked)) continue;
      final after = tester.getTopLeft(find.byKey(ValueKey('i$tracked'))).dy;
      expect(
        after - before,
        lessThanOrEqualTo(30.5),
        reason: 'item $tracked jumped at offset ${s.scroll.offset}',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(s.scroll.offset, 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey('i0'))).dy, 0);
  });

  testWidgets('already consistent lists are untouched', (tester) async {
    // No pinch: estimates are exact, so going to the start must behave
    // exactly as a plain list.
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _List(reverse: false, header: false));
    final s = tester.state<_ListState>(find.byType(_List));
    s.scroll.jumpTo(2000);
    await tester.pump();
    s.scroll.jumpTo(0);
    await tester.pump();
    expect(s.scroll.offset, 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey('i0'))).dy, 0);
  });
}
