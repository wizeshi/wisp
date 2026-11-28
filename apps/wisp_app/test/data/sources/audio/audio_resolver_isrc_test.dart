import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/cache/audio/audio_mapping_store.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/audio/audio_resolver.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/audio/js_audio_source.dart';
import 'package:wisp/data/sources/audio/sources/youtube_audio_source.dart';

class _ConfigurableAudioSource extends AudioSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final bool supportsIsrcSearch;
  final List<AudioSearchQuery> capturedQueries = [];

  _ConfigurableAudioSource({
    required this.id,
    required this.name,
    this.supportsIsrcSearch = false,
  });

  @override
  Future<List<AudioTrackCandidate>> searchAudio(AudioSearchQuery query) async {
    capturedQueries.add(query);
    return [
      AudioTrackCandidate(
        mediaId: 'found_$id',
        providerId: id,
        title: query.title,
        artist: query.artistNames,
        duration: Duration(seconds: query.durationSecs ?? 180),
      ),
    ];
  }

  @override
  Future<AudioStreamResult> getStreamUrl(
    String mediaId, {
    AudioQuality? preferredQuality,
  }) async {
    return AudioStreamResult(
      url: 'https://cdn.example.com/$id/$mediaId.m4a',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  GenericSong makeSpotifyTrack() => GenericSong(
        id: 'spotify:track:abc123',
        source: 'spotify',
        title: 'Test Track',
        thumbnailUrl: '',
        explicit: false,
        durationSecs: 200,
        artists: [
          GenericSimpleArtist(
            id: 'a1',
            source: 'spotify',
            name: 'Test Artist',
            thumbnailUrl: '',
          ),
        ],
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_resolver_isrc_test_');
    await AudioMappingStore.instance.initialize(supportDirectory: tempDir);
    await AudioMappingStore.instance.clear();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('supportsIsrcSearch defaults false for YouTube and true for JsAudioSource', () {
    final yt = YouTubeAudioSource();
    final js = JsAudioSource(
      id: 'qobuz',
      name: 'Qobuz',
      script: '',
    );
    expect(yt.supportsIsrcSearch, isFalse);
    expect(js.supportsIsrcSearch, isTrue);
  });

  test('skips ISRC lookup when cached mapping hits or source does not use ISRC', () async {
    final track = makeSpotifyTrack();
    final canonicalKey = AudioMappingStore.canonicalKey(
      title: track.title,
      artists: track.artists.map((a) => a.name),
    );

    // 1. Cached mapping hits -> zero ISRC calls even for ISRC-capable source.
    await AudioMappingStore.instance.setMapping(
      canonicalKey,
      AudioMappingItem(
        providerID: 'qobuz',
        mediaID: 'cached_id',
        manualOverride: false,
      ),
    );

    var isrcCalls = 0;
    final isrcSource = _ConfigurableAudioSource(
      id: 'qobuz',
      name: 'Qobuz',
      supportsIsrcSearch: true,
    );
    final resolverWithCache = AudioResolver.forTesting(
      orderedSourcesResolver: (_) => [isrcSource],
      isrcLookup: (_) async {
        isrcCalls++;
        return 'USRC17607839';
      },
    );

    final cachedResult = await resolverWithCache.resolveTrack(track);
    expect(cachedResult, isNotNull);
    expect(cachedResult!.mediaId, 'cached_id');
    expect(isrcCalls, 0);

    // 2. No cached mapping, non-ISRC source (YouTube) -> still zero ISRC calls.
    await AudioMappingStore.instance.clear();
    final ytLikeSource = _ConfigurableAudioSource(
      id: 'youtube',
      name: 'YouTube',
      supportsIsrcSearch: false,
    );
    final resolverNoIsrc = AudioResolver.forTesting(
      orderedSourcesResolver: (_) => [ytLikeSource],
      isrcLookup: (_) async {
        isrcCalls++;
        return 'USRC17607839';
      },
    );

    final nonIsrcResult = await resolverNoIsrc.resolveTrack(track);
    expect(nonIsrcResult, isNotNull);
    expect(isrcCalls, 0);
    expect(ytLikeSource.capturedQueries.single.isrc, isNull);

    // 3. No cached mapping, ISRC-capable source -> resolves ISRC lazily once.
    final isrcMissSource = _ConfigurableAudioSource(
      id: 'qobuz',
      name: 'Qobuz',
      supportsIsrcSearch: true,
    );
    final resolverWithIsrc = AudioResolver.forTesting(
      orderedSourcesResolver: (_) => [isrcMissSource],
      isrcLookup: (_) async {
        isrcCalls++;
        return 'USRC17607839';
      },
    );

    final isrcResult = await resolverWithIsrc.resolveTrack(track);
    expect(isrcResult, isNotNull);
    expect(isrcCalls, 1);
    expect(isrcMissSource.capturedQueries.single.isrc, 'USRC17607839');
  });
}
