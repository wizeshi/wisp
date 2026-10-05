// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

class _FakeAudioHandler extends Fake implements WispAudioHandler {
  @override
  GenericSong? get currentTrack => null;

  @override
  PlaybackContext? get playbackContext => null;

  @override
  bool get isPlaying => false;
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

  Widget buildTestWidget({required Widget child}) {
    return MultiProvider(
      providers: [
        Provider<WispAudioHandler>.value(value: _FakeAudioHandler()),
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
  });
}
