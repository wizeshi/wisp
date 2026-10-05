// Copyright © 2026 wizeshi

import 'dart:ui' show PointerDeviceKind;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

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

    testWidgets('Cupertino button inside InkWell does not trigger parent InkWell', (tester) async {
      var parentTapped = false;
      var childTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: Material(
              child: InkWell(
                onTap: () => parentTapped = true,
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Center(
                    child: GenericIconButton(
                      style: AppStyle.AppleMusic,
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () => childTapped = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GenericIconButton));
      expect(childTapped, isTrue);
      expect(parentTapped, isFalse);
    });

    testWidgets('Cupertino icon button has comfortable minimum size by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: GenericIconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {},
            ),
          ),
        ),
      );

      final button = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
      expect(button.minimumSize, const Size(40, 40));
      expect(button.padding, const EdgeInsets.all(8));
    });

    testWidgets('applies hoverColor in Spotify mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: GenericIconButton(
              icon: const Icon(Icons.close),
              onPressed: () {},
              hoverColor: Colors.red,
            ),
          ),
        ),
      );

      final iconBtn = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconBtn.hoverColor, Colors.red);
      final overlay = iconBtn.style?.overlayColor?.resolve({WidgetState.hovered});
      expect(overlay, Colors.red);
    });

    testWidgets('applies hoverColor in AppleMusic mode on hover', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: GenericIconButton(
              icon: const Icon(Icons.close),
              onPressed: () {},
              hoverColor: Colors.red,
            ),
          ),
        ),
      );

      var cupertinoBtn = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
      expect(cupertinoBtn.color, isNull);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(GenericIconButton)));
      await tester.pumpAndSettle();

      cupertinoBtn = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
      expect(cupertinoBtn.color, Colors.red);

      await gesture.moveTo(const Offset(500, 500));
      await tester.pumpAndSettle();

      cupertinoBtn = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
      expect(cupertinoBtn.color, isNull);
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

  group('GenericButton and convenience classes', () {
    testWidgets('renders TextButton and CupertinoButton appropriately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: GenericTextButton(
              onPressed: () {},
              child: const Text('TextBtn'),
            ),
          ),
        ),
      );

      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
    });

    testWidgets('renders OutlinedButton and CupertinoButton appropriately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: GenericOutlinedButton(
              onPressed: () {},
              child: const Text('OutlinedBtn'),
            ),
          ),
        ),
      );

      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
    });

    testWidgets('renders ElevatedButton and CupertinoButton appropriately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: GenericElevatedButton(
              onPressed: () {},
              child: const Text('ElevatedBtn'),
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
    });
  });
}
