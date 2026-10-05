// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';

void main() {
  group('GenericRow double tap', () {
    testWidgets('single tap triggers onTap, double tap triggers onDoubleTap / onPlay', (tester) async {
      var tapped = false;
      var played = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesProvider>(
          create: (_) => PreferencesProvider(),
          child: MaterialApp(
            theme: AppTheme.dark(appStyle: AppStyle.Spotify),
            home: Scaffold(
              body: GenericRow(
                title: 'Test Playlist',
                subtitle: 'Spotify',
                artwork: const SizedBox.expand(),
                onTap: () => tapped = true,
                onPlay: () => played = true,
              ),
            ),
          ),
        ),
      );

      // Single tap
      await tester.tap(find.byType(GenericRow));
      await tester.pump();

      expect(tapped, isTrue);
      expect(played, isFalse);

      tapped = false;

      // Double tap (second tap within 350ms)
      await tester.tap(find.byType(GenericRow));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(GenericRow));
      await tester.pump();

      expect(played, isTrue);
    });
  });
}
