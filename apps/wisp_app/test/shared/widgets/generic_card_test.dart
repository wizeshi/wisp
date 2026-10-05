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
        isNot(paints..rect(rect: const Rect.fromLTRB(0.0, 0.0, 200.0, 300.0))),
      );

      // Release the play button
      await gesture.up();
      await tester.pumpAndSettle();

      expect(playPressed, isTrue);
      expect(cardTapped, isFalse);
    });
  });
}
