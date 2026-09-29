import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

// Regression: on a short list, zooming out after a zoom in could leave the
// anchored position past the new end of the content. The scroll physics
// pulled it back, the anchor pushed it forward, and layout never settled
// ("RenderViewport exceeded its maximum number of layout cycles").

final _texts = [
  for (var i = 0; i < 6; i++)
    LeveledText.parse(
      'Entry $i title [with a medium summary that wraps onto a few lines of '
      'text on a phone] {and the full detailed notes that go on for quite a '
      'while longer, adding several more lines to every single entry.}',
    ),
];

class _Short extends StatefulWidget {
  const _Short({required this.physics, required this.header});
  final ScrollPhysics physics;
  final bool header;

  @override
  State<_Short> createState() => _ShortState();
}

class _ShortState extends State<_Short> with SingleTickerProviderStateMixin {
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
              physics: pinching
                  ? const NeverScrollableScrollPhysics()
                  : widget.physics,
              slivers: [
                if (widget.header)
                  const SliverToBoxAdapter(child: SizedBox(height: 180)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverSemanticZoomList.builder(
                    controller: zoom,
                    itemCount: _texts.length,
                    itemBuilder: (context, i) => Padding(
                      key: ValueKey('e$i'),
                      padding: const EdgeInsets.only(top: 22),
                      child: LeveledTextView(_texts[i], itemId: i),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

void main() {
  for (final (name, physics) in [
    ('clamping', const ClampingScrollPhysics()),
    ('bouncing', const BouncingScrollPhysics()),
  ]) {
    for (final header in [true, false]) {
      testWidgets('$name physics, header: $header — zoom in, then back out',
          (tester) async {
        // Phone-sized: 393 x 604 logical pixels of list.
        tester.view
          ..physicalSize = const Size(1179, 1812)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_Short(physics: physics, header: header));
        final state = tester.state<_ShortState>(find.byType(_Short));
        final list = tester.getRect(find.byType(CustomScrollView));

        // Pinch out in the middle: anchoring scrolls forward.
        final c = list.center;
        const axis = Offset(0.55, 0.835);
        final a = await tester.startGesture(c - axis * 30);
        final b = await tester.startGesture(c + axis * 30);
        for (var i = 1; i <= 30; i++) {
          await a.moveTo(c - axis * (30 + i * 5.0));
          await b.moveTo(c + axis * (30 + i * 5.0));
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: 'pinch step $i');
        }
        await a.up();
        await b.up();
        await tester.pumpAndSettle();
        expect(state.zoom.level, 2);

        // Back to brief with the buttons: the content shrinks below the
        // anchored position.
        unawaited(state.zoom.animateToLevel(0));
        for (var f = 0; f < 60; f++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: 'frame $f');
        }
        await tester.pumpAndSettle();
        final pos = state.scroll.position;
        expect(pos.pixels, lessThanOrEqualTo(pos.maxScrollExtent + 0.5));
        expect(pos.pixels, greaterThanOrEqualTo(pos.minScrollExtent - 0.5));

        // And a pinch in straight after, near the end of the content.
        final a2 = await tester.startGesture(c - axis * 150);
        final b2 = await tester.startGesture(c + axis * 150);
        for (var i = 1; i <= 30; i++) {
          await a2.moveTo(c - axis * (150 - i * 4.0));
          await b2.moveTo(c + axis * (150 - i * 4.0));
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: 'pinch in $i');
        }
        await a2.up();
        await b2.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('far from the end, anchoring is unchanged', (tester) async {
    // Long list: the new limit never applies, the anchored entry stays put.
    tester.view
      ..physicalSize = const Size(1179, 1812)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late SemanticZoomController zoom;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Holder((z) {
            zoom = z;
            return SemanticZoomListView.builder(
              controller: z,
              scrollController: scroll,
              itemCount: 200,
              itemBuilder: (context, i) => Padding(
                key: ValueKey('l$i'),
                padding: const EdgeInsets.all(8),
                child: LeveledTextView(_texts[i % 6], itemId: i),
              ),
            );
          }),
        ),
      ),
    );
    scroll.jumpTo(3000);
    await tester.pump();
    zoom.beginGesture(const Offset(196, 300));
    final sliver = tester.renderObject<RenderSliverSemanticZoomList>(
      find.byType(SliverSemanticZoomList),
    );
    final pinned = sliver.anchorIndex!;
    final before = tester.getTopLeft(find.byKey(ValueKey('l$pinned'))).dy;
    for (var v = 0.0; v <= 2.0; v += 0.1) {
      zoom.value = v;
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(ValueKey('l$pinned'))).dy,
        closeTo(before, 1),
      );
    }
    unawaited(zoom.endGesture(projected: 2));
    await tester.pumpAndSettle();
  });
}

class _Holder extends StatefulWidget {
  const _Holder(this.build);
  final Widget Function(SemanticZoomController) build;

  @override
  State<_Holder> createState() => _HolderState();
}

class _HolderState extends State<_Holder> with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(vsync: this);

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(zoom);
}
