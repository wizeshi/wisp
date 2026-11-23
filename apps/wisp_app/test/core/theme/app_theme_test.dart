// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/core/utils/cover_art_kmeans.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert.dart';
import 'package:wisp/shared/widgets/cards/generic_card.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';

class _FakeQueueAudioHandler extends Fake implements WispAudioHandler {
  @override
  PlaybackContext? get playbackContext => null;

  @override
  List<GenericSong> get queueTracks => const <GenericSong>[];

  @override
  int get currentIndex => -1;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Provider.debugCheckInvalidValueType = null;
  });

  group('AppTheme & WispColors', () {
    test('dark and light themes populate WispColors for every AppStyle', () {
      for (final style in AppStyle.values) {
        final dark = AppTheme.dark(appStyle: style);
        final darkColors = dark.extension<WispColors>()!;
        expect(dark.brightness, Brightness.dark);
        expect(darkColors.brightness, Brightness.dark);
        expect(darkColors.isDark, isTrue);
        expect(dark.scaffoldBackgroundColor, darkColors.canvas);
        expect(dark.canvasColor, darkColors.canvas);
        expect(dark.cardColor, darkColors.surface);
        expect(dark.dialogTheme.backgroundColor, darkColors.surfaceElevated);
        expect(dark.colorScheme.surface, darkColors.canvas);
        expect(dark.colorScheme.onSurface, darkColors.textPrimary);
        expect(dark.extension<WispStyleTokens>()?.style, style);

        final light = AppTheme.light(appStyle: style);
        final lightColors = light.extension<WispColors>()!;
        expect(light.brightness, Brightness.light);
        expect(lightColors.brightness, Brightness.light);
        expect(lightColors.isDark, isFalse);
        expect(light.scaffoldBackgroundColor, lightColors.canvas);
        expect(light.canvasColor, lightColors.canvas);
        expect(light.cardColor, lightColors.surface);
        expect(light.dialogTheme.backgroundColor, lightColors.surfaceElevated);
        expect(light.colorScheme.surface, lightColors.canvas);
        expect(light.colorScheme.onSurface, lightColors.textPrimary);
        expect(light.extension<WispStyleTokens>()?.style, style);

        // Light mode maintains distinct shell depth panes & legible dark ink.
        expect(lightColors.canvas, const Color(0xFFFFFFFF));
        expect(lightColors.chrome, isNot(lightColors.canvas));
        expect(lightColors.sidebar, isNot(lightColors.canvas));
        expect(lightColors.playerBar, isNot(lightColors.canvas));
        expect(lightColors.textPrimary.computeLuminance(), lessThan(0.1));
        expect(
          lightColors.textSecondary.computeLuminance(),
          greaterThan(lightColors.textPrimary.computeLuminance()),
        );
      }
    });

    test('fromBrightness matches dark and light factories', () {
      for (final style in AppStyle.values) {
        final fromDark = AppTheme.fromBrightness(
          Brightness.dark,
          appStyle: style,
        );
        final explicitDark = AppTheme.dark(appStyle: style);
        expect(
          fromDark.extension<WispColors>()!.canvas,
          explicitDark.extension<WispColors>()!.canvas,
        );

        final fromLight = AppTheme.fromBrightness(
          Brightness.light,
          appStyle: style,
        );
        final explicitLight = AppTheme.light(appStyle: style);
        expect(
          fromLight.extension<WispColors>()!.canvas,
          explicitLight.extension<WispColors>()!.canvas,
        );
      }
    });

    test('paletteOverride keeps custom accent while harmonizing canvas', () {
      const override = ColorScheme.light(
        primary: Color(0xFF8B5CF6),
        secondary: Color(0xFFEC4899),
      );
      final themed = AppTheme.light(
        paletteOverride: override,
        appStyle: AppStyle.Original,
      );
      final colors = themed.extension<WispColors>()!;

      expect(themed.colorScheme.primary, const Color(0xFF8B5CF6));
      expect(themed.colorScheme.secondary, const Color(0xFFEC4899));
      expect(themed.colorScheme.surface, colors.canvas);
      expect(themed.colorScheme.onSurface, colors.textPrimary);
    });

    test('WispColors copyWith, lerp, onColor, tintedHeader, and tintedSubtle work', () {
      final dark = WispColors.fromTheme(Brightness.dark, AppStyle.Original);
      final light = WispColors.fromTheme(Brightness.light, AppStyle.Original);

      final copied = light.copyWith(canvas: const Color(0xFFFAFAFC)) as WispColors;
      expect(copied.canvas, const Color(0xFFFAFAFC));
      expect(copied.sidebar, light.sidebar);

      expect((dark.lerp(light, 0.0) as WispColors).canvas, dark.canvas);
      expect((dark.lerp(light, 1.0) as WispColors).canvas, light.canvas);
      final mid = dark.lerp(light, 0.5) as WispColors;
      expect(mid.canvas, isNot(dark.canvas));
      expect(mid.canvas, isNot(light.canvas));
      expect(dark.lerp(null, 0.5), dark);

      expect(light.onColor(Colors.black), Colors.white);
      expect(light.onColor(Colors.white), const Color(0xFF141416));

      const accent = Color(0xFF1DB954);
      expect(dark.tintedHeader(accent), accent);
      final lightHeader = light.tintedHeader(accent);
      expect(lightHeader.computeLuminance(), greaterThan(0.5));
      final lightSubtle = light.tintedSubtle(accent);
      expect(lightSubtle.computeLuminance(), greaterThan(lightHeader.computeLuminance()));
    });

    testWidgets('context.colors safely falls back without ThemeExtension', (tester) async {
      late WispColors lightFallback;
      late WispColors darkFallback;

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('fallback-light'),
          theme: ThemeData.light(),
          home: Builder(
            builder: (context) {
              lightFallback = context.colors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(lightFallback.isDark, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('fallback-dark'),
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              darkFallback = context.colors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(darkFallback.isDark, isTrue);
    });
  });

  group('CoverArtKMeans', () {
    test('buildColorScheme tunes accents per brightness for readable contrast', () {
      const brightPalette = CoverArtPaletteColors(
        primary: Color(0xFFFFFF00),
        secondary: Color(0xFF00FFFF),
      );

      final lightScheme = CoverArtKMeans.buildColorScheme(
        brightPalette,
        brightness: Brightness.light,
      );
      expect(lightScheme.brightness, Brightness.light);
      expect(lightScheme.primary.computeLuminance(), lessThanOrEqualTo(0.35));
      expect(lightScheme.secondary.computeLuminance(), lessThanOrEqualTo(0.35));

      final darkScheme = CoverArtKMeans.buildColorScheme(
        brightPalette,
        brightness: Brightness.dark,
      );
      expect(darkScheme.brightness, Brightness.dark);
    });
  });

  group('PreferencesProvider themeMode', () {
    test('defaults to ThemeMode.dark and persists changes', () async {
      final prefs = PreferencesProvider();
      await testerPumpWait();

      expect(prefs.themeMode, ThemeMode.dark);

      await prefs.setThemeMode(ThemeMode.light);
      expect(prefs.themeMode, ThemeMode.light);

      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('preferred_theme_mode'), 'light');

      await prefs.setThemeMode(ThemeMode.system);
      expect(prefs.themeMode, ThemeMode.system);
      expect(stored.getString('preferred_theme_mode'), 'system');
    });

    test('loads persisted and rejects unknown theme modes safely', () async {
      SharedPreferences.setMockInitialValues({'preferred_theme_mode': 'light'});
      final lightPrefs = PreferencesProvider();
      await testerPumpWait();
      expect(lightPrefs.themeMode, ThemeMode.light);

      SharedPreferences.setMockInitialValues({'preferred_theme_mode': 'system'});
      final systemPrefs = PreferencesProvider();
      await testerPumpWait();
      expect(systemPrefs.themeMode, ThemeMode.system);

      SharedPreferences.setMockInitialValues({'preferred_theme_mode': 'bogus'});
      final fallbackPrefs = PreferencesProvider();
      await testerPumpWait();
      expect(fallbackPrefs.themeMode, ThemeMode.dark);
    });
  });

  group('Themed widgets across Light and Dark modes', () {
    testWidgets('GenericCard and GenericRow render in both Light and Dark themes', (tester) async {
      for (final theme in [
        AppTheme.light(appStyle: AppStyle.Original),
        AppTheme.dark(appStyle: AppStyle.Original),
      ]) {
        final expectedColors = theme.extension<WispColors>()!;

        await tester.pumpWidget(
          ChangeNotifierProvider<PreferencesProvider>(
            create: (_) => PreferencesProvider(),
            child: MaterialApp(
              key: ValueKey('card-row-${theme.brightness.name}'),
              theme: theme,
              home: Scaffold(
                body: Column(
                  children: [
                    SizedBox(
                      width: 180,
                      height: 240,
                      child: GenericCard(
                        title: 'Card Title',
                        subtitle: 'Card Subtitle',
                        artwork: const SizedBox.expand(),
                        onTap: () {},
                      ),
                    ),
                    GenericRow(
                      title: 'Row Title',
                      subtitle: 'Row Subtitle',
                      artwork: const SizedBox.expand(),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Card Title'), findsOneWidget);
        expect(find.text('Row Title'), findsOneWidget);

        final titleText = tester.widget<Text>(find.text('Row Title'));
        expect(titleText.style?.color, expectedColors.textPrimary);
      }
    });

    testWidgets('WispAlert adapts container background to theme brightness', (tester) async {
      for (final theme in [
        AppTheme.light(appStyle: AppStyle.Original),
        AppTheme.dark(appStyle: AppStyle.Original),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('alert-${theme.brightness.name}'),
            theme: theme,
            home: const Scaffold(
              body: WispAlert(
                title: 'Heads up',
                message: 'Theme alert message',
                severity: AlertSeverity.info,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(WispAlert),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration as BoxDecoration;
        expect(
          decoration.color,
          AlertSeverity.info.backgroundColorFor(theme.brightness),
        );
        expect(find.text('Theme alert message'), findsOneWidget);
      }
    });

    testWidgets('QueueView uses transparent embedded surface by default in both themes', (tester) async {
      for (final theme in [
        AppTheme.light(appStyle: AppStyle.Original),
        AppTheme.dark(appStyle: AppStyle.Original),
      ]) {
        final expectedColors = theme.extension<WispColors>()!;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PreferencesProvider>(
                create: (_) => PreferencesProvider(),
              ),
              Provider<WispAudioHandler>.value(value: _FakeQueueAudioHandler()),
            ],
            child: MaterialApp(
              key: ValueKey('queue-${theme.brightness.name}'),
              theme: theme,
              home: const Scaffold(body: QueueView()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Queue'), findsOneWidget);
        expect(find.text('queue is empty'), findsOneWidget);

        final headerTitle = tester.widget<Text>(find.text('Queue'));
        expect(headerTitle.style?.color, expectedColors.textPrimary);
      }
    });
  });
}

Future<void> testerPumpWait() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}
