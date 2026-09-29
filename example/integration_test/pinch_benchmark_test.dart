// Frame-time benchmark: pinch, level changes and scrolling on a 1,000-entry
// list. Run it on a real device in profile mode (see "Performance" in the
// package README):
//
//   flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
//     --target=integration_test/pinch_benchmark_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

const _entries = 1000;

// Realistic mixed content: markup and rewritten versions, some bold/links.
final _texts = [
  LeveledText.parse(
    '[Took] Tram 28 [up] to **Alfama**{, standing room only and every curve '
    'a small adventure}[. Got lost on purpose and found a tiny bakery.]\n'
    '{Pastéis de nata still warm from the oven.}',
  ),
  LeveledText.fromVersions(const [
    'Blood pressure follow-up',
    'Blood pressure follow-up: readings improved, **dose unchanged**',
    'Blood pressure follow-up: home readings averaged 128/82 over four '
        'weeks, readings improved since January, **dose unchanged**. '
        'Continue low-sodium diet and review again in three months.',
  ]),
  LeveledText.fromVersions(const [
    'Checkout crash fixed',
    'Android checkout crash is fixed in version 4.2.1',
    'The checkout crash affecting some Android 14 users is fixed in version '
        '4.2.1, now rolling out to 20% of users. Leo will close the tickets '
        'once the crash rate stays flat for 48 hours.',
  ]),
  LeveledText.parse(
    'Day trip to [Sintra](https://en.wikipedia.org/wiki/Sintra)[. Pena '
    'Palace was lost in fog]{ until noon, then the whole valley opened up '
    'below us}[. Walked back down through the forest.]',
  ),
];

class _Bench extends StatefulWidget {
  const _Bench();

  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> with SingleTickerProviderStateMixin {
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
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: SemanticZoomListView.builder(
          controller: zoom,
          scrollController: scroll,
          padding: const EdgeInsets.all(16),
          itemCount: _entries,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entry ${i + 1}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                LeveledTextView(
                  _texts[i % _texts.length],
                  itemId: i,
                  onLinkTap: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Let the engine schedule frames normally, as in a real app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('semantic zoom frame times', (tester) async {
    await tester.pumpWidget(const _Bench());
    await tester.pumpAndSettle();
    final state = tester.state<_BenchState>(find.byType(_Bench));
    final list = tester.getRect(find.byType(CustomScrollView));

    // Start deep in the list so anchoring and estimates are exercised.
    state.scroll.jumpTo(40000);
    await tester.pumpAndSettle();

    Future<void> pinch(double from, double to) async {
      final c = list.center;
      const axis = Offset(0.55, 0.835);
      final a = await tester.startGesture(c - axis * (from / 2));
      final b = await tester.startGesture(c + axis * (from / 2));
      const frames = 60; // about one second of finger movement
      for (var i = 1; i <= frames; i++) {
        final d = from + (to - from) * i / frames;
        await a.moveTo(c - axis * (d / 2));
        await b.moveTo(c + axis * (d / 2));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    await binding.watchPerformance(() async {
      await pinch(60, 260); // brief -> full
      await pinch(260, 60); // full -> brief
    }, reportKey: 'pinch');

    await binding.watchPerformance(() async {
      for (final level in [2, 0, 1, 2, 0]) {
        await state.zoom.animateToLevel(level);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'level_buttons');

    state.zoom.jumpToLevel(2);
    await tester.pumpAndSettle();
    await binding.watchPerformance(() async {
      for (final dy in [-3000.0, 3000.0, -3000.0]) {
        await tester.fling(find.byType(CustomScrollView), Offset(0, dy), 4000);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'scroll_full_level');
  });
}
