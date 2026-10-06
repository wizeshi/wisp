// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

class _FakeAudioHandler extends Fake implements WispAudioHandler {
  final GenericSong? _currentTrack;
  final PlaybackContext? _playbackContext;
  final bool _isPlaying;

  _FakeAudioHandler({
    GenericSong? currentTrack,
    PlaybackContext? playbackContext,
    bool isPlaying = false,
  })  : _currentTrack = currentTrack,
        _playbackContext = playbackContext,
        _isPlaying = isPlaying;

  @override
  GenericSong? get currentTrack => _currentTrack;

  @override
  PlaybackContext? get playbackContext => _playbackContext;

  @override
  bool get isPlaying => _isPlaying;
}

class _FakeMetadataManager extends Fake implements MetadataManager {
  @override
  bool isTrackLiked(String trackId, {String? providerId, String? source}) => false;

  @override
  Future<void> ensureLikedTracksLoaded({String? providerId, String? source}) async {}

  @override
  Future<void> toggleTrackLike(GenericSong track, {String? providerId, String? source}) async {}
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    Provider.debugCheckInvalidValueType = null;
  });
  final testArtist = GenericSimpleArtist(
    id: 'artist_1',
    name: 'The Artist',
    source: 'spotify',
    thumbnailUrl: '',
  );

  final testSong = GenericSong(
    id: 'track_1',
    source: 'spotify',
    title: 'Test Song',
    durationSecs: 215,
    explicit: false,
    artists: [testArtist],
    album: GenericSimpleAlbum(
      id: 'album_1',
      title: 'The Album',
      source: 'spotify',
      thumbnailUrl: '',
      label: 'Record Label',
      artists: [testArtist],
      releaseDate: DateTime(2023, 5, 12),
    ),
    thumbnailUrl: '',
  );

  Widget buildTestWidget({
    required Widget child,
    WispAudioHandler? audioHandler,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PreferencesProvider>(
          create: (_) => PreferencesProvider(),
        ),
        Provider<WispAudioHandler>.value(value: audioHandler ?? _FakeAudioHandler()),
        Provider<MetadataManager>.value(value: _FakeMetadataManager()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('TrackRow widget', () {
    testWidgets('renders inline artist and album subtitle with foldAlbumIntoSubtitle', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: TrackRow(
            track: testSong,
            style: AppStyle.AppleMusic,
            foldAlbumIntoSubtitle: true,
            showAlbumName: true,
            showDuration: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('The Artist'), findsOneWidget);
      expect(find.text(' • '), findsOneWidget);
      expect(find.text('The Album'), findsOneWidget);
    });

    testWidgets('omits index when index is null in Spotify style', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: TrackRow(
            track: testSong,
            style: AppStyle.Spotify,
            index: null,
            showDuration: true,
            trailing: LikeButton(
              track: testSong,
              hoverOnlyWhenUnliked: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsNothing);
      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('The Artist'), findsOneWidget);
    });

    testWidgets('calls onArtistTap when artist name is tapped', (tester) async {
      GenericSimpleArtist? tappedArtist;
      await tester.pumpWidget(
        buildTestWidget(
          child: TrackRow(
            track: testSong,
            style: AppStyle.AppleMusic,
            foldAlbumIntoSubtitle: true,
            showAlbumName: true,
            onArtistTap: (artist) => tappedArtist = artist,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('The Artist'));
      await tester.pumpAndSettle();

      expect(tappedArtist, isNotNull);
      expect(tappedArtist?.id, 'artist_1');
    });

    testWidgets('renders more button and triggers onMoreTap in Spotify and Apple Music styles', (tester) async {
      var spotifyMoreTapped = false;
      await tester.pumpWidget(
        buildTestWidget(
          child: TrackRow(
            track: testSong,
            style: AppStyle.Spotify,
            onMoreTap: (context) => spotifyMoreTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(spotifyMoreTapped, isTrue);

      var appleMoreTapped = false;
      await tester.pumpWidget(
        buildTestWidget(
          child: TrackRow(
            track: testSong,
            style: AppStyle.AppleMusic,
            onMoreTap: (context) => appleMoreTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final appleIcon = find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon?.codePoint != null,
      );
      expect(appleIcon, findsWidgets);
      await tester.tap(find.byType(GenericIconButton));
      await tester.pumpAndSettle();
      expect(appleMoreTapped, isTrue);
    });

    testWidgets('empty track id never shows as playing even if currentTrack has empty id', (tester) async {
      final emptyIdTrack = GenericSong(
        id: '',
        source: 'spotify',
        title: 'Empty ID Song',
        durationSecs: 180,
        explicit: false,
        artists: [testArtist],
        thumbnailUrl: '',
      );

      final playlistContext = PlaybackContext(
        type: PlaybackContextType.playlist,
        id: 'liked_songs',
        name: 'Liked Songs',
        source: 'spotify',
      );

      final handler = _FakeAudioHandler(
        currentTrack: emptyIdTrack,
        playbackContext: playlistContext,
        isPlaying: true,
      );

      await tester.pumpWidget(
        buildTestWidget(
          audioHandler: handler,
          child: TrackRow(
            track: emptyIdTrack,
            viewContext: playlistContext,
            style: AppStyle.Spotify,
            index: 0,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Title should be white, NOT green/accent primary color
      final textWidget = tester.widget<Text>(find.text('Empty ID Song'));
      expect(textWidget.style?.color, equals(Colors.white));
    });

    testWidgets('matching non-empty track id shows as playing, distinct id does not', (tester) async {
      final playlistContext = PlaybackContext(
        type: PlaybackContextType.playlist,
        id: 'liked_songs',
        name: 'Liked Songs',
        source: 'spotify',
      );

      final otherSong = GenericSong(
        id: 'track_2',
        source: 'spotify',
        title: 'Other Song',
        durationSecs: 200,
        explicit: false,
        artists: [testArtist],
        thumbnailUrl: '',
      );

      final handler = _FakeAudioHandler(
        currentTrack: testSong, // id: 'track_1'
        playbackContext: playlistContext,
        isPlaying: true,
      );

      await tester.pumpWidget(
        buildTestWidget(
          audioHandler: handler,
          child: Column(
            children: [
              TrackRow(
                track: testSong,
                viewContext: playlistContext,
                style: AppStyle.Spotify,
                index: 0,
              ),
              TrackRow(
                track: otherSong,
                viewContext: playlistContext,
                style: AppStyle.Spotify,
                index: 1,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final playingText = tester.widget<Text>(find.text('Test Song'));
      final notPlayingText = tester.widget<Text>(find.text('Other Song'));

      // The currently playing track row is highlighted (not white), whereas other is white
      expect(notPlayingText.style?.color, equals(Colors.white));
      expect(playingText.style?.color, isNot(equals(Colors.white)));
    });

    testWidgets('TrackRow centers artwork and hides columns when isCollapsed is true', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: SizedBox(
            width: 88,
            child: TrackRow(
              track: testSong,
              style: AppStyle.Spotify,
              index: 0,
              isCollapsed: true,
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            ),
          ),
        ),
      );

      // Title should not be rendered
      expect(find.text('Test Song'), findsNothing);
      // Index column should not be rendered
      expect(find.text('1'), findsNothing);

      // Artwork (height/width: 48) should be centered in the 88px container (center dx = 44)
      final center = tester.getCenter(
        find.descendant(of: find.byType(TrackRow), matching: find.byType(AspectRatio)),
      );
      expect(center.dx, equals(44.0));
    });
  });
}
