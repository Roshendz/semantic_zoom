import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'leveled_text.dart';
import 'leveled_text_layout.dart';
import 'leveled_text_loader.dart';
import 'semantic_zoom_controller.dart';
import 'semantic_zoom_scope.dart';

part 'lazy_leveled_text_view.dart';

/// Shows [text] at the controller's current zoom, morphing between levels.
///
/// The font size never changes. Words present in both adjacent levels slide
/// to their new position; words only in the richer level fade in where they
/// will end up.
///
/// Give each view an [itemId] to let it zoom on its own via
/// [SemanticZoomController.setItemLevel] (for example on tap).
///
/// Links from `[label](url)` markup are drawn with [linkStyle] and, when
/// [onLinkTap] is set, become tap targets (and links for screen readers).
///
/// Screen readers get the text at the nearest level and, when
/// [adjustable] is true, can step the detail up or down with the platform's
/// adjust gesture (swipe up/down on VoiceOver, volume keys on TalkBack).
class LeveledTextView extends StatefulWidget {
  /// Creates a view. Uses the nearest [SemanticZoomScope] unless
  /// [controller] is given.
  const LeveledTextView(
    this.text, {
    super.key,
    this.itemId,
    this.adjustable = true,
    this.controller,
    this.style,
    this.linkStyle = defaultLinkStyle,
    this.onLinkTap,
    this.paragraphGap = 6,
    this.moveCurve = Curves.easeInOutCubic,
    this.fadeCurve = const Interval(0.25, 1),
  }) : _cap = null;

  // Used by LazyLeveledTextView: shows at most this zoom (in levels) while
  // longer versions are loading, then follows it up as they are revealed.
  const LeveledTextView._capped(
    this.text, {
    required ValueListenable<double> cap,
    this.itemId,
    this.adjustable = true,
    this.controller,
    this.style,
    this.linkStyle = defaultLinkStyle,
    this.onLinkTap,
  })  : _cap = cap,
        paragraphGap = 6,
        moveCurve = Curves.easeInOutCubic,
        fadeCurve = const Interval(0.25, 1);

  final ValueListenable<double>? _cap;

  /// Underlined, in the surrounding text colour.
  static const defaultLinkStyle = TextStyle(
    decoration: TextDecoration.underline,
  );

  /// The text to display.
  final LeveledText text;

  /// Identifies this item for per-item zoom. When null the view always
  /// follows the global level.
  final Object? itemId;

  /// Whether screen readers can change the detail level from this view.
  /// Adjusts this item if [itemId] is set, otherwise the whole list.
  final bool adjustable;

  /// Controller to follow. Defaults to [SemanticZoomScope.of].
  final SemanticZoomController? controller;

  /// Merged onto the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Merged onto link words, e.g. to add a colour.
  final TextStyle? linkStyle;

  /// Called with a link's target when it is tapped. Without it, links are
  /// styled but not interactive.
  final ValueChanged<String>? onLinkTap;

  /// Extra space between paragraphs.
  final double paragraphGap;

  /// Easing for words sliding between positions.
  final Curve moveCurve;

  /// Easing for new words fading in. The default starts slightly after the
  /// reflow begins.
  final Curve fadeCurve;

  @override
  State<LeveledTextView> createState() => _LeveledTextViewState();
}

class _LeveledTextViewState extends State<LeveledTextView> {
  LeveledTextLayout? _layout;
  TextStyle? _style;
  TextScaler? _scaler;
  TextDirection? _direction;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LeveledTextView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text ||
        old.style != widget.style ||
        old.linkStyle != widget.linkStyle ||
        old.paragraphGap != widget.paragraphGap) {
      _layout?.dispose();
      _layout = null;
    }
    _sync();
  }

  void _sync() {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final direction = Directionality.of(context);
    if (_layout != null &&
        style == _style &&
        scaler == _scaler &&
        direction == _direction) {
      return;
    }
    _style = style;
    _scaler = scaler;
    _direction = direction;
    _layout?.dispose();
    _layout = LeveledTextLayout(
      widget.text,
      style: style,
      textScaler: scaler,
      textDirection: direction,
      paragraphGap: widget.paragraphGap,
      linkStyle: widget.linkStyle,
    );
  }

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? SemanticZoomScope.of(context);
    final layout = _layout!;
    final maxLevel = controller.maxLevel;
    final id = widget.itemId;

    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: widget._cap == null
            ? controller.listenableFor(id)
            : Listenable.merge([controller.listenableFor(id), widget._cap]),
        builder: (context, _) {
          final cap = widget._cap;
          final raw = controller.valueFor(id);
          final z = (cap == null ? raw : math.min(raw, cap.value))
              .clamp(0.0, maxLevel.toDouble());
          final lo = math.min(z.floor(), maxLevel);
          final hi = math.min(lo + 1, maxLevel);
          final from = layout.layoutFor(lo, constraints.maxWidth);
          final to = layout.layoutFor(hi, constraints.maxWidth);
          final move = widget.moveCurve.transform(z - lo);
          final frame = _Frame(layout, from, to, move, z, widget.fadeCurve);
          final shown = z.round();

          Widget content = CustomPaint(painter: _MorphPainter(frame));
          if (widget.onLinkTap != null) {
            content = Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: content),
                ..._linkTargets(frame),
              ],
            );
          }

          return Semantics(
            label: widget.text.textAt(shown),
            value: widget.adjustable ? controller.labelForLevel(shown) : null,
            increasedValue: widget.adjustable && shown < maxLevel
                ? controller.labelForLevel(shown + 1)
                : null,
            decreasedValue: widget.adjustable && shown > 0
                ? controller.labelForLevel(shown - 1)
                : null,
            onIncrease: widget.adjustable && shown < maxLevel
                ? () => _step(controller, shown + 1)
                : null,
            onDecrease: widget.adjustable && shown > 0
                ? () => _step(controller, shown - 1)
                : null,
            child: SizedBox(
              width: constraints.maxWidth,
              height: lerpDouble(from.height, to.height, move),
              child: content,
            ),
          );
        },
      ),
    );
  }

  /// One tap target per visible link word, placed where the word is drawn
  /// this frame. The first word of each link also carries its semantics.
  List<Widget> _linkTargets(_Frame frame) {
    final tokens = widget.text.tokens;
    final onTap = widget.onLinkTap!;
    final targets = <Widget>[];
    for (var i = 0; i < tokens.length; i++) {
      final link = tokens[i].link;
      if (link == null) continue;
      final startsLink = i == 0 || tokens[i - 1].link != link;
      final pos = frame.positions[i];
      if (pos == null || frame.opacities[i] < 0.5) continue;
      final size = frame.layout.painters[i].size;
      Widget target = GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => onTap(link),
        child: const MouseRegion(cursor: SystemMouseCursors.click),
      );
      target = startsLink
          ? Semantics(
              container: true,
              link: true,
              label: _linkLabel(i),
              onTap: () => onTap(link),
              child: target,
            )
          : ExcludeSemantics(child: target);
      targets.add(
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: size.width,
          height: size.height,
          child: target,
        ),
      );
    }
    return targets;
  }

  String _linkLabel(int start) {
    final tokens = widget.text.tokens;
    final link = tokens[start].link;
    final b = StringBuffer(tokens[start].text);
    for (var i = start + 1; i < tokens.length && tokens[i].link == link; i++) {
      if (!tokens[i].glued) b.write(' ');
      b.write(tokens[i].text);
    }
    return b.toString();
  }

  void _step(SemanticZoomController controller, int level) {
    final id = widget.itemId;
    if (id != null) {
      controller.setItemLevel(id, level);
    } else {
      controller.animateToLevel(level);
    }
  }
}

/// Where every token is drawn this frame, and how opaque it is.
class _Frame {
  _Frame(this.layout, this.from, this.to, this.move, this.z, this.fade)
      : positions = List.filled(layout.text.tokens.length, null),
        opacities = List.filled(layout.text.tokens.length, 0) {
    final tokens = layout.text.tokens;
    for (var i = 0; i < tokens.length; i++) {
      final a = from.offsets[i], b = to.offsets[i];
      if (a == null && b == null) continue;
      positions[i] =
          (a != null && b != null) ? Offset.lerp(a, b, move)! : (a ?? b)!;
      opacities[i] = _opacity(tokens[i]);
    }
  }

  final LeveledTextLayout layout;
  final LevelLayout from, to;
  final double move;
  final double z;
  final Curve fade;
  final List<Offset?> positions;
  final List<double> opacities;

  // A token shown from level L fades in over z in (L-1, L]; one dropped
  // after level M fades out over z in [M, M+1). Dropped words leave early,
  // and on levels that replace words the new ones arrive late, so the two
  // never overlap. Pure additions use [fade].
  static const _fadeOut = Interval(0, 0.4, curve: Curves.easeOut);
  static const _lateFadeIn = Interval(0.45, 1);

  double _opacity(LeveledToken t) {
    final tIn = (z - t.minLevel + 1).clamp(0.0, 1.0);
    final fadeIn = layout.rewrittenLevels.contains(t.minLevel)
        ? _lateFadeIn.transform(tIn)
        : fade.transform(tIn);
    final max = t.maxLevel;
    if (max == null) return fadeIn;
    final fadeOut = 1 - _fadeOut.transform((z - max).clamp(0.0, 1.0));
    return fadeIn < fadeOut ? fadeIn : fadeOut;
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.f);

  final _Frame f;

  @override
  void paint(Canvas canvas, Size size) {
    final painters = f.layout.painters;
    // Tokens fading together share an opacity, so they are grouped into one
    // layer per opacity instead of one saveLayer per word.
    final fading = <double, List<int>>{};

    for (var i = 0; i < painters.length; i++) {
      final pos = f.positions[i];
      final opacity = f.opacities[i];
      if (pos == null || opacity <= 0) continue;
      if (opacity >= 1) {
        painters[i].paint(canvas, pos);
      } else {
        (fading[opacity] ??= []).add(i);
      }
    }

    _paintLinkGaps(canvas);

    for (final MapEntry(key: opacity, value: items) in fading.entries) {
      var bounds = Rect.zero;
      for (final i in items) {
        final r = f.positions[i]! & painters[i].size;
        bounds = bounds.isEmpty ? r : bounds.expandToInclude(r);
      }
      canvas.saveLayer(
        bounds.inflate(2),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      for (final i in items) {
        painters[i].paint(canvas, f.positions[i]!);
      }
      canvas.restore();
    }
  }

  /// Paints an underlined space between words of the same link that sit
  /// next to each other on one line, clipped to the actual gap.
  void _paintLinkGaps(Canvas canvas) {
    final painters = f.layout.painters;
    final gaps = f.layout.linkGapPainters;
    for (var i = 0; i < gaps.length; i++) {
      final gap = gaps[i];
      if (gap == null) continue; // only set when a next link word exists
      final a = f.positions[i], b = f.positions[i + 1];
      if (a == null || b == null) continue;
      if ((a.dy - b.dy).abs() > 0.5) continue; // the link wraps here
      final start = a.dx + painters[i].width;
      if (b.dx <= start || b.dx - start > gap.width * 2) continue;
      final opacity = math.min(f.opacities[i], f.opacities[i + 1]);
      if (opacity <= 0) continue;
      final clip = Rect.fromLTRB(start, a.dy, b.dx, a.dy + gap.height);
      canvas.save();
      canvas.clipRect(clip);
      if (opacity < 1) {
        canvas.saveLayer(
            clip, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      }
      gap.paint(canvas, Offset(start, a.dy));
      if (opacity < 1) canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MorphPainter o) =>
      o.f.move != f.move ||
      o.f.z != f.z ||
      o.f.from != f.from ||
      o.f.to != f.to ||
      o.f.layout != f.layout ||
      o.f.fade != f.fade;
}
