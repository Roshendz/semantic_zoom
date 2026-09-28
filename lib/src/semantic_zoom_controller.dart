import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// Something that can hold its content still while the zoom changes, e.g.
/// [RenderSliverSemanticZoomList].
abstract interface class SemanticZoomAnchorClient {
  /// Pins the item under [globalPosition]. Returns whether one was found.
  bool captureAnchorAt(Offset globalPosition);

  /// Pins the first item visible at the leading edge.
  bool captureLeadingAnchor();

  /// Stops pinning.
  void releaseAnchor();
}

/// Drives a semantic zoom: a continuous [zoom] value (e.g. 0.0 → 2.0), the
/// discrete [level] it last settled on, and optional per-item levels.
///
/// [zoom] changes every frame during a pinch; listen to it only from paint
/// or animation code. The controller itself (a [ChangeNotifier]) notifies
/// only when a committed level changes (the global [level] or an
/// [itemLevel]), which is the right hook for persistence, analytics or state
/// management.
class SemanticZoomController extends ChangeNotifier {
  /// Creates a controller with [levelCount] discrete levels.
  ///
  /// [levelLabels], if given, names each level for screen readers (for
  /// example `['Brief', 'Summary', 'Full notes']`).
  SemanticZoomController({
    required TickerProvider vsync,
    this.levelCount = 3,
    int initialLevel = 0,
    SpringDescription? spring,
    this.levelLabels,
  })  : assert(levelCount >= 2),
        assert(levelLabels == null || levelLabels.length == levelCount),
        spring = spring ?? defaultSpring,
        _level = initialLevel.clamp(0, levelCount - 1) {
    _zoom = AnimationController.unbounded(
      vsync: vsync,
      value: _level.toDouble(),
    );
  }

  /// Slightly under-damped spring used when settling on a level.
  static final SpringDescription defaultSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 0.9);

  /// Number of discrete levels. Levels are `0 .. levelCount - 1`.
  final int levelCount;

  /// Spring used by [animateToLevel] and [setItemLevel].
  final SpringDescription spring;

  /// Optional screen-reader names for each level.
  final List<String>? levelLabels;

  late final AnimationController _zoom;
  int _level;
  final _clients = <SemanticZoomAnchorClient>{};
  int _anchorGeneration = 0;
  bool _pinchAnchored = false;

  /// When true, level changes jump instead of animating. The detector keeps
  /// this in sync with `MediaQuery.disableAnimations`.
  bool reduceMotion = false;

  /// Highest level index.
  int get maxLevel => levelCount - 1;

  /// Continuous zoom value. Can briefly exceed `0..maxLevel` while
  /// rubber-banding.
  Animation<double> get zoom => _zoom;

  /// Current continuous zoom value.
  double get value => _zoom.value;

  /// Sets the continuous zoom directly (used while a gesture is active).
  set value(double v) => _zoom.value = v;

  /// The level the zoom last settled on (or is settling towards).
  int get level => _level;

  /// Whether a global settle animation is running.
  bool get isAnimating => _zoom.isAnimating;

  /// Screen-reader text for [level].
  String labelForLevel(int level) =>
      levelLabels?[level] ?? 'Detail ${level + 1} of $levelCount';

  // ── anchoring ──

  /// Registers a client that keeps content anchored. Called by render
  /// objects on attach.
  void addAnchorClient(SemanticZoomAnchorClient client) => _clients.add(client);

  /// Unregisters an anchor client.
  void removeAnchorClient(SemanticZoomAnchorClient client) =>
      _clients.remove(client);

  /// Pins the item under [globalPosition] in every attached list.
  void anchorAt(Offset globalPosition) {
    _anchorGeneration++;
    for (final c in _clients) {
      c.captureAnchorAt(globalPosition);
    }
  }

  /// Pins the first visible item in every attached list.
  void anchorLeading() {
    _anchorGeneration++;
    for (final c in _clients) {
      c.captureLeadingAnchor();
    }
  }

  /// Stops anchoring after the current frame is laid out.
  void releaseAnchor() {
    final generation = _anchorGeneration;
    // Wait for layout so the final frame's correction still applies.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (generation != _anchorGeneration) return;
      for (final c in _clients) {
        c.releaseAnchor();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  bool get _anchorBusy => _zoom.isAnimating || _pinchAnchored;

  // ── global level ──

  /// Stops any settle animation, e.g. when a new gesture begins.
  void stop() => _zoom.stop();

  /// Settles every item on [target] with a spring, carrying [velocity]
  /// (levels/second). Per-item levels are cleared.
  ///
  /// Anchors the first visible item unless [anchor] is false or an anchor is
  /// already active (e.g. from a pinch). [animate] overrides [reduceMotion].
  Future<void> animateToLevel(
    int target, {
    double velocity = 0,
    bool anchor = true,
    bool? animate,
  }) async {
    target = target.clamp(0, maxLevel);
    if (anchor && !_anchorBusy) anchorLeading();
    _pinchAnchored = false;
    final animated = animate ?? !reduceMotion;
    _clearItems(animate: animated);
    _commit(target);

    final end = target.toDouble();
    if (!animated) {
      _zoom.value = end;
      releaseAnchor();
      return;
    }
    await _zoom
        .animateWith(SpringSimulation(spring, _zoom.value, end, velocity))
        .orCancel
        .then((_) => releaseAnchor(), onError: (Object _) {});
  }

  /// Jumps to [target] without animation.
  void jumpToLevel(int target) =>
      animateToLevel(target, animate: false, anchor: false);

  /// Sets the level immediately, without animating or anchoring. Meant for
  /// restoring saved state while the list is first built (the widgets'
  /// `restorationId` uses it); use [jumpToLevel] otherwise.
  ///
  /// Listeners are notified after the current frame, because notifying
  /// widgets elsewhere in the tree during a build isn't allowed.
  void restoreLevel(int level) {
    _zoom.stop();
    final target = level.clamp(0, maxLevel);
    final changed = target != _level;
    _level = target;
    _zoom.value = target.toDouble();
    if (changed) _notifyAfterFrame();
  }

  bool _notifyScheduled = false;
  bool _disposed = false;

  void _notifyAfterFrame() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Starts a gesture at [focalPoint]: stops settling, anchors there and
  /// returns every item to the global level.
  void beginGesture(Offset focalPoint) {
    _zoom.stop();
    anchorAt(focalPoint);
    _pinchAnchored = true;
    _clearItems(animate: !reduceMotion);
  }

  /// Ends a gesture, settling on the level [projected] rounds to.
  Future<void> endGesture({required double projected, double velocity = 0}) =>
      animateToLevel(projected.round(), velocity: velocity);

  void _commit(int target) {
    if (target == _level) return;
    _level = target;
    notifyListeners();
  }

  // ── per-item levels ──
  //
  // Each item's zoom is the global zoom plus an animated offset, so a global
  // pinch or level change can smoothly pull every item back by animating the
  // offsets to zero. Offsets run on a plain Ticker so the controller still
  // works with SingleTickerProviderStateMixin.

  final _items = <Object, _ItemZoom>{};
  Ticker? _itemTicker;
  Duration _itemElapsed = Duration.zero;
  int? _itemAnchorGeneration;

  _ItemZoom _item(Object id) => _items[id] ??= _ItemZoom(_zoom);

  /// What to listen to for item [id]'s zoom (the global [zoom] if null).
  Listenable listenableFor(Object? id) =>
      id == null ? _zoom : _item(id).listenable;

  /// Continuous zoom value for item [id] (the global [value] if null).
  double valueFor(Object? id) {
    if (id == null) return value;
    return value + (_items[id]?.offset ?? 0);
  }

  /// The committed level of item [id]: its own level if one was set with
  /// [setItemLevel], otherwise the global [level].
  int itemLevel(Object id) =>
      (_level + (_items[id]?.target ?? 0)).round().clamp(0, maxLevel);

  /// Whether any item has a level different from the global [level].
  bool get hasItemLevels => _items.values.any((i) => i.target != 0);

  /// Items whose level differs from the global [level], by item id.
  Map<Object, int> get itemLevels => Map.unmodifiable({
        for (final MapEntry(key: id, value: item) in _items.entries)
          if (item.target != 0) id: itemLevel(id),
      });

  /// Sets item levels immediately, without animating. The counterpart of
  /// [restoreLevel] for [itemLevels]; listeners are notified after the
  /// current frame.
  void restoreItemLevels(Map<Object, int> levels) {
    if (levels.isNotEmpty) _notifyAfterFrame();
    for (final MapEntry(key: id, value: level) in levels.entries) {
      final item = _item(id);
      final target = (level.clamp(0, maxLevel) - _level).toDouble();
      item
        ..sim = null
        ..target = target
        ..offset = target
        ..notifyListeners();
    }
  }

  /// Moves only item [id] to [target], e.g. on tap. Other items keep the
  /// global level. The next pinch or [animateToLevel] clears it.
  void setItemLevel(Object id, int target, {bool? animate}) {
    target = target.clamp(0, maxLevel);
    final before = itemLevel(id);
    if (!_anchorBusy && _itemTicker?.isActive != true) {
      anchorLeading();
      _itemAnchorGeneration = _anchorGeneration;
    }
    _animateItem(_item(id), (target - _level).toDouble(), animate);
    if (itemLevel(id) != before) notifyListeners();
  }

  /// Returns every item to the global [level].
  void clearItemLevels({bool? animate}) {
    final changed = hasItemLevels;
    _clearItems(animate: animate ?? !reduceMotion);
    if (changed) notifyListeners();
  }

  void _clearItems({required bool animate}) {
    for (final item in _items.values) {
      if (item.target != 0 || item.offset != 0) {
        _animateItem(item, 0, animate);
      }
    }
  }

  void _animateItem(_ItemZoom item, double target, bool? animate) {
    item.target = target;
    if (!(animate ?? !reduceMotion)) {
      item
        ..sim = null
        ..offset = target
        ..notifyListeners();
      _maybeReleaseItemAnchor();
      return;
    }
    final ticker = _itemTicker ??= Ticker(_tickItems, debugLabel: 'items');
    if (!ticker.isActive) {
      _itemElapsed = Duration.zero;
      ticker.start();
    }
    final t = item.sim == null
        ? 0.0
        : (_itemElapsed - item.simStart).inMicroseconds / 1e6;
    final velocity = item.sim?.dx(t) ?? 0;
    item
      ..sim = SpringSimulation(spring, item.offset, target, velocity)
      ..simStart = _itemElapsed;
  }

  void _tickItems(Duration elapsed) {
    _itemElapsed = elapsed;
    var active = false;
    for (final item in _items.values) {
      final sim = item.sim;
      if (sim == null) continue;
      final t = (elapsed - item.simStart).inMicroseconds / 1e6;
      if (sim.isDone(t)) {
        item
          ..sim = null
          ..offset = item.target;
      } else {
        item.offset = sim.x(t);
        active = true;
      }
      item.notifyListeners();
    }
    if (!active) {
      _itemTicker!.stop();
      _maybeReleaseItemAnchor();
    }
  }

  void _maybeReleaseItemAnchor() {
    // Only release an anchor the item animation took; a pinch or global
    // settle that started since owns the current one.
    if (_itemAnchorGeneration == _anchorGeneration) releaseAnchor();
    _itemAnchorGeneration = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _zoom.dispose();
    _itemTicker?.dispose();
    for (final item in _items.values) {
      item.dispose();
    }
    _items.clear();
    _clients.clear();
    super.dispose();
  }
}

class _ItemZoom extends ChangeNotifier {
  _ItemZoom(Listenable global) {
    listenable = Listenable.merge([global, this]);
  }

  late final Listenable listenable;
  double offset = 0;
  double target = 0;
  SpringSimulation? sim;
  Duration simStart = Duration.zero;
}
