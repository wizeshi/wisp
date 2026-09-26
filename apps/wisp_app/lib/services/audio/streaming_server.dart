// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';

/// Local loopback streaming proxy that feeds MediaKit while simultaneously
/// spooling audio chunks into the local cache.
///
/// This eliminates the "double-download" issue where playback streamed from
/// YouTube while Dio concurrently downloaded the exact same audio stream.
class AudioStreamingProxy {
  static final AudioStreamingProxy instance = AudioStreamingProxy._();
  AudioStreamingProxy._();

  HttpServer? _server;
  int _port = 0;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
    ),
  );

  int get port => _port;
  bool get isRunning => _server != null;

  /// Start the loopback proxy server on an unreserved ephemeral port.
  Future<void> start() async {
    if (_server != null) return;

    try {
      final handler = shelf.Pipeline().addHandler(_handleRequest);

      // Port 0 tells the OS to assign an available ephemeral port
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      _port = _server!.port;
      logger.i('[AudioStreamingProxy] Started at http://127.0.0.1:$_port');
    } catch (e) {
      logger.e('[AudioStreamingProxy] Failed to start server', error: e);
    }
  }

  /// Stop the proxy server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    logger.i('[AudioStreamingProxy] Stopped');
  }

  /// Build a loopback URL that MediaKit can stream from.
  String buildProxyUrl({
    required String trackId,
    required String videoId,
    required String trackTitle,
    required String artistName,
    required String targetUrl,
  }) {
    final queryParams = {
      'trackId': trackId,
      'videoId': videoId,
      'title': trackTitle,
      'artist': artistName,
      'url': targetUrl,
    };
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      path: '/stream',
      queryParameters: queryParams,
    );
    return uri.toString();
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    if (request.url.path != 'stream') {
      return shelf.Response.notFound('Not found');
    }

    final youtubeUrl = request.url.queryParameters['url'];
    final trackId = request.url.queryParameters['trackId'];
    final videoId = request.url.queryParameters['videoId'] ?? '';
    final trackTitle =
        request.url.queryParameters['title'] ?? 'Unknown Track';
    final artistName =
        request.url.queryParameters['artist'] ?? 'Unknown Artist';

    if (youtubeUrl == null || trackId == null) {
      return shelf.Response.badRequest(body: 'Missing required parameters');
    }

    try {
      final rangeHeader = request.headers['range'];
      final userAgent = YouTubeProvider.userAgentForPlatform();

      final options = Options(
        headers: {
          'user-agent': userAgent,
          'accept': '*/*',
          'accept-encoding': 'identity',
          'connection': 'keep-alive',
          'range': ?rangeHeader,
          'referer': 'https://www.youtube.com/',
          'origin': 'https://www.youtube.com',
        },
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null && status < 500,
      );

      final response = await _dio.get<ResponseBody>(
        youtubeUrl,
        options: options,
      );

      final statusCode = response.statusCode ?? 200;
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          headers[name] = values.first;
        }
      });
      headers['accept-ranges'] = 'bytes';
      headers['content-type'] ??= 'audio/mp4';

      final upstreamStream = response.data?.stream;
      if (upstreamStream == null) {
        return shelf.Response(statusCode, headers: headers);
      }

      final isStartOfStream = rangeHeader == null ||
          rangeHeader.startsWith('bytes=0-') ||
          rangeHeader == 'bytes=0';
      final storage = AudioStorageService.instance;
      final shouldSpool = isStartOfStream &&
          AudioCacheManager.instance.autoCacheEnabled &&
          !storage.isStorageFull &&
          !storage.isTrackCached(trackId);

      final cacheDir = storage.cacheDirectory;
      if (shouldSpool && cacheDir != null) {
        final fileName = storage.buildSafeCacheFileName(trackId, videoId);
        final finalFilePath = '${cacheDir.path}/$fileName';
        final tempPartPath = '$finalFilePath.part';
        final partFile = File(tempPartPath);
        final sink = partFile.openWrite();

        final controller = StreamController<List<int>>();

        upstreamStream.listen(
          (chunk) {
            try {
              sink.add(chunk);
            } catch (_) {}
            controller.add(chunk);
          },
          onError: (Object e, StackTrace st) {
            sink.close();
            try {
              if (partFile.existsSync()) partFile.deleteSync();
            } catch (_) {}
            controller.addError(e, st);
          },
          onDone: () async {
            await controller.close();
            try {
              await sink.flush();
              await sink.close();

              if (await partFile.exists() && await partFile.length() > 0) {
                await storage.registerCompletedDownload(
                  trackId: trackId,
                  videoId: videoId,
                  tempPartPath: tempPartPath,
                  finalFilePath: finalFilePath,
                  trackTitle: trackTitle,
                  artistName: artistName,
                  isUserDownload: false,
                );
                AudioCacheManager.instance.coordinator.setCompleted(trackId);
                logger.i(
                  '[AudioStreamingProxy] Track cached from stream: $trackTitle',
                );
              }
            } catch (e) {
              logger.w(
                '[AudioStreamingProxy] Failed to finalize cached stream: $e',
              );
              try {
                if (await partFile.exists()) await partFile.delete();
              } catch (_) {}
            }
          },
          cancelOnError: true,
        );

        return shelf.Response(
          statusCode,
          body: controller.stream,
          headers: headers,
        );
      }

      // Non-spooled passthrough
      return shelf.Response(
        statusCode,
        body: upstreamStream,
        headers: headers,
      );
    } catch (e, stack) {
      logger.e('[AudioStreamingProxy] Streaming error', error: e, stackTrace: stack);
      return shelf.Response.internalServerError(body: 'Streaming error: $e');
    }
  }
}

/// Backwards compatibility alias
final streamingServer = AudioStreamingProxy.instance;
