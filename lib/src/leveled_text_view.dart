import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'leveled_text.dart';
import 'leveled_text_layout.dart';
import 'semantic_zoom_controller.dart';
import 'semantic_zoom_scope.dart';

/// Shows [text] at the controller's current zoom, morphing between levels.
///
/// The font size never changes. Words present in both adjacent levels slide
/// to their new position; words only in the richer level fade in where they
/// will end up.
///
/// Give each view an [itemId] to let it zoom on its own via
/// [SemanticZoomController.setItemLevel] (for example on tap).
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
    this.paragraphGap = 6,
    this.moveCurve = Curves.easeInOutCubic,
    this.fadeCurve = const Interval(0.25, 1),
  });

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
        animation: controller.listenableFor(id),
        builder: (context, _) {
          final z = controller.valueFor(id).clamp(0.0, maxLevel.toDouble());
          final lo = math.min(z.floor(), maxLevel);
          final hi = math.min(lo + 1, maxLevel);
          final from = layout.layoutFor(lo, constraints.maxWidth);
          final to = layout.layoutFor(hi, constraints.maxWidth);
          final move = widget.moveCurve.transform(z - lo);
          final shown = z.round();

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
              child: CustomPaint(
                painter: _MorphPainter(
                  layout,
                  from,
                  to,
                  move,
                  z,
                  widget.fadeCurve,
                ),
              ),
            ),
          );
        },
      ),
    );
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

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.l, this.from, this.to, this.move, this.z, this.fade);

  final LeveledTextLayout l;
  final LevelLayout from, to;
  final double move;
  final double z;
  final Curve fade;

  @override
  void paint(Canvas canvas, Size size) {
    final tokens = l.text.tokens;
    // Tokens fading together share an opacity, so they are grouped into one
    // layer per opacity instead of one saveLayer per word.
    final fading = <double, List<(int, Offset)>>{};

    for (var i = 0; i < tokens.length; i++) {
      final a = from.offsets[i], b = to.offsets[i];
      if (a == null && b == null) continue;

      final opacity = _opacity(tokens[i]);
      if (opacity <= 0) continue;

      final pos =
          (a != null && b != null) ? Offset.lerp(a, b, move)! : (a ?? b)!;
      if (opacity >= 1) {
        l.painters[i].paint(canvas, pos);
      } else {
        (fading[opacity] ??= []).add((i, pos));
      }
    }

    for (final MapEntry(key: opacity, value: items) in fading.entries) {
      var bounds = Rect.zero;
      for (final (i, pos) in items) {
        final r = pos & l.painters[i].size;
        bounds = bounds.isEmpty ? r : bounds.expandToInclude(r);
      }
      canvas.saveLayer(
        bounds.inflate(2),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      for (final (i, pos) in items) {
        l.painters[i].paint(canvas, pos);
      }
      canvas.restore();
    }
  }

  // A token shown from level L fades in over z in (L-1, L]; one dropped
  // after level M fades out over z in [M, M+1). Dropped words leave early,
  // and on levels that replace words the new ones arrive late, so the two
  // never overlap. Pure additions use [fade].
  static const _fadeOut = Interval(0, 0.4, curve: Curves.easeOut);
  static const _lateFadeIn = Interval(0.45, 1);

  double _opacity(LeveledToken t) {
    final tIn = (z - t.minLevel + 1).clamp(0.0, 1.0);
    final fadeIn = l.rewrittenLevels.contains(t.minLevel)
        ? _lateFadeIn.transform(tIn)
        : fade.transform(tIn);
    final max = t.maxLevel;
    if (max == null) return fadeIn;
    final fadeOut = 1 - _fadeOut.transform((z - max).clamp(0.0, 1.0));
    return fadeIn < fadeOut ? fadeIn : fadeOut;
  }

  @override
  bool shouldRepaint(_MorphPainter o) =>
      o.move != move ||
      o.z != z ||
      o.from != from ||
      o.to != to ||
      o.l != l ||
      o.fade != fade;
}
