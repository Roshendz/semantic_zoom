import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

final _text = LeveledText.parse(
  'Took **Tram 28**[ up to *Alfama*]{, standing room only}. '
  'See [the full map](https://example.com){ and the timetable}.\n'
  '[Found a tiny bakery near the river.]',
);

class _Host extends StatefulWidget {
  const _Host({
    required this.selectable,
    this.level = 1,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.style,
  });
  final bool selectable;
  final TextStyle? style;
  final int level;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(
    vsync: this,
    initialLevel: widget.level,
  );
  SelectedContent? selected;

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget view = Padding(
      padding: const EdgeInsets.all(8),
      child: LeveledTextView(
        _text,
        controller: zoom,
        linkStyle: LeveledTextView.defaultLinkStyle.copyWith(
          color: Colors.blue,
        ),
        onLinkTap: (_) {},
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        style: widget.style,
      ),
    );
    if (widget.selectable) {
      view = SelectionArea(
        onSelectionChanged: (content) => selected = content,
        child: view,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: RepaintBoundary(
          key: const Key('shot'),
          child: SizedBox(width: 300, child: view),
        ),
      ),
    );
  }
}

Future<(Uint8List, int, int)> _pixels(WidgetTester tester) async {
  late Uint8List bytes;
  late int width, height;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('shot')),
    );
    final image = await boundary.toImage();
    width = image.width;
    height = image.height;
    final data = await image.toByteData();
    image.dispose();
    bytes = data!.buffer.asUint8List();
  });
  return (bytes, width, height);
}

Finder _realText() => find.descendant(
      of: find.byType(LeveledTextView),
      matching: find.byType(RichText),
    );

void main() {
  final configs = <String, _Host Function(bool selectable, int level)>{
    'start': (sel, level) => _Host(selectable: sel, level: level),
    'centred': (sel, level) =>
        _Host(selectable: sel, level: level, textAlign: TextAlign.center),
    'justified': (sel, level) =>
        _Host(selectable: sel, level: level, textAlign: TextAlign.justify),
    // Line height under 1: glyphs reach above the line box, so the shift
    // between the two modes is negative (as with some system fonts).
    'tight line height': (sel, level) => _Host(
          selectable: sel,
          level: level,
          style: const TextStyle(height: 0.8),
        ),
    'two lines with ellipsis': (sel, level) => _Host(
          selectable: sel,
          level: level,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
  };
  for (final MapEntry(key: name, value: make) in configs.entries) {
    for (final level in [0, 1, 2]) {
      testWidgets(
          'selectable text looks the same as the morphing view, '
          '$name, level $level', (tester) async {
        tester.view
          ..physicalSize = const Size(320, 240)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(make(false, level));
        expect(_realText(), findsNothing, reason: 'painted, not selectable');
        final (painted, w, h) = await _pixels(tester);

        await tester.pumpWidget(Container());
        await tester.pumpWidget(make(true, level));
        expect(_realText(), findsWidgets, reason: 'real text');
        final (selectable, w2, h2) = await _pixels(tester);
        expect((w2, h2), (w, h), reason: 'same size');

        // Compare 4x4-pixel blocks: a word drawn on its own is
        // anti-aliased slightly differently from the same word in a line
        // at fractional positions (under a pixel), but a shifted or missing
        // word changes whole blocks.
        var differing = 0;
        for (var by = 0; by + 4 <= h; by += 4) {
          for (var bx = 0; bx + 4 <= w; bx += 4) {
            var a = 0, b = 0;
            for (var y = by; y < by + 4; y++) {
              for (var x = bx; x < bx + 4; x++) {
                final i = (y * w + x) * 4;
                a += painted[i] + painted[i + 1] + painted[i + 2];
                b += selectable[i] + selectable[i + 1] + selectable[i + 2];
              }
            }
            if ((a - b).abs() / 48 > 64) differing++;
          }
        }
        expect(differing, 0, reason: '$differing blocks differ');
      });
    }
  }

  testWidgets('select all copies the text at the current level',
      (tester) async {
    await tester.pumpWidget(const _Host(selectable: true));
    final state = tester.state<_HostState>(find.byType(_Host));
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    // Paragraphs are copied with a line break between them.
    expect(state.selected?.plainText, _text.textAt(1));
  });

  testWidgets('morphs while the zoom moves, real text again at rest',
      (tester) async {
    await tester.pumpWidget(const _Host(selectable: true, level: 0));
    final zoom = tester.state<_HostState>(find.byType(_Host)).zoom;
    expect(_realText(), findsWidgets);

    unawaited(zoom.animateToLevel(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_realText(), findsNothing, reason: 'morphing');

    await tester.pumpAndSettle();
    expect(_realText(), findsWidgets, reason: 'selectable again');
  });

  testWidgets('screen readers still hear the text once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host(selectable: true));
    expect(find.bySemanticsLabel(_text.textAt(1)), findsOneWidget);
    handle.dispose();
  });

  testWidgets('links still work in selectable text', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: _Holder(
              (z) => LeveledTextView(_text, controller: z, onLinkTap: taps.add),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MouseRegion).last);
    expect(taps, ['https://example.com']);
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
