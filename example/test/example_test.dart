import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantic_zoom_example/main.dart';

void main() {
  testWidgets('all three demos build, expand and change level', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Lisbon & Porto'), findsOneWidget);

    // Travel: global level via the selector, then one entry via tap.
    await tester.tap(find.text('Full'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();

    // Health: tap one visit, then the whole list.
    await tester.tap(find.byIcon(Icons.monitor_heart));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mar 12 · Cardiology'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    // Inbox: rephrased summaries at every level.
    await tester.tap(find.byIcon(Icons.inbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detailed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subject'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
