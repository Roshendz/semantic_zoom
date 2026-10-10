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

  /// The nearest controller. Throws a [FlutterError] explaining how to fix
  /// it if there is none.
  static SemanticZoomController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller != null) return controller;
    throw FlutterError.fromParts([
      ErrorSummary(
          'No SemanticZoomController found for ${context.widget.runtimeType}.'),
      ErrorDescription(
        'LeveledTextView and LazyLeveledTextView follow the controller of '
        'the list they are in. This one is not inside a SemanticZoomDetector, '
        'SemanticZoomListView, SemanticZoomGridView or '
        'DefaultSemanticZoomController, and no controller was passed.',
      ),
      ErrorHint(
        'Wrap the list in one of those, or pass a controller: '
        'LeveledTextView(text, controller: zoom). For a single text that '
        'expands on tap, use ExpandableLeveledText instead.',
      ),
      ErrorHint(
        'See https://pub.dev/packages/semantic_zoom#using-your-own-scroll-view',
      ),
      context.describeElement('The widget that needed a controller was'),
    ]);
  }

  @override
  bool updateShouldNotify(SemanticZoomScope oldWidget) =>
      oldWidget.controller != controller;
}
