import 'package:flutter/widgets.dart';

import 'leveled_text.dart';
import 'leveled_text_view.dart';
import 'semantic_zoom_controller.dart';

/// Builds a footer under an [ExpandableLeveledText], e.g. a "Show more"
/// button. [toggle] steps to the next level (wrapping if enabled).
typedef ExpandableFooterBuilder = Widget Function(
  BuildContext context,
  int level,
  int maxLevel,
  VoidCallback toggle,
);

/// A single piece of leveled text that expands in place on tap, with no
/// list or controller to set up: an animated "read more".
///
/// ```dart
/// ExpandableLeveledText(
///   LeveledText.parse('Knee review[: cleared to run]{ twice a week.}'),
/// )
/// ```
///
/// Each tap morphs to the next level; after the last one it goes back to
/// the first (see [wrap]). Use [footerBuilder] for a visible "Show more /
/// Show less" control, or a [GlobalKey] to call [ExpandableLeveledTextState]
/// methods from elsewhere.
class ExpandableLeveledText extends StatefulWidget {
  /// Creates an expandable text.
  const ExpandableLeveledText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle = LeveledTextView.defaultLinkStyle,
    this.onLinkTap,
    this.initialLevel = 0,
    this.levelCount,
    this.expandOnTap = true,
    this.wrap = true,
    this.onLevelChanged,
    this.footerBuilder,
    this.levelLabels,
    this.showMoreHint = 'Show more',
    this.showLessHint = 'Show less',
  });

  /// The text to display.
  final LeveledText text;

  /// Merged onto the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Merged onto link words.
  final TextStyle? linkStyle;

  /// Called with a link's target when it is tapped.
  final ValueChanged<String>? onLinkTap;

  /// The level shown first.
  final int initialLevel;

  /// Number of levels. Defaults to the levels [text] actually uses (at
  /// least two).
  final int? levelCount;

  /// Whether tapping the text steps to the next level.
  final bool expandOnTap;

  /// Whether stepping past the last level returns to the first.
  final bool wrap;

  /// Called when the level changes.
  final ValueChanged<int>? onLevelChanged;

  /// Builds an optional footer, such as a "Show more" button.
  final ExpandableFooterBuilder? footerBuilder;

  /// Screen-reader names for each level. See
  /// [SemanticZoomController.levelLabels].
  final List<String>? levelLabels;

  /// Screen-reader hint for the tap action while more detail is available.
  final String showMoreHint;

  /// Screen-reader hint for the tap action at the last level.
  final String showLessHint;

  @override
  State<ExpandableLeveledText> createState() => ExpandableLeveledTextState();
}

/// State of an [ExpandableLeveledText]; reach it with a [GlobalKey] to
/// change the level from outside.
class ExpandableLeveledTextState extends State<ExpandableLeveledText>
    with SingleTickerProviderStateMixin {
  late SemanticZoomController _zoom;

  int get _levelCount {
    final count = widget.levelCount ?? widget.text.maxLevel + 1;
    return count < 2 ? 2 : count;
  }

  /// The current level.
  int get level => _zoom.level;

  /// The highest level.
  int get maxLevel => _zoom.maxLevel;

  /// Whether the text is at its last level.
  bool get isExpanded => level == maxLevel;

  @override
  void initState() {
    super.initState();
    _zoom = _create(widget.initialLevel);
  }

  SemanticZoomController _create(int initial) => SemanticZoomController(
        vsync: this,
        levelCount: _levelCount,
        initialLevel: initial,
        levelLabels: widget.levelLabels,
      )..addListener(_changed);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _zoom.reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(ExpandableLeveledText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_zoom.levelCount != _levelCount ||
        oldWidget.levelLabels != widget.levelLabels) {
      final keep = _zoom.level;
      _zoom.dispose();
      _zoom = _create(keep)
        ..reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    }
  }

  void _changed() {
    widget.onLevelChanged?.call(_zoom.level);
    setState(() {});
  }

  /// Morphs to [target].
  void setLevel(int target) => _zoom.animateToLevel(target, anchor: false);

  /// Steps to the next level, wrapping to the first if [ExpandableLeveledText.wrap].
  void next() {
    if (level < maxLevel) {
      setLevel(level + 1);
    } else if (widget.wrap) {
      setLevel(0);
    }
  }

  /// Jumps back to the first level.
  void collapse() => setLevel(0);

  /// Goes straight to the last level.
  void expand() => setLevel(maxLevel);

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget view = LeveledTextView(
      widget.text,
      controller: _zoom,
      style: widget.style,
      linkStyle: widget.linkStyle,
      onLinkTap: widget.onLinkTap,
    );
    final canStep = level < maxLevel || widget.wrap;
    if (widget.expandOnTap && canStep) {
      view = Semantics(
        onTapHint: isExpanded ? widget.showLessHint : widget.showMoreHint,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: next,
          child: view,
        ),
      );
    }
    final footer = widget.footerBuilder;
    if (footer == null) return view;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [view, footer(context, level, maxLevel, next)],
    );
  }
}
