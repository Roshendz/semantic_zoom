import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'semantic_zoom_controller.dart';
import 'sliver_semantic_zoom_list.dart';

/// A grid for semantic zoom: items in rows, where each row is as tall as
/// its tallest item and grows as they zoom.
///
/// Built on [SliverSemanticZoomList] (one list entry per row), so pinch
/// anchoring, lag-free scroll correction and per-item levels work the same
/// way. Items in a row are top-aligned; they can differ in height.
///
/// Give either [crossAxisCount] (fixed columns) or [maxCrossAxisExtent]
/// (as many columns as fit, each at most that wide).
class SliverSemanticZoomGrid extends StatelessWidget {
  /// Creates a grid that builds items on demand. When [itemCount] is null
  /// the grid ends at the first index for which [itemBuilder] returns null.
  const SliverSemanticZoomGrid.builder({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.itemCount,
    this.crossAxisCount,
    this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
  })  : assert(
          (crossAxisCount == null) != (maxCrossAxisExtent == null),
          'Give exactly one of crossAxisCount and maxCrossAxisExtent.',
        ),
        assert(crossAxisCount == null || crossAxisCount > 0),
        assert(maxCrossAxisExtent == null || maxCrossAxisExtent > 0);

  /// The controller whose anchor requests this grid honours.
  final SemanticZoomController controller;

  /// Builds item [int]. Return null to end an open-ended grid.
  final NullableIndexedWidgetBuilder itemBuilder;

  /// Number of items, or null for open-ended.
  final int? itemCount;

  /// Fixed number of columns.
  final int? crossAxisCount;

  /// Maximum width of a column; the number of columns follows the width.
  final double? maxCrossAxisExtent;

  /// Space between rows.
  final double mainAxisSpacing;

  /// Space between columns.
  final double crossAxisSpacing;

  int _columnsFor(double width) {
    final fixed = crossAxisCount;
    if (fixed != null) return fixed;
    return math.max(
      1,
      ((width + crossAxisSpacing) / (maxCrossAxisExtent! + crossAxisSpacing))
          .ceil(),
    );
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = _columnsFor(constraints.crossAxisExtent);
          final count = itemCount;
          return SliverSemanticZoomList.builder(
            controller: controller,
            itemCount: count == null ? null : (count / columns).ceil(),
            itemBuilder: (context, row) => _row(context, row, columns),
          );
        },
      );

  Widget? _row(BuildContext context, int row, int columns) {
    final count = itemCount;
    final first = row * columns;
    final cells = <Widget>[];
    for (var c = 0; c < columns; c++) {
      final index = first + c;
      final item =
          count == null || index < count ? itemBuilder(context, index) : null;
      if (item == null && c == 0) return null; // open-ended grid ended
      if (c > 0 && crossAxisSpacing > 0) {
        cells.add(SizedBox(width: crossAxisSpacing));
      }
      cells.add(Expanded(child: item ?? const SizedBox.shrink()));
    }
    return Padding(
      padding: EdgeInsets.only(top: row == 0 ? 0 : mainAxisSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cells,
      ),
    );
  }
}
