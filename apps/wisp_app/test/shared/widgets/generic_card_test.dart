// Copyright © 2026 wizeshi

import 'dart:ui' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/cards/generic_card.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

void main() {
  group('GenericCard play button ink isolation', () {
    testWidgets('press and hold on play button does not ripple the card', (tester) async {
      var cardTapped = false;
      var playPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.AppleMusic),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: GenericCard(
                  title: 'Test Album',
                  subtitle: 'Test Artist',
                  artwork: const SizedBox.expand(),
                  onTap: () => cardTapped = true,
                  onPlay: () => playPressed = true,
                ),
              ),
            ),
          ),
        ),
      );

      // Trigger hover over the card to reveal the play button
      final mouseLocation = tester.getCenter(find.byType(GenericCard));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(mouseLocation);
      await tester.pumpAndSettle();

      // Find the GenericIconButton (the play button)
      final playButtonFinder = find.byType(GenericIconButton);
      expect(playButtonFinder, findsOneWidget);

      // Move mouse over the play button and press down
      final playCenter = tester.getCenter(playButtonFinder);
      await gesture.moveTo(playCenter);
      await tester.pumpAndSettle();
      await gesture.down(playCenter);
      await tester.pump(const Duration(milliseconds: 300));

      final RenderObject inkFeatures = tester.allRenderObjects.firstWhere(
        (RenderObject object) => object.runtimeType.toString() == '_RenderInkFeatures',
      );
      expect(
        inkFeatures,
        isNot(paints..circle()),
      );

      // Release the play button
      await gesture.up();
      await tester.pumpAndSettle();

      expect(playPressed, isTrue);
      expect(cardTapped, isFalse);
    });

    testWidgets('hovering over generic card shows click cursor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: GenericCard(
                  title: 'Test Album',
                  subtitle: 'Test Artist',
                  artwork: Container(color: Colors.blue),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final cardFinder = find.byType(GenericCard);
      final mouseLocation = tester.getCenter(cardFinder);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(mouseLocation);
      await tester.pumpAndSettle();

      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    });

    testWidgets('press and hold on card triggers ripple on card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(appStyle: AppStyle.Spotify),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: GenericCard(
                  title: 'Test Album',
                  subtitle: 'Test Artist',
                  artwork: Container(color: Colors.blue),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final cardFinder = find.byType(GenericCard);
      final cardCenter = tester.getCenter(cardFinder);
      final gesture = await tester.startGesture(cardCenter);
      await tester.pump(const Duration(milliseconds: 300));

      final allInk = tester.allRenderObjects
          .where((obj) => obj.runtimeType.toString() == '_RenderInkFeatures')
          .toList();
      expect(allInk, isNotEmpty);
      // The ripple should be painted on the card's Material above the artwork
      expect(
        allInk.any((ink) {
          try {
            expect(ink, paints..rect());
            return true;
          } catch (_) {
            return false;
          }
        }),
        isTrue,
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
