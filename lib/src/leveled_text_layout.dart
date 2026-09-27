import 'package:flutter/painting.dart';

import 'leveled_text.dart';

/// Where every token sits at one detail level.
class LevelLayout {
  /// Creates a layout. Use [LeveledTextLayout.layoutFor] instead.
  const LevelLayout(this.offsets, this.height);

  /// Top-left of each token, indexed like [LeveledText.tokens]. `null` means
  /// hidden at this level.
  final List<Offset?> offsets;

  /// Total height of the laid-out text.
  final double height;
}

/// Measures [LeveledText] with Flutter's own paragraph engine.
///
/// For each (level, width) the visible text is laid out once as a real
/// paragraph and each token's position is read back with
/// [TextPainter.getBoxesForSelection]. Line breaking, bidi/RTL and kerning
/// come from the engine. Each token is painted from its own pre-laid-out
/// [TextPainter] so it can move independently between levels.
///
/// Results are cached, so animating between levels never measures text.
class LeveledTextLayout {
  /// Prepares one painter per token. Call [dispose] when done.
  LeveledTextLayout(
    this.text, {
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    this.paragraphGap = 6,
  })  : _style = style,
        _textScaler = textScaler,
        _textDirection = textDirection,
        rewrittenLevels = {
          for (final t in text.tokens)
            if (t.maxLevel != null) t.maxLevel! + 1,
        } {
    painters = [
      for (final t in text.tokens) _painter(t.isBreak ? '' : t.text)..layout(),
    ];
  }

  /// The text being laid out.
  final LeveledText text;

  /// Extra space between paragraphs.
  final double paragraphGap;

  /// Levels at which some words are replaced rather than only added. The
  /// view staggers the cross-fade there so old and new words don't overlap.
  final Set<int> rewrittenLevels;

  final TextStyle _style;
  final TextScaler _textScaler;
  final TextDirection _textDirection;

  /// One painter per token, reused across all levels.
  late final List<TextPainter> painters;

  final _cache = <(int, double), LevelLayout>{};

  TextPainter _painter(String s) => TextPainter(
        text: TextSpan(text: s, style: _style),
        textDirection: _textDirection,
        textScaler: _textScaler,
      );

  /// The (cached) layout of [level] at [maxWidth].
  LevelLayout layoutFor(int level, double maxWidth) =>
      _cache.putIfAbsent((level, maxWidth), () => _compute(level, maxWidth));

  LevelLayout _compute(int level, double maxWidth) {
    final tokens = text.tokens;
    final buf = StringBuffer();
    final ranges = List<(int, int)?>.filled(tokens.length, null);
    final paragraphOf = List<int>.filled(tokens.length, 0);
    var paragraph = 0;
    var pendingBreak = false;

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (!t.isVisibleAt(level)) continue;
      if (t.isBreak) {
        // Collapse breaks that would produce empty paragraphs at this level.
        pendingBreak = buf.isNotEmpty;
        continue;
      }
      if (pendingBreak) {
        buf.write('\n');
        paragraph++;
        pendingBreak = false;
      } else if (buf.isNotEmpty && !t.glued) {
        buf.write(' ');
      }
      final start = buf.length;
      buf.write(t.text);
      ranges[i] = (start, buf.length);
      paragraphOf[i] = paragraph;
    }

    // minLevel pins the paragraph to the full width; otherwise it shrinks to
    // its text and RTL lines would hug the left edge.
    final para = _painter(buf.toString())
      ..layout(minWidth: maxWidth, maxWidth: maxWidth);
    final offsets = List<Offset?>.filled(tokens.length, null);
    for (var i = 0; i < tokens.length; i++) {
      final r = ranges[i];
      if (r == null) continue;
      final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: r.$1, extentOffset: r.$2),
      );
      if (boxes.isEmpty) continue;
      // A token is one word, so normally one box. If a word is wider than
      // the line and the engine splits it, anchor at the first fragment.
      final box = boxes.first;
      offsets[i] = Offset(box.left, box.top + paragraphOf[i] * paragraphGap);
    }

    final height = buf.isEmpty ? 0.0 : para.height + paragraph * paragraphGap;
    para.dispose();
    return LevelLayout(offsets, height);
  }

  /// Releases the per-token painters.
  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
  }
}
