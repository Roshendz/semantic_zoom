import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'semantic_zoom_controller.dart';
import 'semantic_zoom_scope.dart';

/// Creates, provides and disposes a [SemanticZoomController], so you don't
/// need a [StatefulWidget], a `vsync` or `dispose()` of your own. Like
/// [DefaultTabController].
///
/// ```dart
/// DefaultSemanticZoomController(
///   builder: (context, zoom) => SemanticZoomListView.builder(
///     controller: zoom,
///     itemCount: notes.length,
///     itemBuilder: (context, i) => LeveledTextView(notes[i], itemId: i),
///   ),
/// )
/// ```
///
/// Widgets below it can find the controller with
/// [DefaultSemanticZoomController.of], e.g. a row of level buttons.
class DefaultSemanticZoomController extends StatefulWidget {
  /// Creates the controller and builds [builder] with it.
  const DefaultSemanticZoomController({
    super.key,
    required this.builder,
    this.levelCount = 3,
    this.initialLevel = 0,
    this.levelLabels,
    this.spring,
    this.onLevelChanged,
  }) : assert(levelCount >= 2);

  /// Builds the content that uses the controller.
  final Widget Function(BuildContext context, SemanticZoomController zoom)
      builder;

  /// See [SemanticZoomController.levelCount]. Changing it keeps the current
  /// level where possible.
  final int levelCount;

  /// The level shown first.
  final int initialLevel;

  /// See [SemanticZoomController.levelLabels].
  final List<String>? levelLabels;

  /// See [SemanticZoomController.spring].
  final SpringDescription? spring;

  /// Called when the list-wide level changes, e.g. to save it.
  final ValueChanged<int>? onLevelChanged;

  /// The nearest controller above [context]: from a
  /// [DefaultSemanticZoomController], a [SemanticZoomDetector] or a
  /// [SemanticZoomScope]. Throws a [FlutterError] if there is none.
  static SemanticZoomController of(BuildContext context) =>
      SemanticZoomScope.of(context);

  /// Like [of], but returns null when there is no controller.
  static SemanticZoomController? maybeOf(BuildContext context) =>
      SemanticZoomScope.maybeOf(context);

  @override
  State<DefaultSemanticZoomController> createState() =>
      _DefaultSemanticZoomControllerState();
}

class _DefaultSemanticZoomControllerState
    extends State<DefaultSemanticZoomController> with TickerProviderStateMixin {
  late SemanticZoomController _zoom;
  // Set in initState: a lazy initializer would first run inside the
  // listener, after the level had already changed.
  late int _lastLevel;

  @override
  void initState() {
    super.initState();
    _zoom = _create(widget.initialLevel);
    _lastLevel = _zoom.level;
  }

  SemanticZoomController _create(int level) => SemanticZoomController(
        vsync: this,
        levelCount: widget.levelCount,
        initialLevel: level,
        levelLabels: widget.levelLabels,
        spring: widget.spring,
      )..addListener(_changed);

  void _changed() {
    if (_zoom.level == _lastLevel) return;
    _lastLevel = _zoom.level;
    widget.onLevelChanged?.call(_zoom.level);
  }

  @override
  void didUpdateWidget(DefaultSemanticZoomController old) {
    super.didUpdateWidget(old);
    if (old.levelCount != widget.levelCount ||
        !listEquals(old.levelLabels, widget.levelLabels) ||
        old.spring != widget.spring) {
      final previous = _zoom;
      _zoom = _create(previous.level);
      _lastLevel = _zoom.level;
      // Dispose after the frame: widgets below still hold the old one
      // until they rebuild with the new controller.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SemanticZoomScope(
        controller: _zoom,
        child: Builder(builder: (context) => widget.builder(context, _zoom)),
      );
}
