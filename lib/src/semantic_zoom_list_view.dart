import 'package:flutter/widgets.dart';

import 'semantic_zoom_controller.dart';
import 'semantic_zoom_detector.dart';
import 'sliver_semantic_zoom_list.dart';

/// A ready-made scrolling list with semantic zoom: a [SemanticZoomDetector]
/// around a [CustomScrollView] holding a [SliverSemanticZoomList].
///
/// For headers or other slivers, compose those pieces yourself.
class SemanticZoomListView extends StatelessWidget {
  /// Creates a list that builds items on demand.
  const SemanticZoomListView.builder({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.itemCount,
    this.padding,
    this.scrollController,
    this.physics,
    this.levelsPerDoubling = 1.6,
    this.enableHaptics = true,
    this.enableKeyboardShortcuts = true,
  });

  /// Drives the zoom.
  final SemanticZoomController controller;

  /// Builds item [int].
  final NullableIndexedWidgetBuilder itemBuilder;

  /// Number of items, or null for unbounded.
  final int? itemCount;

  /// Padding around the list.
  final EdgeInsetsGeometry? padding;

  /// Optional scroll controller.
  final ScrollController? scrollController;

  /// Physics used when not pinching. Defaults to the platform's.
  final ScrollPhysics? physics;

  /// See [SemanticZoomDetector.levelsPerDoubling].
  final double levelsPerDoubling;

  /// See [SemanticZoomDetector.enableHaptics].
  final bool enableHaptics;

  /// See [SemanticZoomDetector.enableKeyboardShortcuts].
  final bool enableKeyboardShortcuts;

  @override
  Widget build(BuildContext context) => SemanticZoomDetector(
        controller: controller,
        levelsPerDoubling: levelsPerDoubling,
        enableHaptics: enableHaptics,
        enableKeyboardShortcuts: enableKeyboardShortcuts,
        builder: (context, isPinching) {
          Widget sliver = SliverSemanticZoomList.builder(
            controller: controller,
            itemBuilder: itemBuilder,
            itemCount: itemCount,
          );
          if (padding != null) {
            sliver = SliverPadding(padding: padding!, sliver: sliver);
          }
          return CustomScrollView(
            controller: scrollController,
            physics:
                isPinching ? const NeverScrollableScrollPhysics() : physics,
            slivers: [sliver],
          );
        },
      );
}
