import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A word (or glued punctuation) tagged with the range of detail levels at
/// which it is visible, plus optional styling and a link.
@immutable
class LeveledToken {
  /// Creates a token visible from [minLevel] up to [maxLevel] (inclusive;
  /// `null` = every higher level).
  const LeveledToken(
    this.text,
    this.minLevel, {
    this.maxLevel,
    this.glued = false,
    this.style,
    this.link,
  })  : assert(minLevel >= 0),
        assert(maxLevel == null || maxLevel >= minLevel);

  /// A paragraph break. Visible at every level.
  const LeveledToken.paragraphBreak()
      : text = '\n',
        minLevel = 0,
        maxLevel = null,
        glued = false,
        style = null,
        link = null;

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

  /// Style merged over the view's style, e.g. bold or italic.
  final TextStyle? style;

  /// Link target, such as a URL, passed to `LeveledTextView.onLinkTap`.
  final String? link;

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
      other.glued == glued &&
      other.style == style &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, minLevel, maxLevel, glued, style, link);

  @override
  String toString() {
    final range = maxLevel == null ? '$minLevel+' : '$minLevel..$maxLevel';
    return 'LeveledToken(${isBreak ? r'\n' : text}, $range'
        '${glued ? ', glued' : ''}'
        '${style != null ? ', styled' : ''}'
        '${link != null ? ', link: $link' : ''})';
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
///
/// Both [LeveledText.parse] and [LeveledText.fromVersions] understand a
/// small inline markup: `**bold**`, `*italic*`, `[label](url)` links, and
/// `\` to escape any special character.
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
  /// Inline styling works at any level: `**bold**`, `*italic*`, and
  /// `[label](url)` links (a bracket group directly followed by `(url)` is a
  /// link, not a level). Escape special characters with `\`, e.g. `\[`.
  ///
  /// ```dart
  /// LeveledText.parse('Train to **Porto**[, along the coast]{, window seat.}');
  /// // level 0: "Train to Porto"            ("Porto" in bold)
  /// // level 1: "Train to Porto, along the coast"
  /// // level 2: "Train to Porto, along the coast, window seat."
  /// ```
  ///
  /// Throws a [FormatException] on unbalanced or nested level brackets.
  factory LeveledText.parse(String markup) => LeveledText([
        for (final r in _scan(markup, levels: true))
          r.isBreak
              ? const LeveledToken.paragraphBreak()
              : LeveledToken(
                  r.text,
                  r.level,
                  glued: r.glued,
                  style: r.style,
                  link: r.link,
                ),
      ]);

  /// Builds leveled text from plain versions, briefest first, such as
  /// summaries written by a person or an LLM (see `LeveledPrompt`).
  ///
  /// Consecutive versions are aligned word by word (longest common
  /// subsequence; trailing punctuation such as `.,;:!?` is its own token).
  /// Shared words slide to their new positions. Words that a longer version
  /// adds fade in, and words it drops fade out. Inline `**bold**`,
  /// `*italic*` and `[label](url)` markup is supported.
  ///
  /// Set [requireSubsequence] to throw an [ArgumentError] instead when a
  /// version drops or reorders words, for example to validate backend data
  /// against the strict StretchText contract. Use [checkVersions] for a
  /// detailed report instead of an exception.
  ///
  /// ```dart
  /// LeveledText.fromVersions([
  ///   'Port tasting',
  ///   'Port tasting in Gaia',
  ///   'Port tasting in **Gaia**: tawny, ruby and a surprising white.',
  /// ]);
  /// ```
  factory LeveledText.fromVersions(
    List<String> versions, {
    bool requireSubsequence = false,
  }) =>
      LeveledText(_fromVersions(versions, requireSubsequence));

  /// Reports how smoothly [versions] (briefest first) will morph: how many
  /// words carry over between levels, which ones are dropped, and any
  /// problems. Use it to validate LLM or backend output before display.
  ///
  /// ```dart
  /// final report = LeveledText.checkVersions(versions);
  /// if (!report.isStrict) debugPrint(report.issues.join('\n'));
  /// ```
  static LeveledVersionsReport checkVersions(List<String> versions) =>
      _check(versions);

  /// The token stream, in reading order.
  final List<LeveledToken> tokens;

  /// Highest level at which the text differs from the level below it.
  final int maxLevel;

  /// The text as shown at [level], with paragraph breaks as `\n` and
  /// without markup.
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

/// How smoothly a set of versions will morph. See
/// [LeveledText.checkVersions].
@immutable
class LeveledVersionsReport {
  const LeveledVersionsReport._(this.transitions, this.issues);

  /// One entry per step from a level to the next.
  final List<LeveledTransition> transitions;

  /// Human-readable warnings, empty when everything looks good.
  final List<String> issues;

  /// Whether every longer version only adds words (the StretchText
  /// contract), so nothing needs to cross-fade.
  bool get isStrict => transitions.every((t) => t.dropped.isEmpty);

  /// The lowest share of words carried over between two levels, from 0 to
  /// 1. 1.0 means every word of each shorter version stays on screen.
  double get smoothness => transitions.isEmpty
      ? 1
      : transitions.map((t) => t.carryOver).reduce((a, b) => a < b ? a : b);

  @override
  String toString() => 'LeveledVersionsReport(strict: $isStrict, '
      'smoothness: ${smoothness.toStringAsFixed(2)}, '
      'issues: ${issues.length})';
}

/// The change from one level to the next.
@immutable
class LeveledTransition {
  const LeveledTransition._({
    required this.fromLevel,
    required this.kept,
    required this.added,
    required this.dropped,
  });

  /// The shorter level; the longer one is `fromLevel + 1`.
  final int fromLevel;

  /// Words of the shorter level that stay on screen and slide.
  final int kept;

  /// Words the longer level adds.
  final int added;

  /// Words of the shorter level that the longer one drops (they
  /// cross-fade).
  final List<String> dropped;

  /// Share of the shorter level's words that carry over, from 0 to 1.
  double get carryOver {
    final total = kept + dropped.length;
    return total == 0 ? 1 : kept / total;
  }

  @override
  String toString() => 'LeveledTransition($fromLevel→${fromLevel + 1}: '
      'kept $kept, added $added, dropped ${dropped.length})';
}

// ───────────────────────────── scanning ─────────────────────────────

class _Raw {
  const _Raw(
    this.text, {
    required this.glued,
    this.level = 0,
    this.style,
    this.link,
  });

  final String text;
  final bool glued;
  final int level;
  final TextStyle? style;
  final String? link;

  bool get isBreak => text == '\n';
  bool get isPunctuation => text.split('').every(_punctuation.contains);
}

const _punctuation = '.,;:!?…';

bool _isSpace(String ch) => ch == ' ' || ch == '\t' || ch == '\r';
bool _isWhite(String ch) => _isSpace(ch) || ch == '\n';

/// `[label](url)` starting at [i]: (index of `]`, index after `)`, url).
(int, int, String)? _linkAt(String s, int i) {
  var j = i + 1;
  while (j < s.length && s[j] != ']') {
    if (s[j] == '[' || s[j] == '\n') return null;
    j++;
  }
  if (j >= s.length || j == i + 1) return null;
  if (j + 1 >= s.length || s[j + 1] != '(') return null;
  var k = j + 2;
  while (k < s.length && s[k] != ')') {
    if (_isWhite(s[k])) return null;
    k++;
  }
  if (k >= s.length || k == j + 2) return null;
  return (j, k + 1, s.substring(j + 2, k));
}

/// Splits [src] into words, glued punctuation and paragraph breaks, reading
/// inline markup. With [levels], `[..]` and `{..}` set levels 1 and 2.
List<_Raw> _scan(String src, {required bool levels}) {
  final out = <_Raw>[];
  final buf = StringBuffer();
  var bufIsPunct = false;
  var level = 0;
  String? openedBy;
  var bold = false, italic = false;
  String? link;
  var linkLabelEnd = -1, linkEnd = -1;
  var sawSpace = true;
  var glued = false;

  TextStyle? style() => bold || italic
      ? TextStyle(
          fontWeight: bold ? FontWeight.bold : null,
          fontStyle: italic ? FontStyle.italic : null,
        )
      : null;

  void flush() {
    if (buf.isEmpty) return;
    out.add(
      _Raw(
        buf.toString(),
        glued: glued,
        level: level,
        style: style(),
        link: link,
      ),
    );
    buf.clear();
  }

  void write(String ch, {required bool punct}) {
    // Punctuation is its own glued token, so versions compare word by word.
    if (buf.isNotEmpty && bufIsPunct != punct) flush();
    if (buf.isEmpty) {
      glued = !sawSpace && out.isNotEmpty;
      sawSpace = false;
      bufIsPunct = punct;
    }
    buf.write(ch);
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

  var i = 0;
  while (i < src.length) {
    final ch = src[i];

    if (ch == r'\' && i + 1 < src.length && src[i + 1] != '\n') {
      write(src[i + 1], punct: false);
      i += 2;
      continue;
    }

    if (ch == '*') {
      final isDouble = i + 1 < src.length && src[i + 1] == '*';
      final len = isDouble ? 2 : 1;
      final opening = isDouble ? !bold : !italic;
      final before = i > 0 ? src[i - 1] : ' ';
      final after = i + len < src.length ? src[i + len] : ' ';
      // Like Markdown: an opening delimiter must touch the next word and a
      // closing one the previous word, so "5 * 3" stays literal.
      if (opening ? !_isWhite(after) : !_isWhite(before)) {
        flush();
        if (isDouble) {
          bold = !bold;
        } else {
          italic = !italic;
        }
        i += len;
        continue;
      }
      for (var k = 0; k < len; k++) {
        write('*', punct: false);
      }
      i += len;
      continue;
    }

    if (ch == '[' && link == null) {
      final found = _linkAt(src, i);
      if (found != null) {
        flush();
        (linkLabelEnd, linkEnd, link) = found;
        i++;
        continue;
      }
    }
    if (link != null && i == linkLabelEnd) {
      flush();
      link = null;
      i = linkEnd;
      continue;
    }

    if (levels) {
      switch (ch) {
        case '[':
          open(ch, 1, i);
          i++;
          continue;
        case '{':
          open(ch, 2, i);
          i++;
          continue;
        case ']':
          close('[', ch, i);
          i++;
          continue;
        case '}':
          close('{', ch, i);
          i++;
          continue;
      }
    }

    if (_isSpace(ch)) {
      flush();
      sawSpace = true;
    } else if (ch == '\n') {
      flush();
      out.add(const _Raw('\n', glued: false));
      sawSpace = true;
    } else {
      write(ch, punct: _punctuation.contains(ch));
    }
    i++;
  }
  if (openedBy != null) {
    throw FormatException('Unclosed "$openedBy"', src, src.length);
  }
  flush();
  return out;
}

// ───────────────────────────── versions ─────────────────────────────

List<LeveledToken> _fromVersions(
  List<String> versions,
  bool requireSubsequence,
) {
  if (versions.isEmpty) {
    throw ArgumentError.value(versions, 'versions', 'must not be empty');
  }

  LeveledToken token(_Raw r, int level) => LeveledToken(
        r.text,
        level,
        glued: r.glued,
        style: r.style,
        link: r.link,
      );

  var stream = [
    for (final r in _scan(versions.first, levels: false)) token(r, 0),
  ];

  for (var v = 1; v < versions.length; v++) {
    final next = _scan(versions[v], levels: false);
    final alive = [
      for (var i = 0; i < stream.length; i++)
        if (stream[i].maxLevel == null) i,
    ];
    final ops = _diff(
      [for (final i in alive) stream[i].text],
      [for (final r in next) r.text],
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
            LeveledToken(
              t.text,
              t.minLevel,
              maxLevel: v - 1,
              glued: t.glued,
              style: t.style,
              link: t.link,
            ),
          );
        case _Op.insert:
          merged.add(token(next[b], v));
      }
    }
    copyDeadUpTo(stream.length);
    stream = merged;
  }
  return stream;
}

LeveledVersionsReport _check(List<String> versions) {
  final issues = <String>[];
  final transitions = <LeveledTransition>[];
  if (versions.length < 2) {
    issues.add('Provide at least two versions to morph between.');
  }

  final scanned = [
    for (final v in versions)
      [
        for (final r in _scan(v, levels: false))
          if (!r.isBreak) r,
      ],
  ];
  for (var i = 0; i < scanned.length; i++) {
    if (scanned[i].isEmpty) issues.add('Level $i is empty.');
  }

  for (var v = 1; v < scanned.length; v++) {
    final a = scanned[v - 1], b = scanned[v];
    final ops = _diff([for (final r in a) r.text], [for (final r in b) r.text]);
    var kept = 0, added = 0;
    final dropped = <String>[];
    for (final (op, ai, bi) in ops) {
      switch (op) {
        case _Op.keep:
          if (!a[ai].isPunctuation) kept++;
        case _Op.delete:
          if (!a[ai].isPunctuation) dropped.add(a[ai].text);
        case _Op.insert:
          if (!b[bi].isPunctuation) added++;
      }
    }
    final t = LeveledTransition._(
      fromLevel: v - 1,
      kept: kept,
      added: added,
      dropped: List.unmodifiable(dropped),
    );
    transitions.add(t);

    if (added == 0 && dropped.isEmpty) {
      issues.add('Level $v adds nothing to level ${v - 1}.');
    }
    if (dropped.isNotEmpty) {
      final shown = dropped.take(5).map((w) => '"$w"').join(', ');
      final more = dropped.length > 5 ? ', …' : '';
      issues.add(
        'Level $v drops ${dropped.length} word${dropped.length == 1 ? '' : 's'} '
        'of level ${v - 1} ($shown$more); they will cross-fade.',
      );
    }
    if (t.carryOver < 0.5) {
      issues.add(
        'Level $v keeps only ${(t.carryOver * 100).round()}% of level '
        '${v - 1}; the change will look like a cross-fade, not a stretch.',
      );
    }
  }
  return LeveledVersionsReport._(
    List.unmodifiable(transitions),
    List.unmodifiable(issues),
  );
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
