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
  Ctrl/⌘ `+` `−` `0` keyboard shortcuts.
* `SliverSemanticZoomList`: scroll anchoring applied during layout (no
  one-frame lag).
* `SemanticZoomListView.builder` for one-widget setup.
* Accessibility: each entry is an adjustable semantics node
  (increase/decrease) with optional `levelLabels`.
