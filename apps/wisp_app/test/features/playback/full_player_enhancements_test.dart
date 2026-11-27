// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/features/navigation/router/app_routes.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/features/playback/widgets/full_player.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';

class _FakeQueueAudioHandler extends Fake implements WispAudioHandler {
  final List<GenericSong> _queue;

  _FakeQueueAudioHandler(this._queue);

  @override
  PlaybackContext? get playbackContext => null;

  @override
  List<GenericSong> get queueTracks => _queue;

  @override
  int get currentIndex => _queue.isEmpty ? -1 : 0;

  @override
  GenericSong? get currentTrack => _queue.isEmpty ? null : _queue.first;

  @override
  bool get isPlaying => false;

  @override
  bool isTrackCached(String trackId) => false;
}

class _FakeLibraryState extends Fake implements LibraryState {}

class _FakeMetadataManager extends Fake implements MetadataManager {
  @override
  bool isTrackLiked(String trackId, {String? providerId, String? source}) =>
      false;

  @override
  Future<void> ensureLikedTracksLoaded({
    String? providerId,
    String? source,
  }) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Provider.debugCheckInvalidValueType = null;
  });
  group('ClickableArtistNames', () {
    testWidgets('renders multiple comma-separated artists and optional album', (
      tester,
    ) async {
      final artists = [
        GenericSimpleArtist(
          id: 'artist-1',
          source: 'spotify',
          name: 'Daft Punk',
          thumbnailUrl: '',
        ),
        GenericSimpleArtist(
          id: 'artist-2',
          source: 'spotify',
          name: 'Julian Casablancas',
          thumbnailUrl: '',
        ),
      ];
      final album = GenericSimpleAlbum(
        id: 'album-1',
        source: 'spotify',
        title: 'Random Access Memories',
        thumbnailUrl: '',
        artists: artists,
        label: 'Columbia',
        releaseDate: DateTime(2013, 5, 17),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClickableArtistNames(
              artists: artists,
              album: album,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ),
      );

      expect(
        find.text(
          'Daft Punk, Julian Casablancas — Random Access Memories',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('invokes onBeforeNavigate and navigates when artist tapped', (
      tester,
    ) async {
      var beforeNavigateCalled = false;
      String? pushedArtistLocation;

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => Scaffold(
              body: ClickableArtistNames(
                artists: [
                  GenericSimpleArtist(
                    id: 'artist-42',
                    source: 'spotify',
                    name: 'Nujabes',
                    thumbnailUrl: '',
                  ),
                ],
                style: const TextStyle(fontSize: 16, color: Colors.white),
                onBeforeNavigate: () async {
                  beforeNavigateCalled = true;
                },
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.artist,
            builder: (context, state) {
              pushedArtistLocation = state.uri.toString();
              return const Scaffold(body: Text('Artist Page'));
            },
          ),
        ],
      );
      NavigationService.instance.initialize(router);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nujabes', findRichText: true));
      await tester.pumpAndSettle();

      expect(beforeNavigateCalled, isTrue);
      expect(pushedArtistLocation, '/artist?id=artist-42&source=spotify');
      expect(find.text('Artist Page'), findsOneWidget);
    });

    testWidgets('ellipsizes long artist names without overflowing', (
      tester,
    ) async {
      final longArtists = [
        GenericSimpleArtist(
          id: 'a1',
          source: 'spotify',
          name: 'An Extremely Long First Artist Name That Would Overflow',
          thumbnailUrl: '',
        ),
        GenericSimpleArtist(
          id: 'a2',
          source: 'spotify',
          name: 'Another Very Long Featured Artist Name',
          thumbnailUrl: '',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: ClickableArtistNames(
                artists: longArtists,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('PlayerArtworkHero', () {
    testWidgets('renders Hero when enabled and omits Hero when disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlayerArtworkHero(
                  enabled: true,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(width: 48, height: 48),
                ),
                PlayerArtworkHero(
                  enabled: false,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(width: 48, height: 48),
                ),
              ],
            ),
          ),
        ),
      );

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, PlayerHeroTags.artwork);
    });
  });

  group('FullScreenPlayer.buildMobileRoute', () {
    testWidgets('pushes non-opaque PageRoute with Hero transition', (
      tester,
    ) async {
      for (final style in [AppStyle.AppleMusic, AppStyle.Original]) {
        final baseRoute = FullScreenPlayer.buildMobileRoute(style: style);
        expect(baseRoute, isA<PageRoute<void>>());
        expect((baseRoute as PageRoute<void>).opaque, isFalse);

        final destinationRoute = PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: FullScreenPlayer.mobileTransitionDuration,
          reverseTransitionDuration:
              FullScreenPlayer.mobileReverseTransitionDuration,
          pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
            backgroundColor: Colors.black54,
            body: Center(
              child: PlayerArtworkHero(
                borderRadius: BorderRadius.circular(16),
                child: const SizedBox(
                  key: ValueKey('dest-art'),
                  width: 240,
                  height: 240,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FullScreenPlayer.buildMobileTransition(
                context,
                animation,
                secondaryAnimation,
                child,
                style: style,
              ),
        );

        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(style),
            home: Builder(
              builder: (context) => Scaffold(
                body: GestureDetector(
                  onTap: () => Navigator.of(context).push(destinationRoute),
                  child: PlayerArtworkHero(
                    borderRadius: BorderRadius.circular(10),
                    child: const SizedBox(
                      key: ValueKey('source-art'),
                      width: 48,
                      height: 48,
                      child: ColoredBox(color: Colors.red),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('source-art')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('dest-art')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('OriginalMobileUtilitiesRow', () {
    testWidgets(
      'truncates long connected device names with ellipsis and renders icon-only modes',
      (tester) async {
        const longDeviceName =
            'My Extremely Long Living Room Apple TV Audio Receiver Speaker Device Name';
        var selectedMode = OriginalMobilePlayerMode.player;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(appStyle: AppStyle.Original),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      return OriginalMobileUtilitiesRow(
                        showConnectStatus: true,
                        deviceName: longDeviceName,
                        deviceIcon: Icons.speaker,
                        onConnectTap: () {},
                        selectedMode: selectedMode,
                        onModeChanged: (mode) {
                          setState(() => selectedMode = mode);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);

        final deviceText = tester.widget<Text>(find.text(longDeviceName));
        expect(deviceText.maxLines, 1);
        expect(deviceText.overflow, TextOverflow.ellipsis);

        expect(find.text('Player'), findsNothing);
        expect(find.text('Lyrics'), findsNothing);
        expect(find.text('Queue'), findsNothing);

        expect(find.byIcon(Symbols.album), findsOneWidget);
        expect(find.byIcon(Symbols.lyrics), findsOneWidget);
        expect(find.byIcon(Symbols.queue_music), findsOneWidget);

        await tester.tap(find.byIcon(Symbols.lyrics));
        await tester.pump();
        expect(selectedMode, OriginalMobilePlayerMode.lyrics);
      },
    );
  });

  group('QueueView embedded width', () {
    testWidgets('fills full parent width when listPadding is EdgeInsets.zero', (
      tester,
    ) async {
      final track = GenericSong(
        id: 'track-1',
        source: 'spotify',
        title: 'Full Width Queue Track',
        artists: [
          GenericSimpleArtist(
            id: 'artist-1',
            source: 'spotify',
            name: 'Artist One',
            thumbnailUrl: '',
          ),
        ],
        thumbnailUrl: '',
        explicit: false,
        durationSecs: 180,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PreferencesProvider>(
              create: (_) => PreferencesProvider(),
            ),
            Provider<WispAudioHandler>.value(
              value: _FakeQueueAudioHandler([track]),
            ),
            Provider<LibraryState>.value(value: _FakeLibraryState()),
            Provider<MetadataManager>.value(value: _FakeMetadataManager()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(appStyle: AppStyle.Original),
            home: const Scaffold(
              body: SizedBox(
                width: 340,
                height: 400,
                child: QueueView(
                  contentOnly: true,
                  hideHeader: true,
                  backgroundColor: Colors.transparent,
                  listPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(QueueView)).width, 340);
      // TrackRow sits inside the current-track 1px border (340 - 2 = 338).
      expect(tester.getSize(find.byType(TrackRow)).width, 338);
      expect(tester.takeException(), isNull);
    });
  });

  group('Compact Lyrics/Queue Hero pop & Animated Canvas persistence', () {
    testWidgets(
      'PlayerArtworkHero inside compact AnimatedContainer flies back to player bar on pop',
      (tester) async {
        final route = PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: FullScreenPlayer.mobileTransitionDuration,
          reverseTransitionDuration:
              FullScreenPlayer.mobileReverseTransitionDuration,
          pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
            backgroundColor: Colors.black54,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      height: 64,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          width: 64,
                          height: 64,
                          child: PlayerArtworkHero(
                            borderRadius: BorderRadius.circular(10),
                            child: const SizedBox.expand(
                              key: ValueKey('compact-dest-art'),
                              child: ColoredBox(color: Colors.blue),
                            ),
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FullScreenPlayer.buildMobileTransition(
                context,
                animation,
                secondaryAnimation,
                child,
                style: AppStyle.AppleMusic,
              ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Align(
                  alignment: Alignment.bottomLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(route),
                    child: PlayerArtworkHero(
                      borderRadius: BorderRadius.circular(10),
                      child: const SizedBox(
                        key: ValueKey('playerbar-source-art'),
                        width: 46,
                        height: 46,
                        child: ColoredBox(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('playerbar-source-art')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('compact-dest-art')), findsOneWidget);

        await tester.tap(find.text('Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(find.byType(Hero), findsWidgets);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('playerbar-source-art')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    test('PreferencesProvider persists animatedCanvasEnabled across instances', () async {
      final prefs1 = PreferencesProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await prefs1.setAnimatedCanvasEnabled(true);
      expect(prefs1.animatedCanvasEnabled, isTrue);

      await prefs1.setAnimatedCanvasEnabled(false);
      expect(prefs1.animatedCanvasEnabled, isFalse);

      final prefs2 = PreferencesProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(prefs2.animatedCanvasEnabled, isFalse);
    });
  });
}
