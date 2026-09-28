/// Pinch to change how much text a list shows, not how big it is.
///
/// For a single tap-to-expand text, use [ExpandableLeveledText]. For a
/// pinchable list, start with [SemanticZoomController],
/// [SemanticZoomListView] and [LeveledTextView]. Build content with
/// [LeveledText.parse] or [LeveledText.fromVersions]; [LeveledPrompt] helps
/// an LLM write versions that morph smoothly.
library;

export 'src/expandable_leveled_text.dart';
export 'src/leveled_prompt.dart';
export 'src/leveled_text.dart';
export 'src/leveled_text_layout.dart';
export 'src/leveled_text_loader.dart';
export 'src/leveled_text_view.dart';
export 'src/semantic_zoom_controller.dart';
export 'src/semantic_zoom_detector.dart';
export 'src/semantic_zoom_list_view.dart';
export 'src/semantic_zoom_scope.dart';
export 'src/sliver_semantic_zoom_list.dart';
