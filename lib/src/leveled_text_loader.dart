import 'package:flutter/foundation.dart';

import 'leveled_text.dart';

/// Leveled text whose longer versions are fetched only when needed: the
/// brief text is available at once, and the rest is loaded (for example
/// from an API or an LLM) the first time someone expands it.
///
/// Show it with `LazyLeveledTextView`, which calls [ensureLoaded] when its
/// entry starts to zoom. Keep loaders with your data (not in `build`) so a
/// result is fetched once and reused when the entry is rebuilt.
///
/// ```dart
/// final loader = LeveledTextLoader.versions(
///   brief: visit.title,
///   load: () => api.fetchSummaries(visit.id), // e.g. [summary, notes]
/// );
/// ```
class LeveledTextLoader extends ChangeNotifier {
  /// Creates a loader that shows [brief] until [load] completes.
  ///
  /// The loaded text's level 0 should show the same words as [brief], so
  /// the brief text can morph into the longer levels seamlessly.
  LeveledTextLoader({
    required LeveledText brief,
    required Future<LeveledText> Function() load,
  })  : _text = brief,
        _load = load;

  /// Creates a loader from plain versions: [brief] first, then the longer
  /// versions returned by [load], briefest first. They are combined with
  /// [LeveledText.fromVersions].
  factory LeveledTextLoader.versions({
    required String brief,
    required Future<List<String>> Function() load,
    bool requireSubsequence = false,
  }) =>
      LeveledTextLoader(
        brief: LeveledText.fromVersions([brief]),
        load: () async => LeveledText.fromVersions(
          [brief, ...await load()],
          requireSubsequence: requireSubsequence,
        ),
      );

  /// A loader whose text is already complete; nothing is fetched.
  LeveledTextLoader.loaded(LeveledText text)
      : _text = text,
        _load = null,
        _isLoaded = true;

  final Future<LeveledText> Function()? _load;
  LeveledText _text;
  bool _isLoaded = false;
  Future<void>? _pending;
  Object? _error;
  bool _disposed = false;

  /// The brief text until loading completes, then the full text.
  LeveledText get text => _text;

  /// Whether the longer versions are available.
  bool get isLoaded => _isLoaded;

  /// Whether a load is in progress.
  bool get isLoading => _pending != null;

  /// The error from the last failed load, or null. Cleared on retry.
  Object? get error => _error;

  /// Loads the longer versions once. Concurrent calls share the same load;
  /// after a failure, calling it again retries. Never throws: failures are
  /// reported through [error].
  Future<void> ensureLoaded() {
    if (_isLoaded || _load == null) return Future.value();
    return _pending ??= _run();
  }

  Future<void> _run() async {
    // Yield first so [ensureLoaded] has stored this future: listeners must
    // see isLoading == true when they hear that loading started.
    await null;
    if (_disposed) return;
    _error = null;
    notifyListeners();
    try {
      final full = await _load!();
      if (_disposed) return;
      _text = full;
      _isLoaded = true;
    } catch (e) {
      if (_disposed) return;
      _error = e;
    } finally {
      _pending = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
