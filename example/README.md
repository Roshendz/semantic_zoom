# semantic_zoom example

Three demos, one per use case:

- **Travel**: a trip journal written in `LeveledText.parse` markup, with a
  header sliver composed by hand from `SemanticZoomDetector` and
  `SliverSemanticZoomList`. Highlights → day summary → full entry.
- **Health**: a patient timeline built with `LeveledText.fromVersions` and
  the one-widget `SemanticZoomListView.builder`. Visit title → summary →
  clinician notes.
- **Inbox**: AI-style summaries at three lengths that rephrase as well as
  extend. Shared words slide; rephrased words cross-fade.

In every demo, pinch the list to change every entry, tap one entry to change
just that one, or use the buttons at the bottom.

```sh
flutter run            # iOS Simulator: hold ⌥ and drag to pinch
flutter run -d chrome  # trackpad pinch, ctrl + scroll, or Ctrl/⌘ + / −
```
