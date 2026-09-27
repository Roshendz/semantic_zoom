import 'package:flutter/foundation.dart';

/// A word (or glued punctuation) tagged with the range of detail levels at
/// which it is visible.
@immutable
class LeveledToken {
  /// Creates a token visible from [minLevel] up to [maxLevel] (inclusive;
  /// `null` = every higher level).
  const LeveledToken(
    this.text,
    this.minLevel, {
    this.maxLevel,
    this.glued = false,
  })  : assert(minLevel >= 0),
        assert(maxLevel == null || maxLevel >= minLevel);

  /// A paragraph break. Visible at every level.
  const LeveledToken.paragraphBreak()
      : text = '\n',
        minLevel = 0,
        maxLevel = null,
        glued = false;

  /// The word, or `'\n'` for a paragraph break.
  final String text;

  /// Lowest level (0 = briefest) at which this token is shown.
  final int minLevel;

  /// Highest level at which this token is shown, or `null` if it stays
  /// visible at every level above [minLevel].
  ///
  /// Set when a longer version rewrites (drops) this word; it then fades out
  /// while the replacement fades in.
  final int? maxLevel;

  /// Whether this token attaches to the previous one with no space, e.g. a
  /// comma.
  final bool glued;

  /// Whether this token is a paragraph break.
  bool get isBreak => text == '\n';

  /// Whether this token is shown at [level].
  bool isVisibleAt(int level) =>
      level >= minLevel && (maxLevel == null || level <= maxLevel!);

  @override
  bool operator ==(Object other) =>
      other is LeveledToken &&
      other.text == text &&
      other.minLevel == minLevel &&
      other.maxLevel == maxLevel &&
      other.glued == glued;

  @override
  int get hashCode => Object.hash(text, minLevel, maxLevel, glued);

  @override
  String toString() {
    final range = maxLevel == null ? '$minLevel+' : '$minLevel..$maxLevel';
    return 'LeveledToken(${isBreak ? r'\n' : text}, $range'
        '${glued ? ', glued' : ''})';
  }
}

/// Text that exists at several detail levels, stored as a single token
/// stream.
///
/// When every shorter version is a word-subsequence of the longer one
/// (StretchText-style), words already on screen stay and slide while new
/// words fade in around them. Rewritten versions also work via
/// [LeveledText.fromVersions]: words the versions share still slide, and
/// the rest cross-fade in place.
@immutable
class LeveledText {
  /// Creates leveled text from pre-tagged [tokens].
  LeveledText(List<LeveledToken> tokens)
      : tokens = List.unmodifiable(tokens),
        maxLevel = tokens.fold(0, (m, t) {
          final top = t.maxLevel == null ? t.minLevel : t.maxLevel! + 1;
          return top > m ? top : m;
        });

  /// Parses markup where plain words are level 0, `[words]` are level 1,
  /// `{words}` are level 2, and `\n` is a paragraph break.
  ///
  /// ```dart
  /// LeveledText.parse('Train to Porto[, along the coast]{, window seat on the left.}');
  /// // level 0: "Train to Porto"
  /// // level 1: "Train to Porto, along the coast"
  /// // level 2: "Train to Porto, along the coast, window seat on the left."
  /// ```
  ///
  /// Throws a [FormatException] on unbalanced or nested brackets.
  factory LeveledText.parse(String markup) => LeveledText(_parse(markup));

  /// Builds leveled text from plain versions, briefest first, such as
  /// summaries written by a person or an LLM.
  ///
  /// Consecutive versions are aligned word by word (longest common
  /// subsequence; trailing punctuation such as `.,;:!?` is its own token).
  /// Shared words slide to their new positions. Words that a longer version
  /// adds fade in, and words it drops fade out.
  ///
  /// Set [requireSubsequence] to throw an [ArgumentError] instead when a
  /// version drops or reorders words, for example to validate backend data
  /// against the strict StretchText contract.
  ///
  /// ```dart
  /// LeveledText.fromVersions([
  ///   'Port tasting',
  ///   'Port tasting in Gaia',
  ///   'Port tasting in Gaia: tawny, ruby and a surprising white.',
  /// ]);
  /// ```
  factory LeveledText.fromVersions(
    List<String> versions, {
    bool requireSubsequence = false,
  }) =>
      LeveledText(_fromVersions(versions, requireSubsequence));

  /// The token stream, in reading order.
  final List<LeveledToken> tokens;

  /// Highest level at which the text differs from the level below it.
  final int maxLevel;

  /// The text as shown at [level], with paragraph breaks as `\n`.
  String textAt(int level) {
    final b = StringBuffer();
    var pendingBreak = false;
    for (final t in tokens) {
      if (!t.isVisibleAt(level)) continue;
      if (t.isBreak) {
        pendingBreak = b.isNotEmpty;
        continue;
      }
      if (pendingBreak) {
        b.write('\n');
        pendingBreak = false;
      } else if (b.isNotEmpty && !t.glued) {
        b.write(' ');
      }
      b.write(t.text);
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is LeveledText && listEquals(other.tokens, tokens);

  @override
  int get hashCode => Object.hashAll(tokens);
}

List<LeveledToken> _parse(String src) {
  final tokens = <LeveledToken>[];
  final buf = StringBuffer();
  var level = 0;
  String? openedBy;
  var sawSpace = true;
  var glued = false;

  void flush() {
    if (buf.isEmpty) return;
    tokens.add(LeveledToken(buf.toString(), level, glued: glued));
    buf.clear();
  }

  void open(String ch, int lvl, int at) {
    if (openedBy != null) {
      throw FormatException('Nested "$ch" inside "$openedBy"', src, at);
    }
    flush();
    openedBy = ch;
    level = lvl;
  }

  void close(String expectedOpen, String ch, int at) {
    if (openedBy != expectedOpen) {
      throw FormatException('Unmatched "$ch"', src, at);
    }
    flush();
    openedBy = null;
    level = 0;
  }

  for (var i = 0; i < src.length; i++) {
    final ch = src[i];
    switch (ch) {
      case '[':
        open(ch, 1, i);
      case '{':
        open(ch, 2, i);
      case ']':
        close('[', ch, i);
      case '}':
        close('{', ch, i);
      case ' ' || '\t' || '\r':
        flush();
        sawSpace = true;
      case '\n':
        flush();
        tokens.add(const LeveledToken.paragraphBreak());
        sawSpace = true;
      default:
        if (buf.isEmpty) {
          glued = !sawSpace && tokens.isNotEmpty;
          sawSpace = false;
        }
        buf.write(ch);
    }
  }
  if (openedBy != null) {
    throw FormatException('Unclosed "$openedBy"', src, src.length);
  }
  flush();
  return tokens;
}

// A paragraph break, a run of trailing punctuation, or a word. Punctuation is
// split off so "follow-up" in a short version matches "follow-up:" in a
// longer one.
final _words = RegExp(r'\n|[.,;:!?…]+|[^\s.,;:!?…]+');

List<LeveledToken> _fromVersions(
  List<String> versions,
  bool requireSubsequence,
) {
  if (versions.isEmpty) {
    throw ArgumentError.value(versions, 'versions', 'must not be empty');
  }

  List<(String, bool)> split(String s) => [
        for (final m in _words.allMatches(s))
          (
            m.group(0)!,
            m.start > 0 && m.group(0) != '\n' && !_isSpace(s[m.start - 1]),
          ),
      ];

  var stream = [
    for (final (w, glued) in split(versions.first))
      LeveledToken(w, 0, glued: glued),
  ];

  for (var v = 1; v < versions.length; v++) {
    final next = split(versions[v]);
    final alive = [
      for (var i = 0; i < stream.length; i++)
        if (stream[i].maxLevel == null) i,
    ];
    final ops = _diff(
      [for (final i in alive) stream[i].text],
      [for (final (w, _) in next) w],
    );

    if (requireSubsequence) {
      final dropped = ops.where((o) => o.$1 == _Op.delete).firstOrNull;
      if (dropped != null) {
        throw ArgumentError(
          'Version $v is not a word-superset of version ${v - 1}: '
          '"${stream[alive[dropped.$2]].text}" is missing or out of order. '
          'Pass requireSubsequence: false to cross-fade rewritten words.',
        );
      }
    }

    // Rebuild the stream, keeping tokens that died at earlier levels in
    // their place relative to the live ones.
    final merged = <LeveledToken>[];
    var cursor = 0;
    void copyDeadUpTo(int index) {
      while (cursor < index) {
        merged.add(stream[cursor++]);
      }
    }

    for (final (op, a, b) in ops) {
      switch (op) {
        case _Op.keep:
          copyDeadUpTo(alive[a]);
          merged.add(stream[cursor++]);
        case _Op.delete:
          copyDeadUpTo(alive[a]);
          final t = stream[cursor++];
          merged.add(
            LeveledToken(t.text, t.minLevel, maxLevel: v - 1, glued: t.glued),
          );
        case _Op.insert:
          merged.add(LeveledToken(next[b].$1, v, glued: next[b].$2));
      }
    }
    copyDeadUpTo(stream.length);
    stream = merged;
  }
  return stream;
}

enum _Op { keep, delete, insert }

/// Word-level LCS diff. Returns (op, index in [a], index in [b]); deletes
/// come before inserts in a changed region so old words sit before new ones.
List<(_Op, int, int)> _diff(List<String> a, List<String> b) {
  final n = a.length, m = b.length, w = m + 1;
  // lcs[i * w + j] = LCS length of a[i..] and b[j..].
  final lcs = Int32List((n + 1) * w);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i * w + j] = a[i] == b[j]
          ? lcs[(i + 1) * w + j + 1] + 1
          : (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]
              ? lcs[(i + 1) * w + j]
              : lcs[i * w + j + 1]);
    }
  }
  final ops = <(_Op, int, int)>[];
  var i = 0, j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[i] == b[j]) {
      ops.add((_Op.keep, i++, j++));
    } else if (j >= m ||
        (i < n && lcs[(i + 1) * w + j] >= lcs[i * w + j + 1])) {
      ops.add((_Op.delete, i++, -1));
    } else {
      ops.add((_Op.insert, -1, j++));
    }
  }
  return ops;
}

bool _isSpace(String ch) => ch == ' ' || ch == '\t' || ch == '\r';
