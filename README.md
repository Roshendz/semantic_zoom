# semantic_zoom

[![pub package](https://img.shields.io/pub/v/semantic_zoom.svg)](https://pub.dev/packages/semantic_zoom)
[![CI](https://github.com/Roshendz/semantic_zoom/actions/workflows/ci.yml/badge.svg)](https://github.com/Roshendz/semantic_zoom/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Pinch to change how much a list says, not how big it is.**

Pinch out and every entry grows from a title, to a one-line summary, to the
full notes. Or tap a single entry to expand just that one. The font size
never changes. Words already on screen slide to their new spots and new
words fade in around them. The entry under your fingers stays exactly where
it is.

<p align="center"><img src="https://raw.githubusercontent.com/Roshendz/semantic_zoom/main/doc/demo.gif" width="320" alt="Pinching a travel journal from highlights to full entries, then tapping one day"></p>

**[Try the live demo →](https://roshendz.github.io/semantic_zoom/)** (trackpad pinch, ctrl + scroll, or Ctrl/⌘ + / − on desktop)

> Also known as **StretchText** (Ted Nelson, 1970), **telescopic text**,
> progressive disclosure, or an animated **expandable text / "read more"**
> that works for a whole list at once. Nelson's idea was a short text whose
> words carry over into a longer one, with new words inserted around them.
> This package is that idea, driven by a pinch.

## Why not `InteractiveViewer`?

`InteractiveViewer` and `Transform.scale` zoom pixels. This package zooms
*meaning*: a continuous detail level that reflows real text.

> Not the same as the Windows/WinUI `SemanticZoom` control, which switches
> between a grouped overview (A–Z headers) and the full list. Here every
> item stays in place and its **text** gets longer or shorter.

It suits anything with summaries and details:

- journals, notes and feeds
- patient timelines (visit title → summary → clinician notes)
- changelogs, audit logs, search results, email threads
- LLM-generated summaries at several lengths

## Features

- 🔤 **Real text layout.** Flutter's paragraph engine handles line breaking,
  right-to-left scripts and system text scaling. Layout is cached per level,
  so nothing is measured during a pinch.
- ✍️ **Works with rewritten summaries.** Versions don't have to be strict
  word subsets. Shared words slide, and the rest cross-fade in place, so LLM
  or hand-written summaries just work.
- 👆 **Whole list or one item.** Pinch changes every entry; tap (or any
  callback) changes one entry with `setItemLevel`. The next pinch brings
  every entry back into step.
- 📖 **Animated "read more" in one widget.** `ExpandableLeveledText` expands
  a single text in place on tap, with no list or controller to set up.
- 🅱️ **Rich text.** `**bold**`, `*italic*` and `[links](https://…)` in any
  level. Links are real tap targets and are announced as links.
- 🤖 **LLM-ready.** A ready-made prompt asks a model for versions that
  morph smoothly, and `checkVersions` tells you how well it complied.
- 📌 **Lag-free scroll anchoring.** A custom sliver corrects the scroll offset
  *during layout*, so the item under your fingers doesn't drift, not even by
  one frame.
- 🤏 **Every input.** Touch pinch, trackpad pinch (macOS, Windows, web),
  ctrl + scroll wheel on the web, and Ctrl/⌘ `+` `−` `0` on a keyboard.
  Two-finger trackpad scrolling still scrolls, and a pinch never triggers
  taps or ripples on the entries under your fingers.
- ♿ **Accessible.** Each entry is an *adjustable* control for VoiceOver and
  TalkBack (swipe up/down to change detail) with named levels. Screen readers
  read the text at the current level, and the reduce-motion setting skips
  the spring.
- 🌀 **Physics.** Rubber-banding past the first and last levels, velocity
  projection, a spring settle and a haptic tick.
- 🧱 **Composable.** A one-widget list, or the pieces inside your own
  `CustomScrollView`. Any number of levels.

## Install

```sh
flutter pub add semantic_zoom
```

## Quick start

```dart
class Journal extends StatefulWidget {
  const Journal({super.key});
  @override
  State<Journal> createState() => _JournalState();
}

class _JournalState extends State<Journal> with SingleTickerProviderStateMixin {
  late final zoom = SemanticZoomController(vsync: this);

  final entries = [
    // plain = brief, [brackets] = medium, {braces} = full
    LeveledText.parse(
      '[Took] Tram 28 [up] to Alfama{, standing room only}'
      '[. Found a tiny bakery.]',
    ),
    // or plain versions, briefest first (e.g. from an LLM)
    LeveledText.fromVersions(const [
      'Port tasting',
      'Port tasting in Gaia',
      'Port tasting in Gaia: tawny, ruby and a surprising white.',
    ]),
  ];

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SemanticZoomListView.builder(
        controller: zoom,
        itemCount: entries.length,
        itemBuilder: (context, i) => InkWell(
          // Tap one entry to step just that entry to the next level.
          onTap: () => zoom.setItemLevel(i, zoom.itemLevel(i) + 1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LeveledTextView(entries[i], itemId: i),
          ),
        ),
      );
}
```

Add a button for people who can't or won't pinch:

```dart
ListenableBuilder(
  listenable: zoom, // rebuilds only when a committed level changes
  builder: (context, _) => SegmentedButton<int>(
    segments: const [
      ButtonSegment(value: 0, label: Text('Brief')),
      ButtonSegment(value: 1, label: Text('Medium')),
      ButtonSegment(value: 2, label: Text('Full')),
    ],
    selected: {zoom.level},
    onSelectionChanged: (s) => zoom.animateToLevel(s.first),
  ),
)
```

## Just one expandable text

Don't need a pinchable list? `ExpandableLeveledText` is an animated
"read more": each tap morphs to the next level, then back to the first.

```dart
ExpandableLeveledText(
  LeveledText.parse(
    'Offline-first apps feel faster[ because they read local data first]'
    '{ and sync in the background.}',
  ),
  footerBuilder: (context, level, maxLevel, toggle) => TextButton(
    onPressed: toggle,
    child: Text(level < maxLevel ? 'Show more' : 'Show less'),
  ),
)
```

Use a `GlobalKey<ExpandableLeveledTextState>` to call `expand()`,
`collapse()` or `next()` from elsewhere, and `onLevelChanged` to persist it.

## Your content

| | Input | Best for |
|---|---|---|
| `LeveledText.parse` | `plain`, `[level 1]`, `{level 2}`, `\n` for paragraphs | Content you author or a backend emits |
| `LeveledText.fromVersions` | A list of plain strings, briefest first, any number of levels | Summaries from an editor or an LLM |

`fromVersions` aligns consecutive versions word by word (longest common
subsequence):

```dart
LeveledText.fromVersions(const [
  'Skin check, nothing concerning',
  'Full skin check found no concerning moles',
]);
// "check" and "concerning" slide to their new spots; "Skin", "," and
// "nothing" fade out while "Full", "skin", "found", "no" and "moles" fade in.
// Matching is exact, so "Skin" and "skin" count as different words.
```

The smoothest morphs come from versions that *add* words to the shorter one
(StretchText style). To enforce that strictly, for example when validating
backend data, pass `requireSubsequence: true` and `fromVersions` throws an
`ArgumentError` on any rewrite.

## Rich text

Both `parse` and `fromVersions` read a small inline markup, at any level:

| Markup | Result |
|---|---|
| `**bold**` | **bold** |
| `*italic*` | *italic* |
| `[label](https://example.com)` | a link |
| `\[`, `\*`, `\{` … | a literal character |

```dart
LeveledTextView(
  LeveledText.parse(
    'Day trip to [Sintra](https://en.wikipedia.org/wiki/Sintra)'
    '[. **Pena Palace** was lost in fog]{ until noon.}',
  ),
  linkStyle: LeveledTextView.defaultLinkStyle.copyWith(color: Colors.teal),
  onLinkTap: (url) => launchUrl(Uri.parse(url)), // e.g. url_launcher
)
```

A bracket group directly followed by `(url)` is a link; any other `[…]` is a
level. A lone `*` with spaces around it, as in `5 * 3`, stays literal. For
full control, build `LeveledToken`s yourself with any `TextStyle`.

## Summaries from an LLM

`LeveledPrompt` builds a prompt that asks a model for versions where each
longer one keeps every word of the shorter one, which morphs best. Models
don't always comply, so check the result before showing it:

```dart
final prompt = LeveledPrompt.build(
  source: visitNotes,
  levelDescriptions: const [
    'a visit title of at most 5 words',
    'a one-sentence summary',
    'the full clinician notes, lightly edited',
  ],
  instructions: 'Write for the patient, in plain language.',
);
final reply = await llm.complete(prompt);          // any LLM client
final versions = LeveledPrompt.parseResponse(reply); // tolerates ```json fences

final report = LeveledText.checkVersions(versions);
report.isStrict;    // true if every level only adds words
report.smoothness;  // 0..1: share of words that carry over
report.issues;      // e.g. 'Level 2 drops 1 word of level 1 ("Checkout")…'

final text = LeveledText.fromVersions(versions); // rewrites still cross-fade
```

## Per-item zoom

```dart
zoom.setItemLevel(id, 2);   // expand one item
zoom.itemLevel(id);         // its committed level
zoom.clearItemLevels();     // back to the global level
```

`id` is whatever you pass as `LeveledTextView.itemId`, such as an index or a
database id. A pinch or `animateToLevel` returns every item to the global
level.

## Accessibility

- Each `LeveledTextView` is an adjustable semantics node. VoiceOver users
  swipe up or down, TalkBack users use the volume keys. Name the levels with
  `SemanticZoomController(levelLabels: ['Brief', 'Summary', 'Full notes'])`;
  the default is "Detail 1 of 3".
- Pinch isn't discoverable, so offer a visible control too (see above).
- `MediaQuery.disableAnimations` (reduce motion) makes level changes jump.
- The system text scale is respected.

## Using your own scroll view

`SemanticZoomListView` is a thin wrapper. To add headers or other slivers,
compose the pieces yourself:

```dart
SemanticZoomDetector(
  controller: zoom,
  builder: (context, isPinching) => CustomScrollView(
    physics: isPinching ? const NeverScrollableScrollPhysics() : null,
    slivers: [
      const SliverToBoxAdapter(child: MyHeader()),
      SliverSemanticZoomList.builder(
        controller: zoom,
        itemCount: items.length,
        itemBuilder: (context, i) => LeveledTextView(items[i], itemId: i),
      ),
    ],
  ),
)
```

## State management

`SemanticZoomController.zoom` changes on **every frame** during a pinch.
Don't push it through a Bloc, Riverpod provider or `setState`.

The controller itself is a `ChangeNotifier` that fires **only when a
committed level changes**, globally or for one item. That's the right hook
for persistence and analytics:

```dart
zoom.addListener(() => settingsCubit.saveDetailLevel(zoom.level));
```

## API

| Class | Role |
|---|---|
| `SemanticZoomController` | Continuous `zoom`, committed `level`, `animateToLevel`, `setItemLevel`, `itemLevel`, `levelLabels` |
| `SemanticZoomListView.builder` | Ready-made list: detector + scroll view + anchored sliver |
| `SemanticZoomDetector` | Turns touch, trackpad, wheel and keyboard input into zoom |
| `SliverSemanticZoomList` | `SliverList` with scroll anchoring applied during layout |
| `LeveledTextView` | Paints `LeveledText`, morphing between levels; `itemId` for per-item zoom; `onLinkTap` |
| `ExpandableLeveledText` | One tap-to-expand text, no controller needed |
| `LeveledText` / `LeveledToken` | The data model, with `parse`, `fromVersions` and `checkVersions` |
| `LeveledPrompt` | LLM prompt builder and response parser |
| `LeveledTextLayout` | The cached layout engine, if you want to paint it yourself |

## How it works

1. **Layout, once per level.** For each (level, width), the visible text is
   laid out as a real paragraph. Each word's position is read back with
   `TextPainter.getBoxesForSelection`, and the result is cached.
2. **Every frame.** Word positions and the entry height are interpolated
   between the two nearest levels and painted with a `CustomPainter`. Words
   appearing or disappearing share one layer per opacity.
3. **Gestures.** A raw `Listener`, not a `ScaleGestureRecognizer`. The list's
   drag recognizer wins the gesture arena for the first finger, so a scale
   recognizer would only ever see the second one.
4. **Anchoring.** When the zoom starts, the sliver records the item under
   the fingers (or the first visible one). On every layout it returns a
   `scrollOffsetCorrection`, so the viewport re-lays out in the same frame
   with that item back in place.
5. **Per-item zoom.** Each item's zoom is the global zoom plus a spring-animated
   offset, so a pinch can pull every item back into step smoothly.

## Limitations

- Inline widgets (chips, icons) inside text aren't supported yet.
- `LeveledText.parse` markup covers three levels; use `fromVersions` for more.
- Vertical and left-to-right horizontal lists (`AxisDirection.down` and
  `right`); reversed lists aren't anchored yet.
- A word wider than the line is positioned at its first fragment.
- Ligatures that span two words aren't formed, because each word is painted
  separately.
- Splitting is by spaces. CJK text without spaces needs explicit tokens.
- On the web, browsers may handle Ctrl/⌘ `+` / `−` as page zoom before the
  app sees them.

## Contributing

Issues and PRs are welcome. `flutter analyze` and `flutter test` must pass. CI
also runs on the minimum supported Flutter version.

## License

MIT
