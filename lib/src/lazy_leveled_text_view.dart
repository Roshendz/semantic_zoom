part of 'leveled_text_view.dart';

/// Builds what is shown under a [LazyLeveledTextView] while it loads.
typedef LazyLoadingBuilder = Widget Function(BuildContext context);

/// Builds what is shown under a [LazyLeveledTextView] when loading failed.
/// Call [retry] to try again.
typedef LazyErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  VoidCallback retry,
);

/// Like [LeveledTextView], but for text from a [LeveledTextLoader]: the
/// brief text shows at once, and the longer versions are loaded the first
/// time this entry starts to zoom (a pinch, a level change, [itemId]
/// expanding, or a screen reader's increase action).
///
/// When they arrive, the new words morph in up to the current level, and
/// the list keeps the first visible entry still while this one grows.
///
/// ```dart
/// LazyLeveledTextView(
///   visit.loader, // a LeveledTextLoader kept with your data
///   itemId: visit.id,
///   loadingBuilder: (context) => const LinearProgressIndicator(),
/// )
/// ```
class LazyLeveledTextView extends StatefulWidget {
  /// Creates a view. Uses the nearest [SemanticZoomScope] unless
  /// [controller] is given.
  const LazyLeveledTextView(
    this.loader, {
    super.key,
    this.itemId,
    this.adjustable = true,
    this.controller,
    this.style,
    this.linkStyle = LeveledTextView.defaultLinkStyle,
    this.onLinkTap,
    this.eager = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.revealDuration = const Duration(milliseconds: 350),
  });

  /// Provides the brief text and loads the rest.
  final LeveledTextLoader loader;

  /// See [LeveledTextView.itemId].
  final Object? itemId;

  /// See [LeveledTextView.adjustable].
  final bool adjustable;

  /// See [LeveledTextView.controller].
  final SemanticZoomController? controller;

  /// See [LeveledTextView.style].
  final TextStyle? style;

  /// See [LeveledTextView.linkStyle].
  final TextStyle? linkStyle;

  /// See [LeveledTextView.onLinkTap].
  final ValueChanged<String>? onLinkTap;

  /// Whether to start loading as soon as this view is shown, instead of
  /// waiting until it starts to zoom.
  final bool eager;

  /// Shown under the text while loading, e.g. a thin progress bar.
  final LazyLoadingBuilder? loadingBuilder;

  /// Shown under the text when loading failed. Loading is also retried the
  /// next time the entry starts to zoom.
  final LazyErrorBuilder? errorBuilder;

  /// How long the new words take to morph in once loaded. Skipped when the
  /// platform asks to reduce motion.
  final Duration revealDuration;

  @override
  State<LazyLeveledTextView> createState() => _LazyLeveledTextViewState();
}

class _LazyLeveledTextViewState extends State<LazyLeveledTextView>
    with SingleTickerProviderStateMixin {
  // 0 = only level 0 may show, 1 = no limit.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: widget.revealDuration,
    value: widget.loader.isLoaded ? 1 : 0,
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeInOut,
  );

  SemanticZoomController? _zoom;
  Listenable? _zoomListenable;
  bool _wasZooming = false;
  VoidCallback? _releaseAnchor;

  @override
  void initState() {
    super.initState();
    widget.loader.addListener(_loaderChanged);
    if (widget.eager) _loadAfterFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(LazyLeveledTextView old) {
    super.didUpdateWidget(old);
    _reveal.duration = widget.revealDuration;
    if (old.loader != widget.loader) {
      old.loader.removeListener(_loaderChanged);
      widget.loader.addListener(_loaderChanged);
      _reveal.value = widget.loader.isLoaded ? 1 : 0;
      _endReveal();
      if (widget.eager) _loadAfterFrame();
    }
    _bind();
  }

  void _bind() {
    final zoom = widget.controller ?? SemanticZoomScope.of(context);
    final listenable = zoom.listenableFor(widget.itemId);
    if (identical(listenable, _zoomListenable) && zoom == _zoom) return;
    _zoomListenable?.removeListener(_zoomChanged);
    _zoom = zoom;
    _zoomListenable = listenable..addListener(_zoomChanged);
    // Already zoomed in when shown, e.g. scrolled into view at level 2.
    if (zoom.valueFor(widget.itemId) > 0.01) _loadAfterFrame();
  }

  void _loadAfterFrame() => WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          if (mounted) widget.loader.ensureLoaded();
        },
      );

  void _zoomChanged() {
    final zooming = _zoom!.valueFor(widget.itemId) > 0.01;
    final loader = widget.loader;
    // Load when zooming starts; after a failure, only retry on a new zoom.
    if (zooming &&
        !loader.isLoaded &&
        !loader.isLoading &&
        (loader.error == null || !_wasZooming)) {
      loader.ensureLoaded();
    }
    _wasZooming = zooming;
  }

  void _loaderChanged() {
    final loader = widget.loader;
    // Loading rows appearing or going, and the reveal, change this entry's
    // height: keep the list's first visible entry still meanwhile.
    final release = _zoom?.holdAnchor();
    if (loader.isLoaded && _reveal.value < 1 && !_reveal.isAnimating) {
      _endReveal();
      _releaseAnchor = release;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _reveal.value = 1;
        _releaseAfterFrame(_takeReveal());
      } else {
        _reveal.forward().whenCompleteOrCancel(
              () => _releaseAfterFrame(_takeReveal()),
            );
      }
    } else {
      _releaseAfterFrame(release);
    }
    setState(() {});
  }

  VoidCallback? _takeReveal() {
    final release = _releaseAnchor;
    _releaseAnchor = null;
    return release;
  }

  // Release once the new height has been laid out, so the list can correct
  // for it first.
  void _releaseAfterFrame(VoidCallback? release) {
    if (release == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => release());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _endReveal() => _takeReveal()?.call();

  @override
  void dispose() {
    widget.loader.removeListener(_loaderChanged);
    _zoomListenable?.removeListener(_zoomChanged);
    _endReveal();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loader = widget.loader;
    final zoom = _zoom!;
    final cap = _eased.drive(
      Tween<double>(begin: 0, end: zoom.maxLevel.toDouble()),
    );
    final view = LeveledTextView._capped(
      loader.text,
      cap: cap,
      itemId: widget.itemId,
      adjustable: widget.adjustable,
      controller: zoom,
      style: widget.style,
      linkStyle: widget.linkStyle,
      onLinkTap: widget.onLinkTap,
    );
    final error = loader.error;
    final extra = loader.isLoading
        ? widget.loadingBuilder?.call(context)
        : error != null
            ? widget.errorBuilder?.call(context, error, loader.ensureLoaded)
            : null;
    if (extra == null) return view;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [view, extra],
    );
  }
}
