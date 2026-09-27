import 'package:flutter/widgets.dart';

import 'semantic_zoom_controller.dart';

/// Makes a [SemanticZoomController] available to descendants such as
/// `LeveledTextView`. [SemanticZoomDetector] inserts one automatically.
class SemanticZoomScope extends InheritedWidget {
  /// Provides [controller] to [child]'s subtree.
  const SemanticZoomScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The provided controller.
  final SemanticZoomController controller;

  /// The nearest controller, or null.
  static SemanticZoomController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SemanticZoomScope>()
      ?.controller;

  /// The nearest controller. Throws if there is none.
  static SemanticZoomController of(BuildContext context) {
    final c = maybeOf(context);
    assert(
      c != null,
      'No SemanticZoomScope found. Wrap the list in a SemanticZoomDetector '
      'or pass a controller explicitly.',
    );
    return c!;
  }

  @override
  bool updateShouldNotify(SemanticZoomScope oldWidget) =>
      oldWidget.controller != controller;
}
