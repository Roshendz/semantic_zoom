import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

void main() {
  group('LeveledText.parse', () {
    test('assigns levels and glue', () {
      expect(LeveledText.parse('tram{, old} [to] Alfama.').tokens, const [
        LeveledToken('tram', 0),
        LeveledToken(',', 2, glued: true),
        LeveledToken('old', 2),
        LeveledToken('to', 1),
        LeveledToken('Alfama', 0),
        LeveledToken('.', 0, glued: true),
      ]);
    });

    test('renders each level', () {
      final t = LeveledText.parse(
        '[Took] Tram 28 [up] to Alfama{, standing room only,} [and walked.]',
      );
      expect(t.maxLevel, 2);
      expect(t.textAt(0), 'Tram 28 to Alfama');
      expect(t.textAt(1), 'Took Tram 28 up to Alfama and walked.');
      expect(
        t.textAt(2),
        'Took Tram 28 up to Alfama, standing room only, and walked.',
      );
    });

    test('collapses paragraphs that are empty at a level', () {
      final t = LeveledText.parse('a\n[b]\nc');
      expect(t.textAt(0), 'a\nc');
      expect(t.textAt(1), 'a\nb\nc');
    });

    for (final bad in ['[a', 'a]', '[a {b}]', '{a]', 'a}']) {
      test('rejects "$bad"', () {
        expect(() => LeveledText.parse(bad), throwsFormatException);
      });
    }
  });

  group('LeveledText.fromVersions', () {
    test('derives levels from nested versions', () {
      final t = LeveledText.fromVersions(const [
        'Port tasting',
        'Port tasting in Gaia today',
        'Port tasting in Gaia today with a surprising white.',
      ]);
      expect(t.textAt(0), 'Port tasting');
      expect(t.textAt(1), 'Port tasting in Gaia today');
      expect(
        t.textAt(2),
        'Port tasting in Gaia today with a surprising white.',
      );
      expect(t.tokens.map((e) => e.minLevel), [0, 0, 1, 1, 1, 2, 2, 2, 2, 2]);
    });

    test('splits punctuation so versions round-trip exactly', () {
      const versions = [
        'Blood pressure follow-up',
        'Blood pressure follow-up: readings improved, dose unchanged',
        'Blood pressure follow-up: home readings averaged 128/82 over four '
            'weeks, readings improved, dose unchanged. Review in three months.',
      ];
      final t = LeveledText.fromVersions(versions);
      for (var i = 0; i < versions.length; i++) {
        expect(t.textAt(i), versions[i]);
      }
    });

    test('keeps paragraph breaks', () {
      final t = LeveledText.fromVersions(const ['a b', 'a b\nc']);
      expect(t.textAt(0), 'a b');
      expect(t.textAt(1), 'a b\nc');
    });

    test('requireSubsequence rejects rewritten versions', () {
      expect(
        () => LeveledText.fromVersions(
          const ['tram to Alfama', 'Alfama by tram'],
          requireSubsequence: true,
        ),
        throwsArgumentError,
      );
    });

    test('rewritten versions share common words and swap the rest', () {
      const versions = [
        'Tram to Alfama',
        'Took the tram up to Alfama at dawn',
        'Took the old tram up to Alfama, standing room only.',
      ];
      final t = LeveledText.fromVersions(versions);
      for (var i = 0; i < versions.length; i++) {
        expect(t.textAt(i), versions[i]);
      }
      final alfama = t.tokens.firstWhere((e) => e.text == 'Alfama');
      expect(
          (alfama.minLevel, alfama.maxLevel), (0, null)); // slides, never fades
      final tram = t.tokens.firstWhere((e) => e.text == 'Tram');
      expect((tram.minLevel, tram.maxLevel), (0, 0)); // fades out
      final dawn = t.tokens.firstWhere((e) => e.text == 'dawn');
      expect((dawn.minLevel, dawn.maxLevel), (1, 1)); // in at 1, out at 2
      expect(t.maxLevel, 2);
    });

    test('handles completely different versions', () {
      final t = LeveledText.fromVersions(const ['Alpha beta', 'Gamma delta']);
      expect(t.textAt(0), 'Alpha beta');
      expect(t.textAt(1), 'Gamma delta');
    });

    test('supports more than three levels', () {
      final t =
          LeveledText.fromVersions(const ['a', 'a b', 'a b c', 'a b c d']);
      expect(t.maxLevel, 3);
      expect(t.textAt(3), 'a b c d');
    });

    test('rejects an empty list', () {
      expect(() => LeveledText.fromVersions(const []), throwsArgumentError);
    });
  });

  test('equality is by tokens', () {
    expect(LeveledText.parse('a [b]'), LeveledText.parse('a [b]'));
    expect(LeveledText.parse('a [b]'), isNot(LeveledText.parse('a {b}')));
  });

  group('rich markup', () {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    const italic = TextStyle(fontStyle: FontStyle.italic);

    test('bold, italic and links in parse', () {
      final t = LeveledText.parse(
        'Tram **28**[ to *Alfama*]{, see [the map](https://ex.am/p).}',
      );
      expect(t.textAt(0), 'Tram 28');
      expect(t.textAt(2), 'Tram 28 to Alfama, see the map.');
      final byText = {for (final k in t.tokens) k.text: k};
      expect(byText['28']!.style, bold);
      expect(byText['Alfama']!.style, italic);
      expect(byText['Alfama']!.minLevel, 1);
      expect(byText['the']!.link, 'https://ex.am/p');
      expect(byText['map']!.link, 'https://ex.am/p');
      expect(byText['map']!.minLevel, 2);
      expect(byText['see']!.link, isNull);
    });

    test('a bracket group without (url) is still a level', () {
      final t = LeveledText.parse('[Took] a [tram](x) up');
      expect(t.textAt(0), 'a tram up');
      expect(t.textAt(1), 'Took a tram up');
      expect(t.tokens.firstWhere((k) => k.text == 'tram').link, 'x');
    });

    test('style changes inside a word keep it glued', () {
      final t = LeveledText.parse('**Note:** read this');
      expect(t.textAt(0), 'Note: read this');
      expect(t.tokens[0].style, bold);
      expect(t.tokens[1].text, ':');
      expect(t.tokens[1].glued, isTrue);
      expect(t.tokens[2].style, isNull);
    });

    test('lone asterisks and escapes stay literal', () {
      expect(LeveledText.parse('5 * 3 = 15').textAt(0), '5 * 3 = 15');
      final t = LeveledText.parse(r'\[not a level\] and \*literal\*');
      expect(t.textAt(0), '[not a level] and *literal*');
      expect(t.tokens.every((k) => k.style == null), isTrue);
    });

    test('fromVersions reads markdown from LLM output', () {
      final t = LeveledText.fromVersions(const [
        'Knee review',
        'Knee review: **cleared to run**',
        'Knee review: **cleared to run** twice a week, see [plan](p1).',
      ]);
      expect(t.textAt(1), 'Knee review: cleared to run');
      expect(
        t.textAt(2),
        'Knee review: cleared to run twice a week, see plan.',
      );
      expect(t.tokens.firstWhere((k) => k.text == 'run').style, bold);
      expect(t.tokens.firstWhere((k) => k.text == 'plan').link, 'p1');
    });

    test('brackets are literal in fromVersions', () {
      final t = LeveledText.fromVersions(const ['a [b] c', 'a [b] c d']);
      expect(t.textAt(0), 'a [b] c');
    });
  });

  group('checkVersions', () {
    test('strict versions', () {
      final r = LeveledText.checkVersions(const [
        'Knee review',
        'Knee review: swelling reduced, cleared to run',
        'Knee review after six sessions: swelling reduced and range of '
            'motion restored, cleared to run twice a week.',
      ]);
      expect(r.isStrict, isTrue);
      expect(r.smoothness, 1);
      expect(r.issues, isEmpty);
      expect(r.transitions.first.kept, 2);
      expect(r.transitions.first.added, 5);
    });

    test('rewrites are reported with the dropped words', () {
      final r = LeveledText.checkVersions(const [
        'Checkout crash fixed',
        'Android checkout crash is fixed in version 4.2.1',
      ]);
      expect(r.isStrict, isFalse);
      expect(r.transitions.single.dropped, ['Checkout']);
      expect(r.smoothness, closeTo(2 / 3, 1e-9));
      expect(r.issues.single, contains('"Checkout"'));
    });

    test('unrelated versions warn that they will cross-fade', () {
      final r = LeveledText.checkVersions(const ['Alpha beta', 'Gamma delta']);
      expect(r.smoothness, 0);
      expect(r.issues.any((i) => i.contains('keeps only 0%')), isTrue);
    });

    test('identical and empty levels are flagged', () {
      expect(
        LeveledText.checkVersions(const ['a b', 'a b']).issues,
        contains('Level 1 adds nothing to level 0.'),
      );
      expect(
        LeveledText.checkVersions(const ['', 'a']).issues,
        contains('Level 0 is empty.'),
      );
      expect(
        LeveledText.checkVersions(const ['only one']).issues,
        isNotEmpty,
      );
    });
  });
}
