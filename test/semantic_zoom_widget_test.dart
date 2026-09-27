import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

// Each item grows a lot between levels so anchoring errors are obvious.
final _text = LeveledText.parse(
  'Title [with a medium summary that wraps onto a few lines of text] '
  '{and the full detailed notes that go on for quite a while longer, '
  'adding several more lines to every single entry in the list.}',
);

class _Harness extends StatefulWidget {
  const _Harness({required this.onController, this.itemCount = 40});
  final ValueChanged<SemanticZoomController> onController;
  final int itemCount;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  late final controller = SemanticZoomController(vsync: this);
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.onController(controller);
  }

  @override
  void dispose() {
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 600)),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
            child: SemanticZoomListView.builder(
              controller: controller,
              scrollController: scroll,
              physics: const ClampingScrollPhysics(),
              itemCount: widget.itemCount,
              itemBuilder: (context, i) => Padding(
                key: ValueKey('item-$i'),
                padding: const EdgeInsets.only(bottom: 16),
                child: LeveledTextView(_text, itemId: i),
              ),
            ),
          ),
        ),
      );
}

void main() {
  late SemanticZoomController controller;

  Future<ScrollController> pump(WidgetTester tester, {int items = 40}) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _Harness(onController: (c) => controller = c, itemCount: items),
    );
    return tester.state<_HarnessState>(find.byType(_Harness)).scroll;
  }

  double topOf(WidgetTester tester, int i) =>
      tester.getTopLeft(find.byKey(ValueKey('item-$i'))).dy;

  RenderSliverSemanticZoomList sliver(WidgetTester tester) =>
      tester.renderObject<RenderSliverSemanticZoomList>(
        find.byType(SliverSemanticZoomList),
      );

  testWidgets('pinch anchor holds the item still on every frame',
      (tester) async {
    final scroll = await pump(tester);
    scroll.jumpTo(400);
    await tester.pump();

    // Pick an item whose top is mid-screen, well below other items.
    final probe = List.generate(40, (i) => i).firstWhere(
      (i) =>
          find.byKey(ValueKey('item-$i')).evaluate().isNotEmpty &&
          topOf(tester, i) > 250,
    );
    final before = topOf(tester, probe);
    final focal = tester.getCenter(find.byKey(ValueKey('item-$probe')));

    controller.beginGesture(focal);
    expect(sliver(tester).anchorIndex, probe);

    for (var z = 0.0; z <= 2.0; z += 0.05) {
      controller.value = z;
      await tester.pump();
      expect(topOf(tester, probe), closeTo(before, 1), reason: 'z=$z');
    }

    unawaited(controller.endGesture(projected: 2));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(topOf(tester, probe), closeTo(before, 1), reason: 'settle $i');
    }
    await tester.pumpAndSettle();
    expect(controller.level, 2);
    expect(sliver(tester).anchorIndex, isNull);
  });

  testWidgets('animateToLevel anchors the first visible item', (tester) async {
    final scroll = await pump(tester);
    scroll.jumpTo(700);
    await tester.pump();

    final s = sliver(tester);
    controller.animateToLevel(2);
    final anchored = s.anchorIndex!;
    final before = topOf(tester, anchored);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(topOf(tester, anchored), closeTo(before, 1));
    }
    await tester.pumpAndSettle();
    expect(controller.level, 2);
  });

  testWidgets('never corrects before the start of the list', (tester) async {
    final scroll = await pump(tester);
    controller.beginGesture(const Offset(200, 5));
    controller.value = 2;
    await tester.pump();
    controller.value = 0;
    await tester.pump();
    expect(scroll.offset, greaterThanOrEqualTo(0));
  });

  testWidgets('two-finger pinch changes level and blocks scrolling',
      (tester) async {
    await pump(tester);
    final a = await tester.startGesture(const Offset(200, 250));
    final b = await tester.startGesture(const Offset(200, 290));
    await tester.pump();
    final anchored = sliver(tester).anchorIndex!;
    final before = topOf(tester, anchored);
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(Offset(200, 250 - i * 15.0));
      await b.moveTo(Offset(200, 290 + i * 15.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.value, greaterThan(1.5));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(controller.level, 2);
    // The list scrolled to keep the item under the fingers still, instead of
    // following the finger drag.
    expect(topOf(tester, anchored), closeTo(before, 1));
  });

  testWidgets('trackpad pinch zooms; trackpad scroll does not', (tester) async {
    final scroll = await pump(tester);
    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);

    await pad.panZoomStart(const Offset(200, 300));
    await pad.panZoomUpdate(const Offset(200, 300), pan: const Offset(0, -80));
    await tester.pump();
    expect(controller.value, 0, reason: 'plain two-finger scroll');
    await pad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));

    await pad.panZoomStart(const Offset(200, 300));
    for (var s = 1.1; s <= 2.6; s += 0.1) {
      await pad.panZoomUpdate(const Offset(200, 300), scale: s);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(controller.level, 2);
  });

  testWidgets('reduce motion jumps instead of animating', (tester) async {
    await pump(tester);
    controller.reduceMotion = true;
    unawaited(controller.animateToLevel(1));
    expect(controller.value, 1);
    expect(controller.isAnimating, isFalse);
  });

  testWidgets('notifies only when the committed level changes', (tester) async {
    await pump(tester);
    var calls = 0;
    controller.addListener(() => calls++);
    controller.value = 0.7; // per-frame value: no notification
    expect(calls, 0);
    unawaited(controller.animateToLevel(1));
    unawaited(controller.animateToLevel(1));
    expect(calls, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('screen readers get text at the nearest level', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, items: 1);
    expect(find.bySemanticsLabel(_text.textAt(0)), findsOneWidget);
    controller.value = 1.6;
    await tester.pump();
    expect(find.bySemanticsLabel(_text.textAt(2)), findsOneWidget);
    handle.dispose();
  });

  group('per-item zoom', () {
    double heightOf(WidgetTester tester, int i) =>
        tester.getSize(find.byKey(ValueKey('item-$i'))).height;

    testWidgets('expands one item and leaves the others', (tester) async {
      await pump(tester);
      final h0 = heightOf(tester, 0), h1 = heightOf(tester, 1);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.setItemLevel(0, 2);
      await tester.pumpAndSettle();

      expect(controller.itemLevel(0), 2);
      expect(controller.itemLevel(1), 0);
      expect(controller.level, 0);
      expect(heightOf(tester, 0), greaterThan(h0));
      expect(heightOf(tester, 1), h1);
      expect(notified, 1);
    });

    testWidgets('a global level change pulls items back', (tester) async {
      await pump(tester);
      controller.setItemLevel(0, 2);
      await tester.pumpAndSettle();
      final expanded = heightOf(tester, 0);

      controller.animateToLevel(1);
      await tester.pumpAndSettle();
      expect(controller.hasItemLevels, isFalse);
      expect(controller.itemLevel(0), 1);
      expect(heightOf(tester, 0), lessThan(expanded));
      expect(heightOf(tester, 0), heightOf(tester, 1));
    });

    testWidgets('a pinch clears item levels', (tester) async {
      await pump(tester);
      controller.setItemLevel(3, 2);
      await tester.pumpAndSettle();
      controller.beginGesture(const Offset(200, 300));
      await tester.pumpAndSettle();
      expect(controller.hasItemLevels, isFalse);
      unawaited(controller.endGesture(projected: 0));
      await tester.pumpAndSettle();
    });

    testWidgets('expanding an item keeps the first visible item still',
        (tester) async {
      final scroll = await pump(tester);
      scroll.jumpTo(500);
      await tester.pump();
      final s = sliver(tester);
      // Expand an item that is partly above the viewport.
      final first = List.generate(40, (i) => i).firstWhere(
        (i) =>
            find.byKey(ValueKey('item-$i')).evaluate().isNotEmpty &&
            topOf(tester, i) + heightOf(tester, i) > 0,
      );
      final pinnedTop = topOf(tester, first);
      final belowBefore = topOf(tester, first + 1);
      controller.setItemLevel(first, 2);
      expect(s.anchorIndex, first);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(topOf(tester, first), closeTo(pinnedTop, 1), reason: 'f$i');
      }
      await tester.pumpAndSettle();
      expect(s.anchorIndex, isNull);
      expect(topOf(tester, first + 1), greaterThan(belowBefore));
    });
  });

  testWidgets('screen reader increase/decrease adjusts the item',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, items: 2);
    final node = tester.getSemantics(
      find.descendant(
        of: find.byKey(const ValueKey('item-0')),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(node.value, 'Detail 1 of 3');
    expect(node.increasedValue, 'Detail 2 of 3');

    node.owner!.performAction(node.id, SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(controller.itemLevel(0), 1);
    expect(controller.itemLevel(1), 0);
    handle.dispose();
  });

  testWidgets('Ctrl/Cmd +, - and 0 change the level once focused',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('item-0')));
    await tester.pump();

    Future<void> press(LogicalKeyboardKey key, {bool meta = false}) async {
      final mod =
          meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(mod);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.equal);
    expect(controller.level, 1);
    await press(LogicalKeyboardKey.equal, meta: true);
    expect(controller.level, 2);
    await press(LogicalKeyboardKey.minus);
    expect(controller.level, 1);
    await press(LogicalKeyboardKey.digit0);
    expect(controller.level, 0);
  });
}
