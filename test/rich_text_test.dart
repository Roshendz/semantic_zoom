import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

class _Host extends StatefulWidget {
  const _Host({required this.child, required this.onController});
  final Widget Function(SemanticZoomController) child;
  final ValueChanged<SemanticZoomController> onController;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onController(zoom);
  }

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 400, child: widget.child(zoom)),
          ),
        ),
      );
}

void main() {
  late SemanticZoomController zoom;
  final text = LeveledText.parse(
    'See **the** [docs](https://docs.example){ for the [full guide](g)}',
  );

  testWidgets('links are tappable and report their target', (tester) async {
    final taps = <String>[];
    var parentTaps = 0;
    await tester.pumpWidget(
      _Host(
        onController: (c) => zoom = c,
        child: (c) => GestureDetector(
          onTap: () => parentTaps++,
          child: LeveledTextView(text, controller: c, onLinkTap: taps.add),
        ),
      ),
    );

    // Level 0: "See the docs"; only "docs" is a link target.
    final layout = LeveledTextLayout(
      text,
      style: const TextStyle(fontSize: 14),
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
    final docs = text.tokens.indexWhere((t) => t.text == 'docs');
    final origin = tester.getTopLeft(find.byType(LeveledTextView));
    final at = layout.layoutFor(0, 400).offsets[docs]! +
        layout.painters[docs].size.center(Offset.zero);
    layout.dispose();

    await tester.tapAt(origin + at);
    expect(taps, ['https://docs.example']);
    expect(parentTaps, 0, reason: 'the link wins over the parent tap');

    // Tapping plain text still reaches the parent.
    await tester.tapAt(origin + const Offset(4, 8));
    expect(parentTaps, 1);
  });

  testWidgets('hidden links are not tappable, visible ones are',
      (tester) async {
    await tester.pumpWidget(
      _Host(
        onController: (c) => zoom = c,
        child: (c) => LeveledTextView(text, controller: c, onLinkTap: (_) {}),
      ),
    );
    int targets() => find
        .descendant(
          of: find.byType(LeveledTextView),
          matching: find.byType(MouseRegion),
        )
        .evaluate()
        .length;
    expect(targets(), 1); // "docs"
    zoom.jumpToLevel(2);
    await tester.pump();
    expect(targets(), 3); // "docs", "full", "guide"
  });

  testWidgets('links are announced as links', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _Host(
        onController: (c) => zoom = c,
        child: (c) => LeveledTextView(text, controller: c, onLinkTap: (_) {}),
      ),
    );
    zoom.jumpToLevel(2);
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel('docs')),
      matchesSemantics(label: 'docs', isLink: true, hasTapAction: true),
    );
    expect(find.bySemanticsLabel('full guide'), findsOneWidget);
    handle.dispose();
  });

  test('styles and link style are applied when measuring', () {
    final layout = LeveledTextLayout(
      text,
      style: const TextStyle(fontSize: 10),
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
      linkStyle: const TextStyle(color: Color(0xFF0000FF)),
    );
    final the = text.tokens.firstWhere((t) => t.text == 'the');
    final docs = text.tokens.firstWhere((t) => t.text == 'docs');
    expect(layout.styleOf(the).fontWeight, FontWeight.bold);
    expect(layout.styleOf(docs).color, const Color(0xFF0000FF));
    expect(layout.styleOf(docs).fontSize, 10);
    layout.dispose();
  });

  test('multi-word links get gap painters for a continuous underline', () {
    final layout = LeveledTextLayout(
      text,
      style: const TextStyle(fontSize: 10),
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
    final tokens = text.tokens;
    final withGap = [
      for (var i = 0; i < tokens.length; i++)
        if (layout.linkGapPainters[i] != null) tokens[i].text,
    ];
    // Only between "full" and "guide"; not after the one-word "docs" link.
    expect(withGap, ['full']);
    expect(layout.linkGapPainters.last, isNull);
    layout.dispose();
  });
}
