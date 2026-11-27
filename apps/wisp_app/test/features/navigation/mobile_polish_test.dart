// Copyright © 2026 wizeshi

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/data/sources/providers/provider_package_model.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/features/navigation/views/list/mobile/mobile_sort_header.dart';
import 'package:wisp/features/navigation/views/list/view.dart'
    show ListSortMethod, SharedListType;
import 'package:wisp/features/playback/widgets/player_bar/components/mobile_swipe_track_switcher.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/settings/views/providers_marketplace_view.dart';
import 'package:wisp/shared/widgets/display/provider_icon.dart';
import 'package:wisp/shared/widgets/menus/adaptive_context_menu.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';

class _FakeLibraryFolderState extends Fake implements LibraryFolderState {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void dispose() {}

  @override
  List<PlaylistFolder> get folders => const [];

  @override
  String? folderIdForPlaylist(String playlistId) => null;
}

class _FakeLibraryState extends Fake implements LibraryState {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void dispose() {}

  @override
  bool isAlbumSaved(String albumId) => false;

  @override
  bool isArtistFollowed(String artistId) => false;
}

class _FakeMetadataManager extends Fake implements MetadataManager {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void dispose() {}

  @override
  List<MetadataProvider> get allProviders => const [];
}

GenericSong _makeSong(String id, String title, String artist) {
  return GenericSong(
    id: id,
    source: 'spotify',
    title: title,
    artists: [
      GenericSimpleArtist(
        id: 'artist-$id',
        source: 'spotify',
        name: artist,
        thumbnailUrl: '',
      ),
    ],
    thumbnailUrl: '',
    explicit: false,
    durationSecs: 185,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Provider.debugCheckInvalidValueType = null;
  });

  group('Mobile Context Menu', () {
    testWidgets('scrolls long lists and navigates in-sheet submenus', (
      tester,
    ) async {
      debugForceMobileContextMenu = true;
      addTearDown(() => debugForceMobileContextMenu = null);

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var selectedChild = false;
      final actions = [
        ContextMenuAction(
          id: 'submenu-parent',
          label: 'Submenu Parent',
          icon: Icons.folder,
          children: [
            for (var i = 0; i < 16; i++)
              ContextMenuAction(
                id: 'child-$i',
                label: 'Child Item $i',
                icon: Icons.music_note,
                onSelected: (_) {
                  if (i == 15) selectedChild = true;
                },
              ),
          ],
        ),
        for (var i = 1; i < 20; i++)
          ContextMenuAction(
            id: 'item-$i',
            label: 'Action Item $i',
            icon: Icons.star_outline,
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAdaptiveContextMenu(
                    context: context,
                    actions: actions,
                    mobileHeaderBuilder: (_) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text('Header Preview'),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open Menu'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Header Preview'), findsOneWidget);

      // Scroll down to reveal bottom item on 360x640 sheet without overflow.
      await tester.scrollUntilVisible(
        find.text('Action Item 19'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Action Item 19'), findsOneWidget);

      // Scroll back to top and open submenu.
      await tester.scrollUntilVisible(
        find.text('Submenu Parent'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Submenu Parent'));
      await tester.pumpAndSettle();

      expect(find.text('Submenu Parent'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Child Item 15'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Child Item 15'));
      await tester.pumpAndSettle();

      expect(selectedChild, isTrue);
    });

    testWidgets(
      'playlist, album, and artist menus render mobile preview headers with ProviderIcon',
      (tester) async {
        debugForceMobileContextMenu = true;
        addTearDown(() => debugForceMobileContextMenu = null);

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final prefs = PreferencesProvider();
        final owner = GenericSimpleUser(
          id: 'u1',
          source: 'qobuz',
          displayName: 'Alex',
        );
        final artist = GenericSimpleArtist(
          id: 'ar1',
          source: 'spotify',
          name: 'Daft Punk',
          thumbnailUrl: '',
        );
        final playlist = GenericPlaylist(
          id: 'pl1',
          source: 'qobuz',
          title: 'Road Trip Mix',
          thumbnailUrl: '',
          author: owner,
          songs: null,
          durationSecs: 1200,
          total: 12,
        );
        final album = GenericAlbum(
          id: 'al1',
          source: 'spotify',
          title: 'Discovery',
          thumbnailUrl: '',
          artists: [artist],
          label: 'Virgin',
          releaseDate: DateTime(2001, 3, 12),
          explicit: false,
          durationSecs: 3600,
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PreferencesProvider>.value(value: prefs),
              ChangeNotifierProvider<LibraryFolderState>(
                create: (_) => _FakeLibraryFolderState(),
              ),
              ChangeNotifierProvider<LibraryState>(
                create: (_) => _FakeLibraryState(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      TextButton(
                        onPressed: () => EntityContextMenus.showPlaylistMenu(
                          context,
                          playlist: playlist,
                        ),
                        child: const Text('Playlist Menu'),
                      ),
                      TextButton(
                        onPressed: () => EntityContextMenus.showAlbumMenu(
                          context,
                          album: album,
                        ),
                        child: const Text('Album Menu'),
                      ),
                      TextButton(
                        onPressed: () => EntityContextMenus.showArtistMenu(
                          context,
                          artist: artist,
                        ),
                        child: const Text('Artist Menu'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Playlist preview header
        await tester.tap(find.text('Playlist Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Road Trip Mix'), findsOneWidget);
        expect(find.text('Alex • 12 songs'), findsOneWidget);
        expect(find.byType(ProviderIcon), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Album preview header
        await tester.tap(find.text('Album Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Discovery'), findsOneWidget);
        expect(find.text('Daft Punk • Album • 2001'), findsOneWidget);
        expect(find.byType(ProviderIcon), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Artist preview header
        await tester.tap(find.text('Artist Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Daft Punk'), findsOneWidget);
        expect(find.text('Artist'), findsOneWidget);
        expect(find.byType(ClipOval), findsOneWidget);
        expect(find.byType(ProviderIcon), findsOneWidget);
      },
    );
  });

  group('Mobile Playlist Sort Mode Headers', () {
    testWidgets('renders all 3 styles cleanly and dispatches onSort', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final style in AppStyle.values) {
        ListSortMethod? selected;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('sort_${style.name}'),
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileListSortHeader(
                type: SharedListType.playlist,
                sortMethod: ListSortMethod.title,
                sortAscending: true,
                style: style,
                onSort: (method) => selected = method,
              ),
            ),
          ),
        );

        expect(find.text('Custom order'), findsNothing);
        expect(find.text('Track order'), findsNothing);
        expect(find.byType(Divider), findsNothing);
        expect(find.byIcon(Icons.sort), findsNothing);
        expect(find.byIcon(CupertinoIcons.arrow_up_arrow_down), findsNothing);
        expect(find.text('Title'), findsOneWidget);
        expect(find.text('Artist'), findsOneWidget);
        expect(find.text('Album'), findsOneWidget);
        expect(
          find.byIcon(
            style == AppStyle.AppleMusic
                ? CupertinoIcons.arrow_up
                : Icons.arrow_upward_rounded,
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Artist'));
        await tester.pump();
        await tester.tap(find.text('Artist'));
        await tester.pump();
        expect(selected, ListSortMethod.author);
      }

      // Unselected / custom order state when sortMethod is ListSortMethod.position
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MobileListSortHeader(
              type: SharedListType.album,
              sortMethod: ListSortMethod.position,
              sortAscending: true,
              style: AppStyle.Spotify,
              onSort: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Custom order'), findsNothing);
      expect(find.text('Track order'), findsNothing);
      expect(find.text('Album'), findsNothing);
      expect(find.text('Date added'), findsNothing);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });
  });

  group('Mobile Marketplace Appearance', () {
    testWidgets(
      'renders filter bar, updates banner, cards, and priority dialog cleanly at 360px',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final prefs = PreferencesProvider();
        final packages = [
          const ProviderPackage(
            id: 'spotify',
            name: 'Spotify Metadata',
            version: '1.2.0',
            type: 'metadata',
            author: 'wisp',
            description: 'Official Spotify metadata integration.',
            priority: 100,
            path: 'metadata/spotify',
            isInstalled: true,
            installedVersion: '1.0.0',
          ),
          const ProviderPackage(
            id: 'qobuz',
            name: 'Qobuz Lossless Audio',
            version: '2.0.0',
            type: 'audio',
            author: 'wisp',
            description: 'Hi-Res FLAC playback provider.',
            priority: 90,
            path: 'audio/qobuz',
            isInstalled: true,
            installedVersion: '2.0.0',
          ),
          const ProviderPackage(
            id: 'lrclib',
            name: 'LRCLIB Synced Lyrics',
            version: '1.0.5',
            type: 'lyrics',
            author: 'community',
            description: 'Synced and unsynced lyrics lookup.',
            supportedSyncModes: ['line', 'unsynced'],
            priority: 80,
            path: 'lyrics/lrclib',
            isInstalled: false,
          ),
        ];

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PreferencesProvider>.value(value: prefs),
              ChangeNotifierProvider<MetadataManager>(
                create: (_) => _FakeMetadataManager(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: ProvidersMarketplaceView(initialPackages: packages),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('1 provider update available'), findsOneWidget);
        expect(find.text('Update All'), findsOneWidget);
        expect(find.text('Spotify Metadata'), findsOneWidget);
        expect(find.text('Qobuz Lossless Audio'), findsOneWidget);

        // Open priority dialog and verify compact mobile tabs without overflow.
        await tester.tap(find.byTooltip('Provider Priority Order'));
        await tester.pump(const Duration(milliseconds: 250));

        final dialogFinder = find.byType(Dialog);
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('Provider Priority & Fallbacks'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialogFinder, matching: find.text('Metadata')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialogFinder, matching: find.text('Audio')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialogFinder, matching: find.text('Lyrics')),
          findsOneWidget,
        );
      },
    );
  });

  group('Mobile Player Bar Swipe Gesture', () {
    testWidgets(
      'triggers skip next/previous with preview, ignores partial drags, and enforces boundary resistance',
      (tester) async {
        final prev = _makeSong('1', 'Previous Track', 'Artist A');
        final current = _makeSong('2', 'Current Track', 'Artist B');
        final next = _makeSong('3', 'Next Track', 'Artist C');

        var skipNextCount = 0;
        var skipPrevCount = 0;

        Future<void> pumpBar({GenericSong? nextTrack}) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 340,
                    height: 60,
                    child: MobileSwipeablePlayerBar(
                      currentTrack: current,
                      previousTrack: prev,
                      nextTrack: nextTrack,
                      onSkipNext: () => skipNextCount++,
                      onSkipPrevious: () => skipPrevCount++,
                      builder: (context, swipe) {
                        return Container(
                          color: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: MobileSwipeTrackInfoStack(
                            swipe: swipe,
                            accentColor: Colors.greenAccent,
                            secondaryColor: Colors.white70,
                            currentChild: Text(current.title),
                            previewChild: swipe.previewTrack == null
                                ? null
                                : Text(swipe.previewTrack!.title),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        await pumpBar(nextTrack: next);

        // Medium drag below higher threshold should not skip and should snap back cleanly.
        await tester.drag(
          find.byType(MobileSwipeablePlayerBar),
          const Offset(-55, 0),
        );
        await tester.pumpAndSettle();
        expect(skipNextCount, 0);

        // Swipe left past threshold -> skips next.
        await tester.drag(
          find.byType(MobileSwipeablePlayerBar),
          const Offset(-120, 0),
        );
        await tester.pumpAndSettle();
        expect(skipNextCount, 1);

        // Swipe right past threshold -> skips previous.
        await tester.drag(
          find.byType(MobileSwipeablePlayerBar),
          const Offset(120, 0),
        );
        await tester.pumpAndSettle();
        expect(skipPrevCount, 1);

        // With nextTrack == null, dragging left applies resistance and does not skip.
        await pumpBar(nextTrack: null);
        await tester.drag(
          find.byType(MobileSwipeablePlayerBar),
          const Offset(-120, 0),
        );
        await tester.pumpAndSettle();
        expect(skipNextCount, 1);
      },
    );

    testWidgets(
      'allows context.select on builder context without Provider build assertion',
      (tester) async {
        final prefs = PreferencesProvider();
        final current = _makeSong('1', 'Current', 'Artist');
        final next = _makeSong('2', 'Next', 'Artist');

        await tester.pumpWidget(
          ChangeNotifierProvider<PreferencesProvider>.value(
            value: prefs,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 340,
                    height: 60,
                    child: MobileSwipeablePlayerBar(
                      currentTrack: current,
                      previousTrack: null,
                      nextTrack: next,
                      onSkipNext: () {},
                      onSkipPrevious: () {},
                      builder: (builderContext, swipe) {
                        final style = builderContext
                            .select<PreferencesProvider, AppStyle>(
                              (p) => p.style,
                            );
                        return Text('${current.title} (${style.name})');
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.textContaining('Current ('), findsOneWidget);
        await tester.drag(
          find.byType(MobileSwipeablePlayerBar),
          const Offset(-40, 0),
        );
        await tester.pumpAndSettle();
      },
    );
  });
}
