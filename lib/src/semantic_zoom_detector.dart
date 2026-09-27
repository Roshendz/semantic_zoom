import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'semantic_zoom_controller.dart';
import 'semantic_zoom_scope.dart';

/// Builds the scrollable child. [isPinching] is true while a pinch is
/// active; disable scrolling then, e.g. with [NeverScrollableScrollPhysics].
typedef SemanticZoomWidgetBuilder = Widget Function(
  BuildContext context,
  bool isPinching,
);

/// Turns pinch gestures into semantic-zoom changes on [controller].
///
/// Handles touch pinch (two pointers), trackpad pinch (pan/zoom events),
/// ctrl + scroll-wheel / Safari pinch on the web (scale signals), and
/// Ctrl/⌘ `+` / `-` / `0` on a keyboard once the list has focus (clicking or
/// tapping it gives it focus).
///
/// It uses a raw [Listener] rather than a scale recognizer on purpose: a
/// scrollable's drag recognizer wins the gesture arena for the first finger,
/// so a scale recognizer would only ever see the second one.
///
/// Also provides [controller] to descendants via [SemanticZoomScope], and
/// keeps [SemanticZoomController.reduceMotion] in sync with the platform's
/// reduce-motion setting.
class SemanticZoomDetector extends StatefulWidget {
  /// Creates a detector.
  const SemanticZoomDetector({
    super.key,
    required this.controller,
    required this.builder,
    this.levelsPerDoubling = 1.6,
    this.overscrollResistance = 0.25,
    this.flingProjection = const Duration(milliseconds: 120),
    this.enableHaptics = true,
    this.enableKeyboardShortcuts = true,
  });

  /// The controller to drive.
  final SemanticZoomController controller;

  /// Builds the scrollable content.
  final SemanticZoomWidgetBuilder builder;

  /// How many levels one doubling of finger distance moves. Higher is more
  /// sensitive.
  final double levelsPerDoubling;

  /// Fraction of movement applied past the first/last level (rubber band).
  final double overscrollResistance;

  /// How far pinch velocity is projected forward when choosing the level to
  /// settle on.
  final Duration flingProjection;

  /// Whether to play a selection haptic when the level changes.
  final bool enableHaptics;

  /// Whether Ctrl/⌘ `+`, `-` and `0` change the level.
  final bool enableKeyboardShortcuts;

  @override
  State<SemanticZoomDetector> createState() => _SemanticZoomDetectorState();
}

class _SemanticZoomDetectorState extends State<SemanticZoomDetector> {
  static const _panZoomStartThreshold = 0.03; // log2 scale before we engage
  static const _signalSettleDelay = Duration(milliseconds: 160);

  SemanticZoomController get _c => widget.controller;

  final _pointers = <int, Offset>{};
  bool _pinching = false;
  double _startDistance = 1;
  double _startZoom = 0;
  double _velocity = 0;
  double _lastZoom = 0;
  Duration _lastTime = Duration.zero;

  bool _panZoomPending = false;
  Timer? _signalTimer;
  final _focus = FocusNode(debugLabel: 'SemanticZoomDetector');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(SemanticZoomDetector old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _c.reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    }
  }

  @override
  void dispose() {
    _signalTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // ── shared ──

  void _begin(Offset focal, Duration time) {
    _signalTimer?.cancel();
    _c.beginGesture(focal);
    _startZoom = _c.value;
    _lastZoom = _c.value;
    _lastTime = time;
    _velocity = 0;
    setState(() => _pinching = true);
  }

  void _update(double scale, Duration time) {
    final raw = _startZoom +
        math.log(math.max(scale, 1e-3)) / math.ln2 * widget.levelsPerDoubling;
    final z = _rubberBand(raw);
    final dt = (time - _lastTime).inMicroseconds / 1e6;
    if (dt > 0) {
      // Light smoothing so one jittery sample doesn't decide the snap.
      _velocity = 0.7 * _velocity + 0.3 * ((z - _lastZoom) / dt);
    }
    _lastZoom = z;
    _lastTime = time;
    _c.value = z;
  }

  void _end() {
    if (!mounted || !_pinching) return;
    setState(() => _pinching = false);
    final projection = widget.flingProjection.inMicroseconds / 1e6;
    final before = _c.level;
    _c.endGesture(
      projected: _c.value + _velocity * projection,
      velocity: _velocity,
    );
    if (widget.enableHaptics && _c.level != before) {
      HapticFeedback.selectionClick();
    }
  }

  double _rubberBand(double z) {
    final max = _c.maxLevel.toDouble();
    if (z < 0) return z * widget.overscrollResistance;
    if (z > max) return max + (z - max) * widget.overscrollResistance;
    return z;
  }

  // ── touch ──

  void _onDown(PointerDownEvent e) {
    if (widget.enableKeyboardShortcuts && !_focus.hasFocus) {
      _focus.requestFocus();
    }
    if (e.kind != PointerDeviceKind.touch &&
        e.kind != PointerDeviceKind.stylus) {
      return;
    }
    // A new touch during a settle means the user is taking over.
    if (_pointers.isEmpty && _c.isAnimating) _c.releaseAnchor();
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && !_pinching) {
      final p = _pointers.values.toList();
      _startDistance = math.max((p[0] - p[1]).distance, 1);
      _begin((p[0] + p[1]) / 2, e.timeStamp);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (!_pinching || _pointers.length < 2) return;
    final p = _pointers.values.take(2).toList();
    _update((p[0] - p[1]).distance / _startDistance, e.timeStamp);
  }

  void _onUpOrCancel(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    if (_pointers.length < 2) _end();
  }

  // ── trackpad ──

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _panZoomPending = true;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    // Two-finger trackpad *scroll* also arrives here with scale == 1; only
    // engage once the fingers actually pinch, so scrolling keeps working.
    if (_panZoomPending) {
      if ((math.log(e.scale) / math.ln2).abs() < _panZoomStartThreshold) {
        return;
      }
      _panZoomPending = false;
      _begin(e.position, e.timeStamp);
      _startZoom -= math.log(e.scale) / math.ln2 * widget.levelsPerDoubling;
    }
    if (_pinching) _update(e.scale, e.timeStamp);
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent e) {
    _panZoomPending = false;
    _end();
  }

  // ── web ctrl+wheel / Safari pinch ──

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScaleEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final scale = (event as PointerScaleEvent).scale;
      if (!_pinching) {
        _begin(event.position, event.timeStamp);
        _startDistance = 1;
      }
      _startDistance *= scale;
      _update(_startDistance, event.timeStamp);
      _signalTimer?.cancel();
      _signalTimer = Timer(_signalSettleDelay, _end);
    });
  }

  // ── keyboard ──

  void _step(int delta) {
    final before = _c.level;
    _c.animateToLevel(before + delta);
    if (widget.enableHaptics && _c.level != before) {
      HapticFeedback.selectionClick();
    }
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    void more() => _step(1);
    void less() => _step(-1);
    void reset() => _step(-_c.level);
    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final (control, meta) in [(true, false), (false, true)]) {
      SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) =>
          SingleActivator(k, control: control, meta: meta, shift: shift);
      bindings
        ..[key(LogicalKeyboardKey.equal)] = more
        ..[key(LogicalKeyboardKey.equal, shift: true)] = more // "+"
        ..[key(LogicalKeyboardKey.numpadAdd)] = more
        ..[key(LogicalKeyboardKey.minus)] = less
        ..[key(LogicalKeyboardKey.numpadSubtract)] = less
        ..[key(LogicalKeyboardKey.digit0)] = reset
        ..[key(LogicalKeyboardKey.numpad0)] = reset;
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUpOrCancel,
      onPointerCancel: _onUpOrCancel,
      onPointerPanZoomStart: _onPanZoomStart,
      onPointerPanZoomUpdate: _onPanZoomUpdate,
      onPointerPanZoomEnd: _onPanZoomEnd,
      onPointerSignal: _onSignal,
      child: RawGestureDetector(
        gestures: {
          _PinchArenaClaim:
              GestureRecognizerFactoryWithHandlers<_PinchArenaClaim>(
            () => _PinchArenaClaim(debugOwner: this),
            (_) {},
          ),
        },
        child: widget.builder(context, _pinching),
      ),
    );
    if (widget.enableKeyboardShortcuts) {
      child = CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(focusNode: _focus, child: child),
      );
    }
    return SemanticZoomScope(controller: _c, child: child);
  }
}

/// Joins the gesture arena for every touch and wins it as soon as a second
/// finger lands, so taps, ink highlights and long presses under a pinch are
/// cancelled. With a single finger it stays out of the way: it withdraws on
/// pointer up, and a scroll or tap recognizer that claims first wins.
///
/// The pinch itself is still read by the [Listener], because a scrollable's
/// drag recognizer may already have won the first finger's arena.
class _PinchArenaClaim extends OneSequenceGestureRecognizer {
  _PinchArenaClaim({super.debugOwner})
      : super(
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
          },
        );

  final _down = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down.add(event.pointer);
    if (_down.length >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      // A lone finger lifting is a tap or the end of a scroll; step aside
      // before the arena is swept so the item underneath gets it.
      if (_down.length < 2) resolve(GestureDisposition.rejected);
      _down.remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    super.rejectGesture(pointer);
    _down.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) => _down.clear();

  @override
  String get debugDescription => 'semantic zoom pinch';
}
