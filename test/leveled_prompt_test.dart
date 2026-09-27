import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

void main() {
  group('build', () {
    test('describes each level, the rules and the source', () {
      final p = LeveledPrompt.build(source: '  Patient seen for knee pain.  ');
      expect(p, contains('Write 3 versions'));
      expect(p, contains('1. a title of at most 6 words'));
      expect(p, contains('3. the complete text'));
      expect(p, contains('Only insert new words'));
      expect(p, contains('Do not add facts'));
      expect(p, contains('{"levels": ["version 1", "version 2", ...]}'));
      expect(p, endsWith('"""\nPatient seen for knee pain.\n"""'));
    });

    test('custom levels, descriptions and instructions', () {
      final p = LeveledPrompt.build(
        source: 'x',
        levels: 2,
        levelDescriptions: const ['a subject line', 'a two-line summary'],
        instructions: 'Write in Italian.',
      );
      expect(p, contains('Write 2 versions'));
      expect(p, contains('2. a two-line summary'));
      expect(p, contains('- Write in Italian.'));
    });

    test('stretches default descriptions to more levels', () {
      final p = LeveledPrompt.build(source: 'x', levels: 4);
      expect(p, contains('2. a summary of about 25 words'));
      expect(p, contains('3. a summary of about 50 words'));
      expect(p, contains('4. the complete text'));
    });

    test('rejects bad arguments', () {
      expect(() => LeveledPrompt.build(source: 'x', levels: 1),
          throwsArgumentError);
      expect(
        () => LeveledPrompt.build(
          source: 'x',
          levelDescriptions: const ['only one'],
        ),
        throwsArgumentError,
      );
    });

    test('its own example follows the rule it teaches', () {
      for (final levels in [2, 3, 4]) {
        final p = LeveledPrompt.build(source: 'x', levels: levels);
        final json = p.split('\n').firstWhere((l) => l.startsWith('{"levels"'));
        final example = LeveledPrompt.parseResponse(json);
        expect(example, hasLength(levels));
        final report = LeveledText.checkVersions(example);
        expect(report.isStrict, isTrue, reason: report.issues.join('\n'));
        expect(report.issues, isEmpty);
      }
    });
  });

  group('parseResponse', () {
    const versions = ['A', 'A b', 'A b c.'];

    test('plain JSON object', () {
      expect(
        LeveledPrompt.parseResponse(jsonEncode({'levels': versions})),
        versions,
      );
    });

    test('code fence and surrounding chatter', () {
      final reply = 'Sure! Here you go:\n```json\n'
          '${jsonEncode({'levels': versions})}\n```\nLet me know!';
      expect(LeveledPrompt.parseResponse(reply), versions);
    });

    test('bare array, trimming whitespace', () {
      expect(LeveledPrompt.parseResponse('[" A ", "A b"]'), ['A', 'A b']);
    });

    test('rejects replies without a list of strings', () {
      for (final bad in [
        'no json here',
        '{"levels": []}',
        '{"levels": [1, 2]}',
        '{"other": ["a"]}',
        '{"levels": ["a",]',
      ]) {
        expect(
          () => LeveledPrompt.parseResponse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });
}
