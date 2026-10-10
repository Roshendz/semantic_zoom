part of 'leveled_text_view.dart';

/// Where every token sits at one detail level.
class LevelLayout {
  /// Creates a layout. Use [LeveledTextLayout.layoutFor] instead.
  const LevelLayout(
    this.offsets,
    this.height, {
    this.width = 0,
    this.ellipsis,
  });

  /// Top-left of each token, indexed like [LeveledText.tokens]. `null` means
  /// hidden at this level.
  final List<Offset?> offsets;

  /// Total height of the laid-out text.
  final double height;

  /// Width of the laid-out text: the width it was laid out for, or, for an
  /// unbounded width, the width of its longest line.
  final double width;

  /// Where "…" is drawn when the text was cut short by `maxLines` with
  /// [TextOverflow.ellipsis]; otherwise null.
  final Offset? ellipsis;
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
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  })  : assert(maxLines == null || maxLines > 0),
        _style = style,
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

  /// How lines are aligned, as in [Text.textAlign].
  final TextAlign textAlign;

  /// The most lines shown at any level, or null for no limit. Words past
  /// the limit are hidden.
  final int? maxLines;

  /// How text cut short by [maxLines] ends: [TextOverflow.ellipsis] adds
  /// "…" after the last whole word that fits; the other values just cut.
  final TextOverflow overflow;

  /// Paints the "…" for [TextOverflow.ellipsis].
  late final TextPainter _ellipsisPainter = _painter(
    TextSpan(text: _ellipsis, style: _style),
  )..layout();

  static const _ellipsis = '\u2026';

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

  /// The text shown at [level] as one span per paragraph, styled exactly as
  /// it is measured and drawn. A `RichText` per paragraph, stacked with
  /// [paragraphGap] between them, looks the same as the morphing view at
  /// rest; the view uses this to make text selectable.
  List<TextSpan> _paragraphsAt(int level, double maxWidth) {
    final layout = layoutFor(level, maxWidth);
    return [
      for (final p in _build(
        level,
        keep: maxLines == null ? null : _kept(layout),
        ellipsis: layout.ellipsis != null,
      ).paragraphs)
        TextSpan(style: _style, children: p),
    ];
  }

  static Set<int> _kept(LevelLayout layout) => {
        for (var i = 0; i < layout.offsets.length; i++)
          if (layout.offsets[i] != null) i,
      };

  _Built _build(int level, {Set<int>? keep, bool ellipsis = false}) {
    final tokens = text.tokens;
    // The paragraph is built from styled spans so bold, italic and links are
    // measured exactly as they are painted.
    final spans = <InlineSpan>[];
    final paragraphs = <List<InlineSpan>>[[]];
    var length = 0;
    void add(String s, [TextStyle? style]) {
      final span = TextSpan(text: s, style: style);
      spans.add(span);
      if (s == '\n') {
        paragraphs.add([]);
      } else {
        paragraphs.last.add(span);
      }
      length += s.length;
    }

    final ranges = List<(int, int)?>.filled(tokens.length, null);
    final paragraphOf = List<int>.filled(tokens.length, 0);
    var paragraph = 0;
    var pendingBreak = false;
    LeveledToken? previous;

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (!t.isVisibleAt(level)) continue;
      if (keep != null && !t.isBreak && !keep.contains(i)) continue;
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
        // A space inside a multi-word link carries the link's colour and
        // underline (which don't change its width), so selectable text
        // shows one continuous link, like the morphing view.
        add(
            ' ',
            previous?.link != null && previous!.link == t.link
                ? _decorationOf(styleOf(t))
                : null);
      }
      final start = length;
      add(t.text, styleOf(t));
      ranges[i] = (start, length);
      paragraphOf[i] = paragraph;
      previous = t;
    }
    (int, int)? ellipsisRange;
    if (ellipsis) {
      final start = length;
      add(_ellipsis);
      ellipsisRange = (start, length);
    }
    return _Built(
      spans,
      paragraphs,
      ranges,
      paragraphOf,
      paragraph,
      length,
      ellipsisRange,
    );
  }

  static TextStyle _decorationOf(TextStyle s) => TextStyle(
        color: s.color,
        decoration: s.decoration,
        decorationColor: s.decorationColor,
        decorationStyle: s.decorationStyle,
        decorationThickness: s.decorationThickness,
      );

  LevelLayout _compute(int level, double maxWidth) {
    var built = _build(level);
    var para = _layoutParagraph(built, maxWidth);
    var offsets = _offsetsIn(built, para);

    // Cut short with an ellipsis: keep whole words only, then lay the text
    // out again with "…" after them so alignment still holds. Drop words
    // from the end until it fits.
    if (overflow == TextOverflow.ellipsis && para.didExceedMaxLines) {
      final keep = _kept(LevelLayout(offsets, 0));
      while (true) {
        para.dispose();
        built = _build(level, keep: keep, ellipsis: true);
        para = _layoutParagraph(built, maxWidth);
        if (!para.didExceedMaxLines || keep.isEmpty) break;
        keep.remove(keep.reduce(math.max));
      }
      offsets = _offsetsIn(built, para);
    }

    Offset? ellipsis;
    final e = built.ellipsisRange;
    if (e != null) {
      final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: e.$1, extentOffset: e.$2),
      );
      if (boxes.isNotEmpty) {
        ellipsis = Offset(
          boxes.first.left,
          boxes.first.top + built.paragraph * paragraphGap,
        );
      }
    }

    // Only paragraphs with shown words add a gap.
    var paragraphs = 0;
    for (var i = 0; i < offsets.length; i++) {
      if (offsets[i] != null) {
        paragraphs = math.max(paragraphs, built.paragraphOf[i]);
      }
    }
    final height =
        built.length == 0 ? 0.0 : para.height + paragraphs * paragraphGap;
    final width = built.length == 0 ? 0.0 : para.width;
    para.dispose();
    return LevelLayout(offsets, height, width: width, ellipsis: ellipsis);
  }

  TextPainter _layoutParagraph(_Built built, double maxWidth) =>
      // minWidth pins the paragraph to the full width; otherwise it shrinks
      // to its text and RTL lines would hug the left edge. With an unbounded
      // width it shrink-wraps to its longest line, like Text.
      TextPainter(
        text: TextSpan(style: _style, children: built.spans),
        textDirection: _textDirection,
        textScaler: _textScaler,
        textAlign: textAlign,
        maxLines: maxLines,
      )..layout(
          minWidth: maxWidth.isFinite ? maxWidth : 0,
          maxWidth: maxWidth,
        );

  List<Offset?> _offsetsIn(_Built built, TextPainter para) {
    final offsets = List<Offset?>.filled(text.tokens.length, null);
    for (var i = 0; i < offsets.length; i++) {
      final r = built.ranges[i];
      if (r == null) continue;
      final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: r.$1, extentOffset: r.$2),
      );
      // No box: cut off by maxLines.
      if (boxes.isEmpty) continue;
      // A token is one word, so normally one box. If a word is wider than
      // the line and the engine splits it, anchor at the first fragment.
      final box = boxes.first;
      offsets[i] =
          Offset(box.left, box.top + built.paragraphOf[i] * paragraphGap);
    }
    return offsets;
  }

  /// How far below a real paragraph's glyphs the morphing view draws them
  /// at [level]. Each word is painted at its tight glyph box, and the
  /// word's own painter adds the line's leading on top of that. Selectable
  /// text is shifted by this much so both look the same.
  double _glyphInsetAt(int level) {
    for (var i = 0; i < painters.length; i++) {
      final t = text.tokens[i];
      if (t.isBreak || !t.isVisibleAt(level)) continue;
      final boxes = painters[i].getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: t.text.length),
      );
      return boxes.isEmpty ? 0 : boxes.first.top;
    }
    return 0;
  }

  /// The narrowest width the text can take at [level] without breaking a
  /// word: its widest visible token.
  double _minIntrinsicWidthAt(int level) {
    var widest = 0.0;
    for (var i = 0; i < painters.length; i++) {
      final t = text.tokens[i];
      if (!t.isBreak && t.isVisibleAt(level) && painters[i].width > widest) {
        widest = painters[i].width;
      }
    }
    return widest;
  }

  /// Releases the per-token painters.
  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
    for (final p in linkGapPainters) {
      p?.dispose();
    }
    _ellipsisPainter.dispose();
  }
}

class _Built {
  _Built(
    this.spans,
    this.paragraphs,
    this.ranges,
    this.paragraphOf,
    this.paragraph,
    this.length,
    this.ellipsisRange,
  );

  final List<InlineSpan> spans;
  final List<List<InlineSpan>> paragraphs;
  final List<(int, int)?> ranges;
  final List<int> paragraphOf;
  final int paragraph;
  final int length;
  final (int, int)? ellipsisRange;

  ({
    List<InlineSpan> spans,
    List<(int, int)?> ranges,
    List<int> paragraphOf,
    int paragraph,
    int length,
  }) get record => (
        spans: spans,
        ranges: ranges,
        paragraphOf: paragraphOf,
        paragraph: paragraph,
        length: length,
      );
}
