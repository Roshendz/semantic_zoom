// Pixel baselines added in 0.4, recorded from the published 0.3.2
// rendering. See golden_test.dart for why they are local-only.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

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

Widget _frame(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );

void main() => _goldens03();

void _goldens03() {
  final text = LeveledText.parse(
    'Took **Tram 28**[ up to *Alfama*]{, standing room only}. '
    '[Found a tiny bakery.]',
  );

  testWidgets('grid at level 1', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 420)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late SemanticZoomController zoom;
    await tester.pumpWidget(
      _frame(
        _Host((z) {
          zoom = z;
          return SemanticZoomGridView.builder(
            controller: z,
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            itemCount: 6,
            itemBuilder: (context, i) => ColoredBox(
              color: const Color(0xFFEFEFEF),
              child: LeveledTextView(text, itemId: i),
            ),
          );
        }),
      ),
    );
    zoom.jumpToLevel(1);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/grid_level1.png'),
    );
  });

  testWidgets('chat with one message expanded', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 420)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late SemanticZoomController zoom;
    await tester.pumpWidget(
      _frame(
        _Host((z) {
          zoom = z;
          return SemanticZoomListView.builder(
            controller: z,
            reverse: true,
            itemCount: 8,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.all(6),
              child: LeveledTextView(text, itemId: i),
            ),
          );
        }),
      ),
    );
    zoom.setItemLevel(1, 2);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chat_item_expanded.png'),
    );
  });
}
