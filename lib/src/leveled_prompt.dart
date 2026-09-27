import 'dart:convert';

import 'leveled_text.dart';

/// Helpers for asking an LLM to write versions of a text that morph
/// smoothly with [LeveledText.fromVersions].
///
/// The smoothest morphs come from versions where each longer one keeps
/// every word of the shorter one and only inserts words (StretchText). The
/// prompt asks for exactly that; check the result with
/// [LeveledText.checkVersions], since models don't always comply. Anything
/// they rephrase still cross-fades, so nothing breaks.
///
/// ```dart
/// final prompt = LeveledPrompt.build(source: note);
/// final reply = await myLlm.complete(prompt); // any LLM client
/// final versions = LeveledPrompt.parseResponse(reply);
/// final report = LeveledText.checkVersions(versions);
/// if (report.smoothness < 0.8) { /* retry, or log report.issues */ }
/// final text = LeveledText.fromVersions(versions);
/// ```
abstract final class LeveledPrompt {
  /// Default description of each level, by position.
  static const defaultLevelDescriptions = [
    'a title of at most 6 words',
    'one sentence of at most 25 words',
    'the complete text',
  ];

  /// A prompt asking for [levels] versions of [source], briefest first,
  /// returned as JSON.
  ///
  /// [levelDescriptions] describes each level (defaults to
  /// [defaultLevelDescriptions], stretched to [levels]). [instructions] adds
  /// extra guidance such as tone, audience or language.
  static String build({
    required String source,
    int levels = 3,
    List<String>? levelDescriptions,
    String? instructions,
  }) {
    if (levels < 2) {
      throw ArgumentError.value(levels, 'levels', 'must be at least 2');
    }
    if (levelDescriptions != null && levelDescriptions.length != levels) {
      throw ArgumentError.value(
        levelDescriptions,
        'levelDescriptions',
        'must have $levels entries',
      );
    }
    final descriptions = levelDescriptions ?? _descriptions(levels);

    final b = StringBuffer()
      ..writeln(
        'Write $levels versions of the source text below, from shortest to '
        'longest, for an app where readers pinch to see more or less '
        'detail. Each longer version grows out of the shorter one so its '
        'words can animate into place.',
      )
      ..writeln()
      ..writeln('Versions:');
    for (var i = 0; i < levels; i++) {
      b.writeln('${i + 1}. ${descriptions[i]}');
    }
    b
      ..writeln()
      ..writeln('Rules:')
      ..writeln(
        '- Every version must contain all words of the version before it, '
        'in the same order, with the same spelling, capitalisation and '
        'punctuation. Only insert new words between them. Never remove, '
        'reorder or rephrase a word.',
      )
      ..writeln(
        '- Use only information from the source. Do not add facts, '
        'opinions or advice.',
      )
      ..writeln(
        '- Plain sentences. You may mark key terms as **bold**. No '
        'headings, lists or emojis.',
      );
    if (instructions != null && instructions.trim().isNotEmpty) {
      b.writeln('- ${instructions.trim()}');
    }
    b
      ..writeln(
        '- Reply with JSON only, no other text: '
        '{"levels": ["version 1", "version 2", ...]}',
      )
      ..writeln()
      ..writeln('Example of the growth pattern:')
      ..writeln(jsonEncode({'levels': _example.take(levels).toList()}))
      ..writeln()
      ..writeln('Source:')
      ..writeln('"""')
      ..writeln(source.trim())
      ..write('"""');
    return b.toString();
  }

  /// Extracts the versions from an LLM reply to [build]'s prompt.
  ///
  /// Accepts `{"levels": [...]}` or a bare JSON array, optionally inside a
  /// Markdown code fence or surrounded by other text. Throws a
  /// [FormatException] if no list of strings can be found.
  static List<String> parseResponse(String response) {
    final start = _firstOf(response, const ['{', '[']);
    final end = _lastOf(response, const ['}', ']']);
    if (start == -1 || end < start) {
      throw FormatException('No JSON found in the response', response);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.substring(start, end + 1));
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON: ${e.message}', response);
    }
    final list = decoded is Map ? decoded['levels'] : decoded;
    if (list is! List || list.isEmpty || list.any((e) => e is! String)) {
      throw FormatException(
        'Expected {"levels": [...]} with a list of strings',
        response,
      );
    }
    return [for (final e in list) (e as String).trim()];
  }

  // Each line only inserts words into the one before it.
  static const _example = [
    'Knee review',
    'Knee review: swelling reduced, cleared to run',
    'Knee review after six sessions: swelling reduced and range of motion '
        'restored, cleared to run twice a week.',
    'Knee review after six sessions with the physiotherapist: swelling '
        'reduced and range of motion fully restored, cleared to run twice a '
        'week on flat ground.',
  ];

  static List<String> _descriptions(int levels) => [
        for (var i = 0; i < levels; i++)
          if (i == 0)
            defaultLevelDescriptions.first
          else if (i == levels - 1)
            defaultLevelDescriptions.last
          else
            levels == 3
                ? defaultLevelDescriptions[1]
                : 'a summary of about ${25 * i} words',
      ];

  static int _firstOf(String s, List<String> chars) {
    var best = -1;
    for (final c in chars) {
      final i = s.indexOf(c);
      if (i != -1 && (best == -1 || i < best)) best = i;
    }
    return best;
  }

  static int _lastOf(String s, List<String> chars) {
    var best = -1;
    for (final c in chars) {
      final i = s.lastIndexOf(c);
      if (i > best) best = i;
    }
    return best;
  }
}
