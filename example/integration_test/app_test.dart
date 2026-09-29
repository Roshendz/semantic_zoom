// Drives every tab of the example app on a real device or simulator:
//
//   flutter test integration_test/app_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:semantic_zoom/semantic_zoom.dart';
import 'package:semantic_zoom_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Set<int> selectedLevel(WidgetTester tester) => tester
      .widget<SegmentedButton<int>>(
        find.byType(SegmentedButton<int>).hitTestable().first,
      )
      .selected;

  Finder views() => find.byWidgetPredicate(
    (w) => w is LeveledTextView || w is LazyLeveledTextView,
  );

  // The level an entry shows. Heights aren't compared: they depend on the
  // fonts and window width, and a longer text may still fit on one line.
  int levelOf(WidgetTester tester, Finder view) {
    final zoom = SemanticZoomScope.of(tester.element(view));
    final w = tester.widget(view);
    final id = w is LeveledTextView
        ? w.itemId
        : (w as LazyLeveledTextView).itemId;
    return zoom.itemLevel(id!);
  }

  Future<void> pinchOut(WidgetTester tester) async {
    final list = tester.getRect(find.byType(CustomScrollView).hitTestable());
    final c = list.center;
    const axis = Offset(0.55, 0.835);
    final a = await tester.startGesture(c - axis * 30);
    final b = await tester.startGesture(c + axis * 30);
    for (var i = 1; i <= 30; i++) {
      await a.moveTo(c - axis * (30 + i * 5.0));
      await b.moveTo(c + axis * (30 + i * 5.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  testWidgets('every tab works end to end', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    // Travel: pinch, tap one day, tap a link.
    expect(find.text('Lisbon & Porto'), findsOneWidget);
    await pinchOut(tester);
    expect(selectedLevel(tester).single, greaterThan(0), reason: 'pinch');
    await tester.tap(find.text('Highlights'));
    await tester.pumpAndSettle();
    expect(selectedLevel(tester), {0});
    final day = views().hitTestable().at(1);
    expect(levelOf(tester, day), 0);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(levelOf(tester, day), 1, reason: 'tap expands one entry');
    final link = find
        .descendant(of: views().at(1), matching: find.byType(MouseRegion))
        .first;
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.textContaining('wikipedia.org/wiki/Sintra'), findsOneWidget);
    // Let the snackbar go: it floats over the level buttons.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('wikipedia.org'), findsNothing);

    // Health: grid, buttons, one card.
    await tester.tap(find.byIcon(Icons.monitor_heart));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(selectedLevel(tester), {2});
    await tester.tap(find.text('Titles'));
    await tester.pumpAndSettle();
    expect(selectedLevel(tester), {0});
    final card = views().hitTestable().first;
    await tester.tap(find.text('Mar 12 · Cardiology'));
    await tester.pumpAndSettle();
    expect(levelOf(tester, card), 1, reason: 'tap expands one card');

    // Inbox: summaries load on demand, then morph in.
    await tester.tap(find.byIcon(Icons.inbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detailed'));
    await tester.pump();
    expect(selectedLevel(tester), {2});
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      if (find.byType(LinearProgressIndicator).evaluate().isNotEmpty) break;
    }
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final loaded = tester
        .widgetList<LazyLeveledTextView>(find.byType(LazyLeveledTextView))
        .every((v) => v.loader.isLoaded);
    expect(loaded, isTrue, reason: 'every visible summary loaded');

    // Chat: newest at the bottom, one message expands upwards.
    await tester.tap(find.byIcon(Icons.forum));
    await tester.pumpAndSettle();
    final newest = views().hitTestable().first;
    final bottom = tester.getRect(newest).bottom;
    final older = views().hitTestable().at(1);
    await tester.tap(older);
    await tester.pumpAndSettle();
    expect(levelOf(tester, older), 1, reason: 'tap expands one message');
    expect(tester.getRect(newest).bottom, closeTo(bottom, 1));
    await tester.tap(find.text('Full'));
    await tester.pumpAndSettle();
    expect(selectedLevel(tester), {2});
    expect(tester.getRect(newest).bottom, closeTo(bottom, 1));
    await tester.tap(find.text('Gist'));
    await tester.pumpAndSettle();
    expect(selectedLevel(tester), {0});

    // Reads: expandable cards, including Chinese and Sinhala.
    await tester.tap(find.byIcon(Icons.article));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show more').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show more').first);
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('In Sinhala: the train to Ella'),
      find.byType(Scrollable).hitTestable().first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
