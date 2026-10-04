// Copyright © 2026 wizeshi

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/buttons/generic_button.dart';

void main() {
  group('GenericIconButton', () {
    testWidgets('renders CupertinoButton when style is AppleMusic', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: GenericIconButton(
              style: AppStyle.AppleMusic,
              icon: const Icon(Icons.play_arrow),
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CupertinoButton), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('renders IconButton when style is Spotify', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: GenericIconButton(
              style: AppStyle.Spotify,
              icon: const Icon(Icons.play_arrow),
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
    });

    testWidgets('infers AppleMusic from ambient theme when style is omitted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: GenericIconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CupertinoButton), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('infers Spotify from ambient theme when style is omitted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: GenericIconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
    });

    testWidgets('triggers onPressed when clicked', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: GenericIconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GenericIconButton));
      expect(tapped, isTrue);
    });
  });

  group('GenericFilledButton', () {
    testWidgets('renders CupertinoButton when style is AppleMusic', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: GenericFilledButton(
              style: AppStyle.AppleMusic,
              onPressed: () {},
              child: const Text('Play'),
            ),
          ),
        ),
      );

      expect(find.byType(CupertinoButton), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('renders FilledButton when style is Spotify', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: GenericFilledButton(
              style: AppStyle.Spotify,
              onPressed: () {},
              child: const Text('Play'),
            ),
          ),
        ),
      );

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
    });

    testWidgets('renders icon and label properly with .icon constructor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: GenericFilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Play'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(CupertinoButton), findsOneWidget);
    });
  });
}
