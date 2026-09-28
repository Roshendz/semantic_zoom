import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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
    this.restorationId,
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

  /// Restores the level after the operating system restarts the app in the
  /// background (Flutter state restoration). Requires a
  /// `restorationScopeId` on the app. Null (the default) disables it.
  ///
  /// To keep the level when the text scrolls out of a list and back, give
  /// it a [PageStorageKey] instead, e.g. `key: PageStorageKey(article.id)`.
  final String? restorationId;

  @override
  State<ExpandableLeveledText> createState() => ExpandableLeveledTextState();
}

/// State of an [ExpandableLeveledText]; reach it with a [GlobalKey] to
/// change the level from outside.
class ExpandableLeveledTextState extends State<ExpandableLeveledText>
    with SingleTickerProviderStateMixin, RestorationMixin {
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
    final stored = _storageId == null
        ? null
        : PageStorage.maybeOf(context)?.readState(
            context,
            identifier: _storageId,
          );
    _zoom = _create(stored is int ? stored : widget.initialLevel);
  }

  final _savedLevel = RestorableIntN(null);

  @override
  String? get restorationId => widget.restorationId;

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_savedLevel, 'level');
    final level = _savedLevel.value;
    if (level != null) _zoom.restoreLevel(level);
  }

  /// Where the level is kept in [PageStorage], or null when this widget has
  /// no [PageStorageKey] of its own. Ancestor keys are included so equal
  /// keys in different lists don't collide, but an ancestor key alone is
  /// never enough: that would make every text under it share one level.
  Object? get _storageId {
    final key = widget.key;
    if (key is! PageStorageKey) return null;
    final keys = <Key>[key];
    context.visitAncestorElements((element) {
      final k = element.widget.key;
      if (k is PageStorageKey) keys.add(k);
      return element.widget is! PageStorage;
    });
    return _StorageId(keys);
  }

  // SingleTickerProviderStateMixin may create only one ticker. The first
  // controller uses it; controllers replaced later (new level count or
  // labels) get theirs from [_PlainTickers].
  bool _usedOwnTicker = false;

  SemanticZoomController _create(int initial) {
    final TickerProvider vsync = _usedOwnTicker ? const _PlainTickers() : this;
    _usedOwnTicker = true;
    return SemanticZoomController(
      vsync: vsync,
      levelCount: _levelCount,
      initialLevel: initial,
      levelLabels: widget.levelLabels,
    )..addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _zoom.reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(ExpandableLeveledText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_zoom.levelCount != _levelCount ||
        !listEquals(oldWidget.levelLabels, widget.levelLabels)) {
      final keep = _zoom.level;
      _zoom.dispose();
      _zoom = _create(keep)
        ..reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    }
  }

  void _changed() {
    widget.onLevelChanged?.call(_zoom.level);
    if (bucket != null) _savedLevel.value = _zoom.level;
    final id = _storageId;
    if (id != null) {
      PageStorage.maybeOf(context)?.writeState(
        context,
        _zoom.level,
        identifier: id,
      );
    }
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
    _savedLevel.dispose();
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

@immutable
class _StorageId {
  const _StorageId(this.keys);
  final List<Key> keys;

  @override
  bool operator ==(Object other) =>
      other is _StorageId && listEquals(other.keys, keys);

  @override
  int get hashCode => Object.hashAll(keys);
}

/// Tickers for controllers created after the first. Unlike the State's own
/// ticker they aren't paused by [TickerMode]; they only run for the short
/// settle animation after a tap. (TickerMode's listening API differs
/// between the oldest and newest supported Flutter versions.)
class _PlainTickers implements TickerProvider {
  const _PlainTickers();

  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, debugLabel: 'ExpandableLeveledText');
}
