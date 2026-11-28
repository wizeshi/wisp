import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/data/cache/audio/audio_storage_service.dart';
import 'package:wisp/services/audio/streaming_server.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wisp_streaming_proxy_test_');
    SharedPreferences.setMockInitialValues({});
    final storage = AudioStorageService.instance;
    storage.resetForTesting();
    await storage.initialize(
      supportDirectory: tempDir,
      cacheDirectory: tempDir,
    );
    await AudioStreamingProxy.instance.start();
  });

  tearDownAll(() async {
    await AudioStreamingProxy.instance.stop();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test(
    'spooled stream cancels upstream download and deletes .part file on client disconnect',
    () async {
      final upstreamDisconnected = Completer<void>();
      var chunksSent = 0;

      final upstreamServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => upstreamServer.close(force: true));

      upstreamServer.listen((HttpRequest req) async {
        req.response.statusCode = 200;
        req.response.bufferOutput = false;
        req.response.headers.contentType = ContentType('audio', 'mp4');
        var closed = false;

        final timer = Timer.periodic(const Duration(milliseconds: 15), (t) {
          if (closed || chunksSent >= 1000) {
            t.cancel();
            return;
          }
          chunksSent++;
          try {
            req.response.add(List<int>.filled(4096, 0x41));
          } catch (_) {
            closed = true;
            t.cancel();
            if (!upstreamDisconnected.isCompleted) {
              upstreamDisconnected.complete();
            }
          }
        });

        unawaited(
          req.response.done.catchError((_) {}).whenComplete(() {
            closed = true;
            timer.cancel();
            if (!upstreamDisconnected.isCompleted) {
              upstreamDisconnected.complete();
            }
          }),
        );
      });

      final proxyUrl = AudioStreamingProxy.instance.buildProxyUrl(
        trackId: 'test_abort_track_1',
        videoId: 'vid_abort_1',
        trackTitle: 'Abort Test',
        artistName: 'Test Artist',
        targetUrl: 'http://127.0.0.1:${upstreamServer.port}/audio.m4a',
        spool: true,
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(Uri.parse(proxyUrl));
      final response = await request.close();
      expect(response.statusCode, 200);

      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;
      var receivedBytes = 0;
      sub = response.listen(
        (chunk) {
          receivedBytes += chunk.length;
          if (receivedBytes >= 4096) {
            unawaited(
              sub.cancel().whenComplete(() {
                client.close(force: true);
                if (!completer.isCompleted) completer.complete();
              }),
            );
          }
        },
        onError: (_) {},
      );

      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Client did not receive 4096 bytes (got $receivedBytes)'),
      );
      await upstreamDisconnected.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Upstream did not disconnect (chunksSent=$chunksSent)'),
      );

      expect(chunksSent, lessThan(200));

      // Give async .part cleanup a brief moment to complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final cacheDir = AudioStorageService.instance.cacheDirectory!;
      final partFiles = cacheDir
          .listSync()
          .where((e) => e.path.endsWith('.part'))
          .toList();
      expect(partFiles, isEmpty);
    },
  );
}
