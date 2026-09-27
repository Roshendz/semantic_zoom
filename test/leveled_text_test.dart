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
        LeveledToken('Alfama.', 0),
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
}
