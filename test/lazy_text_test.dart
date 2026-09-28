import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

const _brief = 'Knee review';
const _longer = [
  'Knee review: swelling reduced, cleared to run',
  'Knee review after six sessions: swelling reduced and range of motion '
      'restored, cleared to run twice a week. Keep strength exercises daily.',
];

/// A fake backend: each call waits until the test completes it.
class _Server {
  final calls = <Completer<List<String>>>[];
  Future<List<String>> fetch() {
    final c = Completer<List<String>>();
    calls.add(c);
    return c.future;
  }

  void completeAll() {
    for (final c in calls) {
      if (!c.isCompleted) c.complete(_longer);
    }
  }
}

void main() {
  group('LeveledTextLoader', () {
    test('shows the brief text, loads once, then the full text', () async {
      final server = _Server();
      final loader = LeveledTextLoader.versions(
        brief: _brief,
        load: server.fetch,
      );
      var notified = 0;
      loader.addListener(() => notified++);
      expect(loader.text.textAt(2), _brief);
      expect(loader.isLoaded, isFalse);

      final a = loader.ensureLoaded();
      final b = loader.ensureLoaded();
      await Future<void>.delayed(Duration.zero);
      expect(server.calls, hasLength(1), reason: 'concurrent calls share');
      expect(loader.isLoading, isTrue);
      server.completeAll();
      await Future.wait([a, b]);

      expect(loader.isLoaded, isTrue);
      expect(loader.isLoading, isFalse);
      expect(loader.text.textAt(0), _brief);
      expect(loader.text.textAt(2), _longer.last);
      expect(notified, 2);
      await loader.ensureLoaded();
      expect(server.calls, hasLength(1), reason: 'cached');
    });

    test('failures are reported and can be retried', () async {
      var attempt = 0;
      final loader = LeveledTextLoader.versions(
        brief: _brief,
        load: () async {
          if (attempt++ == 0) throw StateError('offline');
          return _longer;
        },
      );
      await loader.ensureLoaded(); // never throws
      expect(loader.error, isA<StateError>());
      expect(loader.isLoaded, isFalse);
      await loader.ensureLoaded();
      expect(loader.error, isNull);
      expect(loader.isLoaded, isTrue);
    });

    test('loaded() never fetches; disposing mid-load is safe', () async {
      final ready = LeveledTextLoader.loaded(LeveledText.parse('a [b]'));
      expect(ready.isLoaded, isTrue);
      await ready.ensureLoaded();

      final server = _Server();
      final loader = LeveledTextLoader.versions(
        brief: _brief,
        load: server.fetch,
      );
      final pending = loader.ensureLoaded();
      loader.dispose();
      server.completeAll();
      await pending;
    });
  });

  group('LazyLeveledTextView in a list', () {
    late SemanticZoomController zoom;
    late _Server server;
    late List<LeveledTextLoader> loaders;
    late ScrollController scroll;

    Future<void> pump(
      WidgetTester tester, {
      bool reduceMotion = false,
      int count = 30,
      LeveledTextLoader Function(int i)? make,
    }) async {
      tester.view
        ..physicalSize = const Size(400, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server = _Server();
      loaders = [
        for (var i = 0; i < count; i++)
          make?.call(i) ??
              LeveledTextLoader.versions(brief: _brief, load: server.fetch),
      ];
      scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 600),
              disableAnimations: reduceMotion,
            ),
            child: _Host(
              (z) {
                zoom = z;
                return SemanticZoomListView.builder(
                  controller: z,
                  scrollController: scroll,
                  physics: const ClampingScrollPhysics(),
                  itemCount: count,
                  itemBuilder: (context, i) => Padding(
                    key: ValueKey('i$i'),
                    padding: const EdgeInsets.all(8),
                    child: LazyLeveledTextView(
                      loaders[i],
                      itemId: i,
                      loadingBuilder: (_) => const Text('loading…'),
                      errorBuilder: (_, e, retry) => TextButton(
                        onPressed: retry,
                        child: const Text('retry'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    double height(WidgetTester t, int i) =>
        t.getSize(find.byKey(ValueKey('i$i'))).height;
    // Includes entries built in the list's off-screen cache area.
    int built() =>
        find.byType(LazyLeveledTextView, skipOffstage: false).evaluate().length;

    testWidgets('nothing loads at the brief level', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(server.calls, isEmpty);
    });

    testWidgets('zooming loads only the entries that are built',
        (tester) async {
      await pump(tester);
      final builtBefore = built();
      unawaited(zoom.animateToLevel(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(server.calls, isNotEmpty);
      expect(server.calls.length, lessThanOrEqualTo(builtBefore));
      expect(server.calls.length, lessThan(30));
      await tester.pumpAndSettle();
    });

    testWidgets('stays brief while loading, then morphs in', (tester) async {
      await pump(tester);
      final brief = height(tester, 0);
      unawaited(zoom.animateToLevel(2));
      await tester.pumpAndSettle();
      expect(find.text('loading…'), findsWidgets);
      expect(height(tester, 0), brief + _loadingRow(tester));

      server.completeAll();
      await tester.pump(); // loader notifies, reveal starts
      await tester.pump(); // first reveal frame
      await tester.pump(const Duration(milliseconds: 150));
      final mid = height(tester, 0);
      await tester.pumpAndSettle();
      final full = height(tester, 0);
      expect(find.text('loading…'), findsNothing);
      expect(mid, greaterThan(brief));
      expect(mid, lessThan(full), reason: 'grows over several frames');
      expect(full, _fullHeight(tester));
    });

    testWidgets('reduce motion shows the loaded text at once', (tester) async {
      await pump(tester, reduceMotion: true);
      zoom.jumpToLevel(2);
      await tester.pump();
      await tester.pump();
      server.completeAll();
      await tester.pump();
      await tester.pump();
      expect(height(tester, 0), _fullHeight(tester));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('tapping one entry loads just that entry', (tester) async {
      await pump(tester);
      zoom.setItemLevel(3, 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(server.calls, hasLength(1));
      server.completeAll();
      await tester.pumpAndSettle();
      expect(loaders[3].isLoaded, isTrue);
      expect(loaders[2].isLoaded, isFalse);
      expect(height(tester, 3), greaterThan(height(tester, 2)));
    });

    testWidgets('entries above the pinned one growing keep it still',
        (tester) async {
      await pump(tester);
      scroll.jumpTo(700);
      await tester.pump();
      zoom.jumpToLevel(2);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      server.completeAll();
      await tester.pump(); // loaders notify: anchor held, reveal starts
      final sliver = tester.renderObject<RenderSliverSemanticZoomList>(
        find.byType(SliverSemanticZoomList),
      );
      final pinned = sliver.anchorIndex!;
      final before = tester.getTopLeft(find.byKey(ValueKey('i$pinned'))).dy;
      var grewAbove = false;
      for (var f = 0; f < 30; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(find.byKey(ValueKey('i$pinned'))).dy,
          closeTo(before, 1),
          reason: 'frame $f',
        );
        grewAbove |= pinned > 0 && loaders[pinned - 1].isLoaded;
      }
      expect(grewAbove, isTrue, reason: 'an entry above really grew');
      await tester.pumpAndSettle();
      expect(sliver.anchorIndex, isNull, reason: 'released afterwards');
    });

    testWidgets('a failed load shows retry, and retry works', (tester) async {
      var fail = true;
      await pump(
        tester,
        count: 1,
        make: (_) => LeveledTextLoader.versions(
          brief: _brief,
          load: () async {
            if (fail) throw StateError('offline');
            return _longer;
          },
        ),
      );
      zoom.jumpToLevel(2);
      await tester.pumpAndSettle();
      expect(find.text('retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('retry'));
      await tester.pumpAndSettle();
      expect(find.text('retry'), findsNothing);
      expect(height(tester, 0), _fullHeight(tester));
    });

    testWidgets('already loaded text shows at once', (tester) async {
      await pump(
        tester,
        count: 1,
        make: (_) => LeveledTextLoader.loaded(
          LeveledText.fromVersions(const [_brief, ..._longer]),
        ),
      );
      zoom.jumpToLevel(2);
      await tester.pump();
      expect(height(tester, 0), _fullHeight(tester));
      expect(server.calls, isEmpty);
    });

    testWidgets('screen readers get the brief text until loaded',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, count: 1);
      zoom.jumpToLevel(2);
      await tester.pump();
      await tester.pump();
      // In a list the text and the loading row are merged into one label.
      expect(find.bySemanticsLabel(RegExp('^$_brief\\b')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('twice a week')), findsNothing);
      server.completeAll();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_longer.last))),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('a pinch during a hold keeps its own anchor', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late SemanticZoomController zoom;
    await tester.pumpWidget(
      MaterialApp(
        home: _Host((z) {
          zoom = z;
          return SemanticZoomListView.builder(
            controller: z,
            itemCount: 30,
            itemBuilder: (c, i) =>
                LeveledTextView(LeveledText.parse('a [b] {c}'), itemId: i),
          );
        }),
      ),
    );
    final sliver = tester.renderObject<RenderSliverSemanticZoomList>(
      find.byType(SliverSemanticZoomList),
    );
    final release = zoom.holdAnchor();
    expect(sliver.anchorIndex, 0);
    zoom.beginGesture(tester.getCenter(find.byType(LeveledTextView).at(3)));
    expect(sliver.anchorIndex, 3);
    release();
    await tester.pump();
    await tester.pump();
    expect(sliver.anchorIndex, 3, reason: 'the pinch still owns it');
    unawaited(zoom.endGesture(projected: 0));
    await tester.pumpAndSettle();
    expect(sliver.anchorIndex, isNull);
  });
}

// Height of the "loading…" row under the text in the test theme.
double _loadingRow(WidgetTester t) =>
    t.getSize(find.text('loading…').first).height;

// Height of the fully loaded entry at level 2, laid out the normal way.
double _fullHeight(WidgetTester t) {
  final layout = LeveledTextLayout(
    LeveledText.fromVersions(const [_brief, ..._longer]),
    style: DefaultTextStyle.of(t.element(find.byType(LeveledTextView).first))
        .style,
    textScaler: TextScaler.noScaling,
    textDirection: TextDirection.ltr,
  );
  final h = layout.layoutFor(2, 400 - 16).height + 16;
  layout.dispose();
  return h;
}

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
  Widget build(BuildContext context) => Scaffold(body: widget.build(zoom));
}
