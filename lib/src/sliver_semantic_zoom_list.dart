import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'semantic_zoom_controller.dart';

/// A [SliverList] that keeps a pinned item still while items around it grow
/// or shrink during a semantic zoom.
///
/// The correction is applied during layout via
/// [SliverGeometry.scrollOffsetCorrection], so it lands in the same frame,
/// with no one-frame lag and no post-frame `jumpTo`.
class SliverSemanticZoomList extends SliverMultiBoxAdaptorWidget {
  /// Creates a list from a [SliverChildDelegate].
  const SliverSemanticZoomList({
    super.key,
    required super.delegate,
    required this.controller,
  });

  /// Creates a list that builds items on demand.
  SliverSemanticZoomList.builder({
    super.key,
    required this.controller,
    required NullableIndexedWidgetBuilder itemBuilder,
    int? itemCount,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
  }) : super(
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: itemCount,
            addAutomaticKeepAlives: addAutomaticKeepAlives,
            addRepaintBoundaries: addRepaintBoundaries,
            addSemanticIndexes: addSemanticIndexes,
          ),
        );

  /// The controller whose anchor requests this list honours.
  final SemanticZoomController controller;

  @override
  RenderSliverSemanticZoomList createRenderObject(BuildContext context) =>
      RenderSliverSemanticZoomList(
        childManager: context as SliverMultiBoxAdaptorElement,
        controller: controller,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverSemanticZoomList renderObject,
  ) {
    renderObject.controller = controller;
  }
}

/// Render object for [SliverSemanticZoomList].
///
/// Supports [AxisDirection.down], [AxisDirection.right] and, for chat-style
/// lists (`reverse: true`), [AxisDirection.up].
class RenderSliverSemanticZoomList extends RenderSliverList
    implements SemanticZoomAnchorClient {
  /// Creates the render object.
  RenderSliverSemanticZoomList({
    required super.childManager,
    required SemanticZoomController controller,
  }) : _controller = controller;

  SemanticZoomController _controller;

  /// The controller this list registers with.
  SemanticZoomController get controller => _controller;
  set controller(SemanticZoomController value) {
    if (value == _controller) return;
    if (attached) _controller.removeAnchorClient(this);
    _controller = value;
    if (attached) _controller.addAnchorClient(this);
  }

  int? _anchorIndex;

  /// Leading edge of the anchored child, relative to the viewport.
  double _anchorPosition = 0;

  /// Anchor corrections smaller than this are ignored.
  static const double _epsilon = 0.5;

  /// One correction per frame is the norm; the rest is headroom for passes
  /// where the list's own estimates change too.
  static const int _maxCorrectionsPerFrame = 3;
  int _correctionsThisFrame = 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addAnchorClient(this);
  }

  @override
  void detach() {
    _controller.removeAnchorClient(this);
    super.detach();
  }

  bool get _supported => switch (constraints.axisDirection) {
        // All offsets here are measured from the viewport's leading edge,
        // which is the bottom in a reversed list, so the same math applies.
        AxisDirection.down || AxisDirection.right || AxisDirection.up => true,
        _ => false,
      };

  // Where this sliver's scroll offset 0 sits in the viewport. Derivation:
  // painted-before = viewportExtent - remainingPaintExtent, and the sliver's
  // leading edge is that minus how far it's scrolled past.
  double get _sliverLeadingInViewport =>
      constraints.viewportMainAxisExtent -
      constraints.remainingPaintExtent -
      constraints.scrollOffset;

  double _childLeadingInViewport(RenderBox child) =>
      _sliverLeadingInViewport + childScrollOffset(child)!;

  // Viewport scroll pixels, derived from constraints so we can avoid
  // correcting past the start of the scroll view.
  double get _viewportPixels =>
      constraints.precedingScrollExtent - _sliverLeadingInViewport;

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = childAfter(child);
    }
  }

  @override
  bool captureAnchorAt(Offset globalPosition) {
    _anchorIndex = null;
    if (!attached || geometry == null || !_supported) return false;
    final vertical = constraints.axis == Axis.vertical;
    for (final child in _children) {
      if (!child.hasSize) continue;
      final local = child.globalToLocal(globalPosition);
      final along = vertical ? local.dy : local.dx;
      final extent = vertical ? child.size.height : child.size.width;
      if (along >= 0 && along <= extent) {
        _pin(child);
        return true;
      }
    }
    return captureLeadingAnchor();
  }

  @override
  bool captureLeadingAnchor() {
    _anchorIndex = null;
    if (!attached || geometry == null || !_supported) return false;
    for (final child in _children) {
      if (!child.hasSize) continue;
      final end = _childLeadingInViewport(child) + paintExtentOf(child);
      if (end > 0) {
        _pin(child);
        return true;
      }
    }
    return false;
  }

  void _pin(RenderBox child) {
    _anchorIndex = indexOf(child);
    _anchorPosition = _childLeadingInViewport(child);
  }

  @override
  void releaseAnchor() => _anchorIndex = null;

  /// Whether an item is currently pinned. Exposed for tests.
  @visibleForTesting
  int? get anchorIndex => _anchorIndex;

  @override
  void performLayout() {
    super.performLayout();
    if (_anchorIndex == null &&
        geometry!.scrollOffsetCorrection != null &&
        constraints.scrollOffset <= precisionErrorTolerance &&
        firstChild != null) {
      // The list was moved to exactly its start (e.g. jumpTo(0) or the end
      // of animateTo(0)), but items above the old position changed height
      // while off-screen. SliverList would fix its estimate one item at a
      // time by shifting the scroll offset, so the start would be missed.
      // Lay out again from item 0 instead, so the start is really shown.
      // While scrolling normally the estimates are already fixed by the
      // time the start is reached, so this doesn't run then.
      collectGarbage(childCount, 0);
      super.performLayout();
    }
    final index = _anchorIndex;
    if (index == null || !_supported) return;
    if (geometry!.scrollOffsetCorrection != null) return;

    RenderBox? anchor;
    for (final child in _children) {
      if (indexOf(child) == index) {
        anchor = child;
        break;
      }
    }
    // The pinned item scrolled out of the built range; nothing to correct.
    if (anchor == null) return;

    var delta = _childLeadingInViewport(anchor) - _anchorPosition;
    // Never correct to before the start of the scroll view (but leave an
    // existing overscroll alone).
    final pixels = _viewportPixels;
    final floor = pixels > 0 ? -pixels : 0.0;
    if (delta < floor) delta = floor;
    if (delta.abs() < _epsilon) return;

    // A correction that keeps being undone within one frame can't win: e.g.
    // the content shrank so the view can't scroll this far any more, and
    // the scroll physics pull the offset back each time. Fighting them
    // would never settle, so after a few tries let them win this frame.
    if (_correctionsThisFrame >= _maxCorrectionsPerFrame) return;
    if (_correctionsThisFrame++ == 0) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _correctionsThisFrame = 0,
      );
    }

    // The viewport shifts its offset by `delta` and lays out again within
    // this same frame, so the pinned item never visibly moves.
    geometry = SliverGeometry(scrollOffsetCorrection: delta);
  }
}
