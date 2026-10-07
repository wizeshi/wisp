import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/cache/audio/audio_mapping_store.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';

class MockAudioSource extends AudioSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final int priority;

  final List<AudioTrackCandidate> Function(AudioSearchQuery)? onSearch;
  final AudioStreamResult Function(String mediaId)? onStream;

  MockAudioSource({
    required this.id,
    required this.name,
    this.priority = 10,
    this.onSearch,
    this.onStream,
  });

  @override
  Future<List<AudioTrackCandidate>> searchAudio(AudioSearchQuery query) async {
    if (onSearch != null) return onSearch!(query);
    return [
      AudioTrackCandidate(
        mediaId: 'mock_$id',
        providerId: id,
        title: query.title,
        artist: query.artistNames,
        duration: Duration(seconds: query.durationSecs ?? 200),
      ),
    ];
  }

  @override
  Future<AudioStreamResult> getStreamUrl(
    String mediaId, {
    AudioQuality? preferredQuality,
  }) async {
    if (onStream != null) return onStream!(mediaId);
    return AudioStreamResult(
      url: 'https://cdn.example.com/$id/$mediaId.mp3',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_resolver_test_');
    await AudioMappingStore.instance.initialize(supportDirectory: tempDir);
    await AudioMappingStore.instance.clear();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resolveTrack prioritizes manual override in AudioMappingStore', () async {
    final track = GenericSong(
      id: 'track_123',
      source: 'spotify',
      title: 'Let It Happen',
      thumbnailUrl: 'https://example.com/cover.jpg',
      explicit: false,
      durationSecs: 467,
      artists: [
        GenericSimpleArtist(
          id: 'a1',
          source: 'spotify',
          name: 'Tame Impala',
          thumbnailUrl: 'https://example.com/artist.jpg',
        ),
      ],
    );

    final canonicalKey = AudioMappingStore.canonicalKey(
      title: track.title,
      artists: track.artists.map((a) => a.name),
    );

    // Set a manual override for provider "custom_source"
    await AudioMappingStore.instance.setMapping(
      canonicalKey,
      AudioMappingItem(
        providerID: 'custom_source',
        mediaID: 'custom_media_999',
        manualOverride: true,
      ),
    );

    // Verify stored override
    final item = AudioMappingStore.instance.getMapping(canonicalKey, 'custom_source');
    expect(item, isNotNull);
    expect(item!.manualOverride, isTrue);
    expect(item.mediaID, 'custom_media_999');
  });

  test('canonicalKey handles multi-artist and punctuation robustly', () {
    final key = AudioMappingStore.canonicalKey(
      title: 'Let It Happen (Original Mix)',
      artists: ['Tame Impala', 'Kevin Parker'],
    );
    expect(key.contains('happen'), isTrue);
    expect(key.contains('impala'), isTrue);
    expect(key.contains('let'), isTrue);
    expect(key.contains('parker'), isTrue);
  });

  test('SegmentedAudioDescriptor serializes and deserializes accurately', () {
    final descriptor = SegmentedAudioDescriptor(
      initSegmentUrl: 'https://cdn.example.com/stream?s=0',
      segmentUrlTemplate: 'https://cdn.example.com/stream?s=\$SEGMENT\$',
      segmentCount: 26,
      container: 'flac',
      cipher: SegmentCipherConfig(
        algorithm: 'aes-ctr',
        keyHex: '15f27328dddff2b91ab4461cb98c0ecf',
        ivMode: 'mp4-uuid',
      ),
    );

    final map = descriptor.toMap();
    final reconstructed = SegmentedAudioDescriptor.fromMap(map);

    expect(reconstructed.initSegmentUrl, 'https://cdn.example.com/stream?s=0');
    expect(reconstructed.segmentUrlTemplate, 'https://cdn.example.com/stream?s=\$SEGMENT\$');
    expect(reconstructed.segmentCount, 26);
    expect(reconstructed.container, 'flac');
    expect(reconstructed.cipher, isNotNull);
    expect(reconstructed.cipher!.algorithm, 'aes-ctr');
    expect(reconstructed.cipher!.keyHex, '15f27328dddff2b91ab4461cb98c0ecf');
    expect(reconstructed.cipher!.ivMode, 'mp4-uuid');
  });
}
