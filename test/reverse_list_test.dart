import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _text = LeveledText.parse(
  'Message [with a medium summary that wraps onto a few lines of text] '
  '{and the full detailed notes that go on for quite a while longer, '
  'adding several more lines to every single entry in the list.}',
);

class _Chat extends StatefulWidget {
  const _Chat({
    required this.onController,
    this.useListView = false,
  });
  final ValueChanged<SemanticZoomController> onController;
  final bool useListView;

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> with SingleTickerProviderStateMixin {
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

  Widget _item(BuildContext context, int i) => SizedBox(
        key: ValueKey('msg-$i'),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LeveledTextView(_text, itemId: i),
        ),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: widget.useListView
              ? SemanticZoomListView.builder(
                  controller: controller,
                  scrollController: scroll,
                  reverse: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: 40,
                  itemBuilder: _item,
                )
              : SemanticZoomDetector(
                  controller: controller,
                  builder: (context, pinching) => CustomScrollView(
                    controller: scroll,
                    reverse: true,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      SliverSemanticZoomList.builder(
                        controller: controller,
                        itemCount: 40,
                        itemBuilder: _item,
                      ),
                    ],
                  ),
                ),
        ),
      );
}

void main() {
  late SemanticZoomController controller;

  Future<ScrollController> pump(
    WidgetTester tester, {
    bool useListView = false,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _Chat(
        onController: (c) => controller = c,
        useListView: useListView,
      ),
    );
    return tester.state<_ChatState>(find.byType(_Chat)).scroll;
  }

  Offset edge(WidgetTester tester, int i) =>
      tester.getBottomLeft(find.byKey(ValueKey('msg-$i')));

  RenderSliverSemanticZoomList sliver(WidgetTester tester) =>
      tester.renderObject(find.byType(SliverSemanticZoomList));

  /// A message whose bottom edge sits in the middle of the screen.
  int middleMessage(WidgetTester tester) =>
      List.generate(40, (i) => i).firstWhere(
        (i) =>
            find.byKey(ValueKey('msg-$i')).evaluate().isNotEmpty &&
            edge(tester, i).dy < 350,
      );

  testWidgets('reversed list: pinch keeps the message under the fingers still',
      (tester) async {
    final scroll = await pump(tester);
    scroll.jumpTo(300);
    await tester.pump();
    final probe = middleMessage(tester);
    final before = edge(tester, probe);
    final focal = tester.getCenter(find.byKey(ValueKey('msg-$probe')));

    controller.beginGesture(focal);
    expect(sliver(tester).anchorIndex, probe);
    for (var z = 0.0; z <= 2.0; z += 0.05) {
      controller.value = z;
      await tester.pump();
      expect(edge(tester, probe).dy, closeTo(before.dy, 1), reason: 'z=$z');
    }
    unawaited(controller.endGesture(projected: 2));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(edge(tester, probe).dy, closeTo(before.dy, 1), reason: 'f$i');
    }
    await tester.pumpAndSettle();
    expect(controller.level, 2);
    expect(sliver(tester).anchorIndex, isNull);
  });

  testWidgets('reversed list: buttons keep the newest visible message still',
      (tester) async {
    final scroll = await pump(tester);
    scroll.jumpTo(400);
    await tester.pump();
    unawaited(controller.animateToLevel(2));
    final anchored = sliver(tester).anchorIndex!;
    final before = edge(tester, anchored);
    // The leading edge of a reversed list is the bottom: the anchored message
    // is the lowest one still on screen.
    expect(before.dy, greaterThan(400));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(edge(tester, anchored).dy, closeTo(before.dy, 1));
    }
    await tester.pumpAndSettle();
  });

  testWidgets('reversed list: expanding one message keeps it still',
      (tester) async {
    final scroll = await pump(tester);
    scroll.jumpTo(300);
    await tester.pump();
    final probe = middleMessage(tester);
    final before = edge(tester, probe);
    controller.anchorAt(tester.getCenter(find.byKey(ValueKey('msg-$probe'))));
    controller.setItemLevel(probe, 2);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(edge(tester, probe).dy, closeTo(before.dy, 1), reason: 'f$i');
    }
    await tester.pumpAndSettle();
    expect(controller.itemLevel(probe), 2);
  });

  testWidgets('reversed list at the newest message never scrolls past it',
      (tester) async {
    final scroll = await pump(tester);
    expect(scroll.offset, 0);
    controller.beginGesture(const Offset(200, 580));
    controller.value = 2;
    await tester.pump();
    controller.value = 0;
    await tester.pump();
    expect(scroll.offset, greaterThanOrEqualTo(0));
  });

  testWidgets('SemanticZoomListView.builder(reverse: true)', (tester) async {
    final scroll = await pump(tester, useListView: true);
    // At the start, item 0 (the newest message) sits at the bottom.
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('msg-0'))).dy,
      closeTo(600, 1),
    );
    scroll.jumpTo(300);
    await tester.pump();
    final probe = middleMessage(tester);
    final before = edge(tester, probe);
    controller.beginGesture(
      tester.getCenter(find.byKey(ValueKey('msg-$probe'))),
    );
    for (var z = 0.0; z <= 2.0; z += 0.1) {
      controller.value = z;
      await tester.pump();
      expect(edge(tester, probe).dy, closeTo(before.dy, 1), reason: 'z=$z');
    }
    unawaited(controller.endGesture(projected: 2));
    await tester.pumpAndSettle();
  });
}
