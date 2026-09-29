import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _text = LeveledText.parse(
  'Card [with a medium summary that wraps onto a few lines of text] '
  '{and the full detailed notes that go on for quite a while longer.}',
);

class _Grid extends StatefulWidget {
  const _Grid({
    this.count = 30,
    this.columns,
    this.maxExtent,
    this.spacing = 0,
    this.useView = true,
    this.rtl = false,
  });
  final int? count;
  final int? columns;
  final double? maxExtent;
  final double spacing;
  final bool useView;
  final bool rtl;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(vsync: this);
  final scroll = ScrollController();

  @override
  void dispose() {
    zoom.dispose();
    scroll.dispose();
    super.dispose();
  }

  Widget? _cell(BuildContext context, int i) {
    if (widget.count == null && i >= 13) return null;
    return Container(
      key: ValueKey('c$i'),
      padding: const EdgeInsets.all(4),
      child: LeveledTextView(_text, itemId: i),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: Scaffold(
          body: widget.useView
              ? SemanticZoomGridView.builder(
                  controller: zoom,
                  scrollController: scroll,
                  physics: const ClampingScrollPhysics(),
                  itemCount: widget.count,
                  crossAxisCount: widget.columns,
                  maxCrossAxisExtent: widget.maxExtent,
                  mainAxisSpacing: widget.spacing,
                  crossAxisSpacing: widget.spacing,
                  itemBuilder: _cell,
                )
              : SemanticZoomDetector(
                  controller: zoom,
                  builder: (context, pinching) => CustomScrollView(
                    controller: scroll,
                    slivers: [
                      const SliverToBoxAdapter(child: SizedBox(height: 50)),
                      SliverSemanticZoomGrid.builder(
                        controller: zoom,
                        itemCount: widget.count,
                        crossAxisCount: widget.columns ?? 2,
                        itemBuilder: _cell,
                      ),
                    ],
                  ),
                ),
        ),
      );
}

void main() {
  _GridState grid(WidgetTester t) => t.state(find.byType(_Grid));
  Rect cell(WidgetTester t, int i) => t.getRect(find.byKey(ValueKey('c$i')));
  bool built(int i) => find.byKey(ValueKey('c$i')).evaluate().isNotEmpty;

  Future<void> pump(WidgetTester tester, _Grid widget) async {
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
  }

  testWidgets('lays items out in rows of crossAxisCount', (tester) async {
    await pump(tester, const _Grid(count: 7, columns: 3, spacing: 10));
    // Row 0: items 0, 1, 2 side by side with 10 px gaps.
    const w = (400 - 2 * 10) / 3;
    for (var i = 0; i < 3; i++) {
      expect(cell(tester, i).left, closeTo(i * (w + 10), 0.5));
      expect(cell(tester, i).width, closeTo(w, 0.5));
      expect(cell(tester, i).top, cell(tester, 0).top);
    }
    // Next row starts below the tallest item of the row, plus spacing.
    expect(cell(tester, 3).top, closeTo(cell(tester, 0).bottom + 10, 0.5));
    // Last row holds only item 6, in the first column.
    expect(cell(tester, 6).left, 0);
    expect(built(7), isFalse);
  });

  testWidgets('maxCrossAxisExtent picks the columns from the width',
      (tester) async {
    await pump(tester, const _Grid(maxExtent: 150));
    // 400 px wide, at most 150 px per column -> 3 columns.
    expect(cell(tester, 2).top, cell(tester, 0).top);
    expect(cell(tester, 3).left, 0);
    tester.view.physicalSize = const Size(700, 600);
    await tester.pump();
    // 700 px -> 5 columns.
    expect(cell(tester, 4).top, cell(tester, 0).top);
    expect(cell(tester, 5).left, 0);
  });

  testWidgets('pinch keeps the row under the fingers still', (tester) async {
    await pump(tester, const _Grid(count: 80, columns: 2));
    grid(tester).scroll.jumpTo(300);
    await tester.pump();
    final probe = List.generate(80, (i) => i)
        .firstWhere((i) => built(i) && cell(tester, i).top > 250);
    final before = cell(tester, probe).top;
    final zoom = grid(tester).zoom
      ..beginGesture(tester.getCenter(find.byKey(ValueKey('c$probe'))));
    for (var z = 0.0; z <= 2.0; z += 0.1) {
      zoom.value = z;
      await tester.pump();
      expect(cell(tester, probe).top, closeTo(before, 1), reason: 'z=$z');
    }
    unawaited(zoom.endGesture(projected: 2));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(cell(tester, probe).top, closeTo(before, 1), reason: 'f$i');
    }
    await tester.pumpAndSettle();
  });

  testWidgets('one card expands; its row grows, its neighbour does not',
      (tester) async {
    await pump(tester, const _Grid(columns: 2));
    final neighbour = cell(tester, 5).height;
    grid(tester).zoom.setItemLevel(4, 2);
    await tester.pumpAndSettle();
    expect(cell(tester, 4).height, greaterThan(neighbour));
    expect(cell(tester, 5).height, neighbour, reason: 'top-aligned');
    // The next row moved down by the growth.
    expect(cell(tester, 6).top, greaterThan(cell(tester, 4).bottom - 1));
  });

  testWidgets('scroll to top after a pinch lands at the top', (tester) async {
    await pump(tester, const _Grid(count: 80, columns: 2));
    grid(tester).scroll.jumpTo(300);
    await tester.pump();
    final zoom = grid(tester).zoom..beginGesture(const Offset(200, 300));
    for (var z = 0.0; z <= 2.0; z += 0.1) {
      zoom.value = z;
      await tester.pump();
    }
    unawaited(zoom.endGesture(projected: 2));
    await tester.pumpAndSettle();
    grid(tester).scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(grid(tester).scroll.offset, 0);
    expect(cell(tester, 0).top, 0);
  });

  testWidgets('open-ended grids stop where the builder returns null',
      (tester) async {
    await pump(tester, const _Grid(count: null, columns: 3));
    grid(tester).scroll.jumpTo(10000);
    await tester.pumpAndSettle();
    expect(built(12), isTrue);
    expect(built(13), isFalse);
    // 13 items in rows of 3: item 12 starts the last row.
    expect(cell(tester, 12).left, 0);
  });

  testWidgets('the sliver works inside your own scroll view', (tester) async {
    await pump(tester, const _Grid(columns: 2, useView: false));
    expect(cell(tester, 0).top, 50);
    expect(cell(tester, 1).top, 50);
    expect(cell(tester, 1).left, 200);
  });

  testWidgets('right-to-left puts the first item on the right', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Grid(count: 4, columns: 2, rtl: true));
    expect(cell(tester, 0).left, greaterThan(cell(tester, 1).left));
  });
}
