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
    TextStyle? linkStyle,
  })  : _style = style,
        _linkStyle = linkStyle,
        _textScaler = textScaler,
        _textDirection = textDirection,
        rewrittenLevels = {
          for (final t in text.tokens)
            if (t.maxLevel != null) t.maxLevel! + 1,
        } {
    painters = [
      for (final t in text.tokens)
        _painter(TextSpan(text: t.isBreak ? '' : t.text, style: styleOf(t)))
          ..layout(),
    ];
    final tokens = text.tokens;
    linkGapPainters = [
      for (var i = 0; i < tokens.length; i++)
        if (i + 1 < tokens.length &&
            tokens[i].link != null &&
            tokens[i + 1].link == tokens[i].link &&
            !tokens[i + 1].glued)
          // A no-break space: the engine doesn't decorate a plain trailing
          // space, so a lone ' ' would paint no underline.
          _painter(TextSpan(text: '\u00A0', style: styleOf(tokens[i + 1])))
            ..layout()
        else
          null,
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
  final TextStyle? _linkStyle;
  final TextScaler _textScaler;
  final TextDirection _textDirection;

  /// One painter per token, reused across all levels.
  late final List<TextPainter> painters;

  /// For a link word followed by another word of the same link, a painter
  /// for the space between them, so the link's underline is continuous.
  late final List<TextPainter?> linkGapPainters;

  final _cache = <(int, double), LevelLayout>{};

  /// The full style of [token]: the base style, its own style, and the
  /// link style for links.
  TextStyle styleOf(LeveledToken token) {
    var s = _style;
    if (token.style != null) s = s.merge(token.style);
    if (token.link != null && _linkStyle != null) s = s.merge(_linkStyle);
    return s;
  }

  TextPainter _painter(InlineSpan span) => TextPainter(
        text: span,
        textDirection: _textDirection,
        textScaler: _textScaler,
      );

  /// The (cached) layout of [level] at [maxWidth].
  LevelLayout layoutFor(int level, double maxWidth) =>
      _cache.putIfAbsent((level, maxWidth), () => _compute(level, maxWidth));

  LevelLayout _compute(int level, double maxWidth) {
    final tokens = text.tokens;
    // The paragraph is built from styled spans so bold, italic and links are
    // measured exactly as they are painted.
    final spans = <InlineSpan>[];
    var length = 0;
    void add(String s, [TextStyle? style]) {
      spans.add(TextSpan(text: s, style: style));
      length += s.length;
    }

    final ranges = List<(int, int)?>.filled(tokens.length, null);
    final paragraphOf = List<int>.filled(tokens.length, 0);
    var paragraph = 0;
    var pendingBreak = false;

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (!t.isVisibleAt(level)) continue;
      if (t.isBreak) {
        // Collapse breaks that would produce empty paragraphs at this level.
        pendingBreak = length > 0;
        continue;
      }
      if (pendingBreak) {
        add('\n');
        paragraph++;
        pendingBreak = false;
      } else if (length > 0 && !t.glued) {
        add(' ');
      }
      final start = length;
      add(t.text, styleOf(t));
      ranges[i] = (start, length);
      paragraphOf[i] = paragraph;
    }

    // minLevel pins the paragraph to the full width; otherwise it shrinks to
    // its text and RTL lines would hug the left edge.
    final para = _painter(TextSpan(style: _style, children: spans))
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

    final height = length == 0 ? 0.0 : para.height + paragraph * paragraphGap;
    para.dispose();
    return LevelLayout(offsets, height);
  }

  /// Releases the per-token painters.
  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
    for (final p in linkGapPainters) {
      p?.dispose();
    }
  }
}
