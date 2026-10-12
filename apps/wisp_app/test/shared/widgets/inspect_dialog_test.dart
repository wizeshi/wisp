// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/shared/widgets/menus/inspect_dialog.dart';

void main() {
  testWidgets('InspectDialog renders flat and nested data correctly', (tester) async {
    final testData = <String, dynamic>{
      'title': 'Test Song',
      'duration': 210,
      'explicit': false,
      'album': {
        'title': 'Test Album',
        'year': 2026,
      },
      'artists': [
        {'name': 'Artist 1'},
        {'name': 'Artist 2'},
      ],
      'tags': ['pop', 'rock'],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectDialog(
            data: testData,
            title: 'Inspect Track',
          ),
        ),
      ),
    );

    // Header title
    expect(find.text('Inspect Track'), findsOneWidget);

    // Top-level fields
    expect(find.text('title'), findsOneWidget);
    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('duration'), findsOneWidget);
    expect(find.text('210'), findsOneWidget);
    expect(find.text('explicit'), findsOneWidget);
    expect(find.text('false'), findsOneWidget);

    // Primitive list is rendered inline
    expect(find.text('tags'), findsOneWidget);
    expect(find.text('[pop, rock]'), findsOneWidget);

    // Subsections headers are visible
    expect(find.text('album'), findsOneWidget);
    expect(find.text('{2}'), findsOneWidget);
    expect(find.text('artists'), findsOneWidget);
    expect(find.text('[2]'), findsOneWidget);

    // Before expanding, nested contents are not rendered
    expect(find.text('Test Album'), findsNothing);

    // Expand the album subsection
    await tester.tap(find.text('album'));
    await tester.pumpAndSettle();

    // Now nested fields are visible
    expect(find.text('Test Album'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);

    // Expand artists list subsection
    await tester.tap(find.text('artists'));
    await tester.pumpAndSettle();

    expect(find.text('[0]'), findsOneWidget);
    expect(find.text('[1]'), findsOneWidget);

    // Expand artist [0]
    await tester.tap(find.text('[0]'));
    await tester.pumpAndSettle();

    expect(find.text('Artist 1'), findsOneWidget);

    // Copy all button exists
    expect(find.text('Copy all as JSON'), findsOneWidget);
  });
}

