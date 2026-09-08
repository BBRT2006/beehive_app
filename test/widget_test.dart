// Basic widget test adapted to this project.
// Ensures the main app widget builds without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beehive_app/main.dart';

void main() {
  testWidgets('App builds and shows auth screen', (WidgetTester tester) async {
    // Build the BeehiveApp and trigger a frame.
    await tester.pumpWidget(const BeehiveApp());

    // The app should build; expect the top-level BeehiveApp to be present.
    expect(find.byType(BeehiveApp), findsOneWidget);

    // Auth screen shows a title — either Greek or English depending on default language.
    // Check for presence of the hive icon used in the auth card.
    expect(find.byIcon(Icons.hive), findsOneWidget);
  });
}
