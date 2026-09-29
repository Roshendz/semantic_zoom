## 0.3.1

Documentation only; no code changes.

* New demo GIF recorded from the current example app.
* README: lists, chats and grids in the introduction; a Contributing
  section explaining `tool/check.sh`, the screenshot tests and the device
  test.
* Shorter pub.dev description mentioning chats, grids and languages.

## 0.3.0

All additions are opt-in; existing code works unchanged.

* **Chat-style lists.** Anchoring works in reversed lists (newest item at the
  bottom). New `SemanticZoomListView.builder(reverse:)`.
* **Grids.** `SliverSemanticZoomGrid` and `SemanticZoomGridView`, with fixed
  (`crossAxisCount`) or width-based (`maxCrossAxisExtent`) columns.
* **Chinese, Japanese, Thai, Lao, Khmer and Myanmar** text morphs and wraps
  per character. Text in other languages is tokenised exactly as before.
* **Load on demand.** `LeveledTextLoader` and `LazyLeveledTextView` show the
  brief text at once and fetch longer versions when an entry is expanded.
* **Remember the level.** `restorationId` on the list, grid, detector and
  `ExpandableLeveledText`; `PageStorageKey` keeps an expandable card open
  after scrolling away.
* New controller methods: `holdAnchor`, `itemLevels`, `restoreLevel`,
  `restoreItemLevels`.
* **Fixed:** scrolling to the start (`jumpTo(0)`, `animateTo(0)`, the iOS
  status-bar tap) after a pinch stopped short of the first item.
* **Fixed:** `ExpandableLeveledText` crashed when rebuilt with a new
  `levelLabels` list or text with a different number of levels.
* **Fixed:** on a short list, zooming out after zooming in could make
  layout loop until Flutter gave up ("RenderViewport exceeded its maximum
  number of layout cycles"), e.g. on phone-sized screens.
* Performance numbers and a benchmark you can run on your own device.
* New dependency: `characters` (already part of Flutter).

## 0.2.0

* **Rich text.** `**bold**`, `*italic*` and `[label](url)` links in both
  `LeveledText.parse` and `LeveledText.fromVersions`, plus `\` escapes.
  `LeveledToken` gains `style` and `link`. Styled words are measured with
  their real style.
* **Links.** `LeveledTextView.onLinkTap` and `linkStyle`. Links are tap
  targets that follow the morph, show a click cursor, are announced as links
  to screen readers, and keep a continuous underline across words.
* **`ExpandableLeveledText`**: a single tap-to-expand text with no list or
  controller, an optional footer (e.g. "Show more"), `onLevelChanged`, and
  `expand()` / `collapse()` / `next()` via `ExpandableLeveledTextState`.
* **LLM helpers.** `LeveledPrompt.build` writes a prompt asking a model for
  versions that morph smoothly; `LeveledPrompt.parseResponse` reads the
  reply; `LeveledText.checkVersions` reports how many words carry over
  between levels, which ones are dropped, and any problems.
* `LeveledText.parse` now splits trailing punctuation into its own glued
  token, like `fromVersions`. Rendered text is unchanged.

## 0.1.0

* Initial release.
* `LeveledText.parse`: bracket markup for three levels.
* `LeveledText.fromVersions`: any number of plain versions. Words shared by
  consecutive versions slide; rewritten words cross-fade, so LLM or
  hand-written summaries don't need to be strict word subsets.
  `requireSubsequence: true` enforces the strict StretchText contract.
* `LeveledTextView`: morphs between levels using Flutter's paragraph engine
  (correct line breaking, RTL and text scaling). No text measurement during
  the animation.
* `SemanticZoomController`: continuous zoom plus committed level, spring
  settle, reduce-motion support, and per-item levels (`setItemLevel`,
  `itemLevel`, `clearItemLevels`).
* `SemanticZoomDetector`: touch pinch, trackpad pinch, web ctrl+wheel, and
  Ctrl/⌘ `+` `−` `0` keyboard shortcuts. A pinch cancels taps, ink
  highlights and long presses on the items under the fingers.
* `SliverSemanticZoomList`: scroll anchoring applied during layout (no
  one-frame lag).
* `SemanticZoomListView.builder` for one-widget setup.
* Accessibility: each entry is an adjustable semantics node
  (increase/decrease) with optional `levelLabels`.
