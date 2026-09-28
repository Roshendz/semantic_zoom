// Proves that text without Chinese, Japanese, Thai, Lao, Khmer or Myanmar
// characters is tokenised exactly as in the published 0.2.0, by comparing
// against a frozen copy of that parser on thousands of random inputs.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

import 'legacy/leveled_text_0_2_0.dart' as legacy;

// Every script and markup the parser already handled; no newly segmented
// scripts, so output must be identical.
const _words = [
  'Tram',
  'tram',
  'Alfama',
  'the',
  'a',
  'I',
  'co-op',
  "don't",
  '10K',
  '4.2.1',
  '128/82',
  'e.g.',
  'café',
  'naïve',
  'São',
  'Größe',
  'żółw',
  'привет',
  'мир',
  'λόγος',
  'سلام',
  'عليكم',
  'שלום',
  'עולם',
  '한국어',
  '문장',
  'نص',
  '😀',
  '👍🏽',
  'ﬁ',
  'x',
  '5',
  '3',
  '=',
  '+',
  '-',
  '—',
  '/',
  '#tag',
  '@me',
  '%',
  'https://ex.am/p',
  'mailto:a@b.c',
];
const _markup = [
  '[',
  ']',
  '{',
  '}',
  '*',
  '**',
  '(',
  ')',
  r'\[',
  r'\]',
  r'\{',
  r'\*',
  r'\',
  '[docs](https://docs.example)',
  '[a b](x)',
  '**bold**',
  '*it*',
  ' * ',
  '[]()',
  '[x](a b)',
  '[(x)]',
];
const _space = [' ', ' ', ' ', '  ', '\n', '\t', '\r\n', ''];
const _punct = ['.', ',', ';', ':', '!', '?', '…', '...', '?!', ''];

String _randomText(Random r, {bool markup = true}) {
  final b = StringBuffer();
  final n = r.nextInt(14);
  for (var i = 0; i < n; i++) {
    final roll = r.nextDouble();
    if (markup && roll < 0.22) {
      b.write(_markup[r.nextInt(_markup.length)]);
    } else {
      b.write(_words[r.nextInt(_words.length)]);
      if (r.nextDouble() < 0.25) b.write(_punct[r.nextInt(_punct.length)]);
    }
    b.write(_space[r.nextInt(_space.length)]);
  }
  return b.toString();
}

List<String> _randomVersions(Random r) {
  var words = [
    for (var i = 0; i < 1 + r.nextInt(5); i++) _randomText(r, markup: false),
  ].join(' ').split(' ');
  final versions = [words.join(' ')];
  for (var v = 1; v < 2 + r.nextInt(3); v++) {
    final next = <String>[];
    for (final w in words) {
      final roll = r.nextDouble();
      if (roll < 0.1) continue; // drop
      if (roll < 0.2) {
        next.add(_words[r.nextInt(_words.length)]); // rewrite
        continue;
      }
      next.add(w);
      if (roll > 0.7) next.add(_words[r.nextInt(_words.length)]); // insert
    }
    if (r.nextDouble() < 0.3) next.add('**${_words[r.nextInt(8)]}**');
    words = next;
    versions.add(words.join(' '));
  }
  return versions;
}

Object _tokens(List<Object> tokens) => [
      for (final t in tokens)
        switch (t) {
          LeveledToken() => (
              t.text,
              t.minLevel,
              t.maxLevel,
              t.glued,
              t.style,
              t.link,
            ),
          legacy.LeveledToken() => (
              t.text,
              t.minLevel,
              t.maxLevel,
              t.glued,
              t.style,
              t.link,
            ),
          _ => throw StateError('unexpected $t'),
        },
    ];

Object _outcome(Object Function() run) {
  try {
    return run();
  } on FormatException catch (e) {
    return ('FormatException', e.message, e.offset);
  } on ArgumentError catch (e) {
    return ('ArgumentError', e.message);
  }
}

void main() {
  test('parse: identical tokens and errors on 4000 random texts', () {
    final r = Random(20260928);
    for (var i = 0; i < 4000; i++) {
      final src = _randomText(r);
      final now = _outcome(() {
        final t = LeveledText.parse(src);
        return [
          _tokens(t.tokens),
          t.maxLevel,
          [for (var l = 0; l <= 3; l++) t.textAt(l)],
        ];
      });
      final then = _outcome(() {
        final t = legacy.LeveledText.parse(src);
        return [
          _tokens(t.tokens),
          t.maxLevel,
          [for (var l = 0; l <= 3; l++) t.textAt(l)],
        ];
      });
      expect(now, then, reason: 'input #$i: ${src.replaceAll('\n', r'\n')}');
    }
  });

  test('fromVersions and checkVersions: identical on 1500 random sets', () {
    final r = Random(1970);
    for (var i = 0; i < 1500; i++) {
      final versions = _randomVersions(r);
      for (final strict in [false, true]) {
        final now = _outcome(() {
          final t = LeveledText.fromVersions(
            versions,
            requireSubsequence: strict,
          );
          return [_tokens(t.tokens), t.maxLevel];
        });
        final then = _outcome(() {
          final t = legacy.LeveledText.fromVersions(
            versions,
            requireSubsequence: strict,
          );
          return [_tokens(t.tokens), t.maxLevel];
        });
        expect(now, then, reason: 'set #$i strict=$strict: $versions');
      }
      final a = LeveledText.checkVersions(versions);
      final b = legacy.LeveledText.checkVersions(versions);
      expect(
        [
          a.isStrict,
          a.smoothness,
          a.issues,
          for (final t in a.transitions)
            [t.fromLevel, t.kept, t.added, t.dropped],
        ],
        [
          b.isStrict,
          b.smoothness,
          b.issues,
          for (final t in b.transitions)
            [t.fromLevel, t.kept, t.added, t.dropped],
        ],
        reason: 'set #$i: $versions',
      );
    }
  });
}
