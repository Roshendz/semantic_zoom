import 'package:flutter/widgets.dart';

import 'semantic_zoom_controller.dart';
import 'semantic_zoom_detector.dart';
import 'sliver_semantic_zoom_grid.dart';

/// A ready-made scrolling grid with semantic zoom: a [SemanticZoomDetector]
/// around a [CustomScrollView] holding a [SliverSemanticZoomGrid].
///
/// For headers or other slivers, compose those pieces yourself.
class SemanticZoomGridView extends StatelessWidget {
  /// Creates a grid that builds items on demand. Give exactly one of
  /// [crossAxisCount] and [maxCrossAxisExtent].
  const SemanticZoomGridView.builder({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.itemCount,
    this.crossAxisCount,
    this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.padding,
    this.scrollController,
    this.physics,
    this.restorationId,
    this.levelsPerDoubling = 1.6,
    this.enableHaptics = true,
    this.enableKeyboardShortcuts = true,
  });

  /// Drives the zoom.
  final SemanticZoomController controller;

  /// See [SliverSemanticZoomGrid.itemBuilder].
  final NullableIndexedWidgetBuilder itemBuilder;

  /// See [SliverSemanticZoomGrid.itemCount].
  final int? itemCount;

  /// See [SliverSemanticZoomGrid.crossAxisCount].
  final int? crossAxisCount;

  /// See [SliverSemanticZoomGrid.maxCrossAxisExtent].
  final double? maxCrossAxisExtent;

  /// See [SliverSemanticZoomGrid.mainAxisSpacing].
  final double mainAxisSpacing;

  /// See [SliverSemanticZoomGrid.crossAxisSpacing].
  final double crossAxisSpacing;

  /// Padding around the grid.
  final EdgeInsetsGeometry? padding;

  /// Optional scroll controller.
  final ScrollController? scrollController;

  /// Physics used when not pinching. Defaults to the platform's.
  final ScrollPhysics? physics;

  /// See [SemanticZoomDetector.restorationId]. Also restores the scroll
  /// position.
  final String? restorationId;

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
        restorationId: restorationId,
        builder: (context, isPinching) {
          Widget sliver = SliverSemanticZoomGrid.builder(
            controller: controller,
            itemBuilder: itemBuilder,
            itemCount: itemCount,
            crossAxisCount: crossAxisCount,
            maxCrossAxisExtent: maxCrossAxisExtent,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
          );
          if (padding != null) {
            sliver = SliverPadding(padding: padding!, sliver: sliver);
          }
          return CustomScrollView(
            controller: scrollController,
            restorationId:
                restorationId == null ? null : '$restorationId.scroll',
            physics:
                isPinching ? const NeverScrollableScrollPhysics() : physics,
            slivers: [sliver],
          );
        },
      );
}
