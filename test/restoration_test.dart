import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _text = LeveledText.parse(
  'Title [with a medium summary that wraps onto a few lines of text] '
  '{and the full detailed notes that go on for quite a while longer.}',
);

class _Journal extends StatefulWidget {
  const _Journal({this.restorationId});
  final String? restorationId;

  @override
  State<_Journal> createState() => _JournalState();
}

class _JournalState extends State<_Journal>
    with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(vsync: this);
  final notified = <int>[];

  @override
  void initState() {
    super.initState();
    zoom.addListener(() => notified.add(zoom.level));
  }

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            // Listens to the controller *above* the list: restoring must not
            // notify it during the build.
            ListenableBuilder(
              listenable: zoom,
              builder: (context, _) => Text('level ${zoom.level}'),
            ),
            Expanded(
              child: SemanticZoomListView.builder(
                controller: zoom,
                restorationId: widget.restorationId,
                itemCount: 30,
                itemBuilder: (context, i) => Padding(
                  key: ValueKey('i$i'),
                  padding: const EdgeInsets.all(8),
                  child: LeveledTextView(_text, itemId: i),
                ),
              ),
            ),
          ],
        ),
      );
}

Widget _app(Widget home) => MaterialApp(restorationScopeId: 'app', home: home);

void main() {
  _JournalState journal(WidgetTester t) => t.state(find.byType(_Journal));
  double height(WidgetTester t, int i) =>
      t.getSize(find.byKey(ValueKey('i$i'))).height;

  group('SemanticZoomListView(restorationId)', () {
    testWidgets('restores the level, item levels and scroll position',
        (tester) async {
      await tester.pumpWidget(_app(const _Journal(restorationId: 'journal')));
      final brief = height(tester, 1);
      journal(tester).zoom.jumpToLevel(1);
      await tester.pump();
      journal(tester).zoom.setItemLevel(2, 2, animate: false);
      await tester.pump();
      final scroll =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      scroll.jumpTo(120);
      await tester.pump();
      final medium = height(tester, 3);
      final full = height(tester, 2);
      expect(medium, greaterThan(brief));
      expect(full, greaterThan(medium));

      await tester.restartAndRestore();

      final j = journal(tester);
      expect(j.zoom.level, 1);
      expect(j.zoom.itemLevel(2), 2);
      expect(j.zoom.itemLevel(3), 1);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        120,
      );
      // Shown at the restored level from the first frame, no animation.
      expect(height(tester, 3), medium);
      expect(height(tester, 2), full);
      expect(tester.hasRunningAnimations, isFalse);
      // Widgets above the list hear about it right after the first frame.
      await tester.pump();
      expect(find.text('level 1'), findsOneWidget);
      expect(j.notified, [1], reason: 'one notification, after the frame');
    });

    testWidgets('changes after a restore are saved again', (tester) async {
      await tester.pumpWidget(_app(const _Journal(restorationId: 'journal')));
      journal(tester).zoom.jumpToLevel(2);
      await tester.pump();
      await tester.restartAndRestore();
      journal(tester).zoom.jumpToLevel(0);
      await tester.pump();
      await tester.restartAndRestore();
      expect(journal(tester).zoom.level, 0);
    });

    testWidgets('without restorationId nothing is restored', (tester) async {
      await tester.pumpWidget(_app(const _Journal()));
      journal(tester).zoom.jumpToLevel(2);
      await tester.pump();
      await tester.restartAndRestore();
      expect(journal(tester).zoom.level, 0);
    });
  });

  testWidgets('SemanticZoomDetector(restorationId) on its own', (tester) async {
    late SemanticZoomController zoom;
    Widget build() => _app(
          _Holder(
            (z) {
              zoom = z;
              return SemanticZoomDetector(
                controller: z,
                restorationId: 'zoom',
                builder: (context, _) => LeveledTextView(_text),
              );
            },
          ),
        );
    await tester.pumpWidget(build());
    zoom.jumpToLevel(2);
    await tester.pump();
    await tester.restartAndRestore();
    expect(zoom.level, 2);
  });

  group('ExpandableLeveledText', () {
    testWidgets('restorationId restores the level', (tester) async {
      final key = GlobalKey<ExpandableLeveledTextState>();
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ExpandableLeveledText(_text, key: key, restorationId: 'note'),
          ),
        ),
      );
      key.currentState!.expand();
      await tester.pumpAndSettle();
      await tester.restartAndRestore();
      expect(key.currentState!.level, 2);
      expect(tester.hasRunningAnimations, isFalse);
    });

    Widget feed({required bool pageStorage}) => MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: 60,
              itemBuilder: (context, i) => ExpandableLeveledText(
                _text,
                key: pageStorage ? PageStorageKey('note-$i') : ValueKey(i),
              ),
            ),
          ),
        );

    Future<int> levelAfterScrollingAway(
      WidgetTester tester, {
      required bool pageStorage,
    }) async {
      await tester.pumpWidget(feed(pageStorage: pageStorage));
      await tester.tap(find.byType(ExpandableLeveledText).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpandableLeveledText).first);
      await tester.pumpAndSettle();
      final scroll =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      scroll.jumpTo(6000);
      await tester.pump();
      expect(
        find.byType(ExpandableLeveledText).evaluate().length,
        lessThan(60),
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      return tester
          .state<ExpandableLeveledTextState>(
            find.byType(ExpandableLeveledText).first,
          )
          .level;
    }

    testWidgets('a PageStorageKey keeps the level when scrolled away',
        (tester) async {
      expect(await levelAfterScrollingAway(tester, pageStorage: true), 2);
    });

    testWidgets('without a PageStorageKey it resets, as in 0.2.0',
        (tester) async {
      expect(await levelAfterScrollingAway(tester, pageStorage: false), 0);
    });

    testWidgets('a PageStorageKey on an ancestor alone is not shared',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              key: const PageStorageKey('feed'),
              children: [
                for (var i = 0; i < 3; i++)
                  ExpandableLeveledText(_text, key: ValueKey(i)),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ExpandableLeveledText).first);
      await tester.pumpAndSettle();
      // Rebuild the others from scratch: they must not pick up item 0's level.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              key: const PageStorageKey('feed'),
              children: [
                for (var i = 0; i < 3; i++)
                  ExpandableLeveledText(_text, key: ValueKey(i + 10)),
              ],
            ),
          ),
        ),
      );
      final states = tester
          .stateList<ExpandableLeveledTextState>(
            find.byType(ExpandableLeveledText),
          )
          .map((s) => s.level);
      expect(states, [0, 0, 0]);
    });
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
  Widget build(BuildContext context) => Scaffold(body: widget.build(zoom));
}
