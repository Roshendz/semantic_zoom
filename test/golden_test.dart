// Pixel baselines of the published rendering. They are recorded once from
// released code and must keep matching, so new features can't change how
// existing apps look. Run locally; CI skips them because font rasterising
// differs between operating systems.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _rich = LeveledText.parse(
  'Took **Tram 28**[ up to *Alfama*]{, standing room only}. '
  'See [the map](https://example.com){ and the timetable}.\n'
  '[Found a tiny bakery.]',
);

final _rewrite = LeveledText.fromVersions(const [
  'Checkout crash fixed',
  'Android checkout crash is fixed in version 4.2.1',
  'The checkout crash affecting some Android 14 users is fixed in 4.2.1.',
]);

class _Host extends StatefulWidget {
  const _Host(this.build);
  final Widget Function(SemanticZoomController zoom) build;

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

Widget _frame(Widget child, {TextDirection dir = TextDirection.ltr}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Directionality(
        textDirection: dir,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ),
    );

Future<SemanticZoomController> _pumpViews(
  WidgetTester tester, {
  TextDirection dir = TextDirection.ltr,
}) async {
  tester.view
    ..physicalSize = const Size(360, 420)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late SemanticZoomController zoom;
  await tester.pumpWidget(
    _frame(
      dir: dir,
      _Host((z) {
        zoom = z;
        return DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Colors.black),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LeveledTextView(
                _rich,
                controller: z,
                linkStyle: LeveledTextView.defaultLinkStyle.copyWith(
                  color: Colors.blue,
                ),
                onLinkTap: (_) {},
              ),
              const Divider(),
              LeveledTextView(_rewrite, controller: z),
            ],
          ),
        );
      }),
    ),
  );
  return zoom;
}

void main() {
  for (final z in [0.0, 0.3, 0.5, 1.0, 1.5, 2.0]) {
    testWidgets('views at zoom $z', (tester) async {
      final zoom = await _pumpViews(tester);
      zoom.value = z;
      await tester.pump();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/views_z$z.png'),
      );
    });
  }

  testWidgets('right-to-left views at zoom 1.5', (tester) async {
    final zoom = await _pumpViews(tester, dir: TextDirection.rtl);
    zoom.value = 1.5;
    await tester.pump();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/views_rtl_z1.5.png'),
    );
  });

  testWidgets('list mid-pinch with anchoring', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late SemanticZoomController zoom;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _frame(
        _Host((z) {
          zoom = z;
          return SemanticZoomListView.builder(
            controller: z,
            scrollController: scroll,
            physics: const ClampingScrollPhysics(),
            itemCount: 30,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LeveledTextView(i.isEven ? _rich : _rewrite, itemId: i),
            ),
          );
        }),
      ),
    );
    scroll.jumpTo(300);
    await tester.pump();
    zoom.beginGesture(const Offset(180, 300));
    for (var v = 0.0; v <= 1.4; v += 0.1) {
      zoom.value = v;
      await tester.pump();
    }
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/list_pinch.png'),
    );
    zoom.value = 0;
    await tester.pump();
  });

  testWidgets('one item expanded in a list', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late SemanticZoomController zoom;
    await tester.pumpWidget(
      _frame(
        _Host((z) {
          zoom = z;
          return SemanticZoomListView.builder(
            controller: z,
            itemCount: 6,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LeveledTextView(_rich, itemId: i),
            ),
          );
        }),
      ),
    );
    zoom.setItemLevel(1, 2);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/list_item_expanded.png'),
    );
  });

  for (final taps in [0, 1, 2]) {
    testWidgets('expandable text after $taps taps', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 260)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _frame(
          ExpandableLeveledText(
            _rich,
            expandOnTap: false,
            footerBuilder: (context, level, max, toggle) => TextButton(
              onPressed: toggle,
              child: Text(level < max ? 'more' : 'less'),
            ),
          ),
        ),
      );
      for (var i = 0; i < taps; i++) {
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/expandable_$taps.png'),
      );
    });
  }
}
