// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/providers/jumo_crypto_utils.dart';
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
    Map<String, String>? headers,
    String? providerId,
    SegmentedAudioDescriptor? segmentedDescriptor,
    Map<String, dynamic>? customData,
  }) {
    final queryParams = {
      'trackId': trackId,
      'videoId': videoId,
      'title': trackTitle,
      'artist': artistName,
      'url': targetUrl,
      'providerId': ?providerId,
      if (headers != null && headers.isNotEmpty)
        'headers': base64Url.encode(utf8.encode(jsonEncode(headers))),
      if (segmentedDescriptor != null)
        'segmented': base64Url.encode(utf8.encode(jsonEncode(segmentedDescriptor.toMap()))),
      if (customData != null && customData.isNotEmpty)
        'customData': base64Url.encode(utf8.encode(jsonEncode(customData))),
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

    final targetUrl = request.url.queryParameters['url'];
    final trackId = request.url.queryParameters['trackId'];
    final videoId = request.url.queryParameters['videoId'] ?? '';
    final trackTitle = request.url.queryParameters['title'] ?? 'Unknown Track';
    final artistName = request.url.queryParameters['artist'] ?? 'Unknown Artist';
    final providerId = request.url.queryParameters['providerId'] ?? 'unknown';
    final rawHeadersParam = request.url.queryParameters['headers'];
    final rawSegmentedParam = request.url.queryParameters['segmented'];

    if (targetUrl == null || trackId == null) {
      return shelf.Response.badRequest(body: 'Missing required parameters');
    }

    // Generic segmented stream handling (protocol-driven, provider agnostic)
    if (rawSegmentedParam != null && rawSegmentedParam.isNotEmpty) {
      try {
        final decodedMap = (jsonDecode(utf8.decode(base64Url.decode(rawSegmentedParam))) as Map).cast<String, dynamic>();
        final descriptor = SegmentedAudioDescriptor.fromMap(decodedMap);
        return await _handleSegmentedStream(
          request: request,
          trackId: trackId,
          videoId: videoId,
          trackTitle: trackTitle,
          artistName: artistName,
          descriptor: descriptor,
        );
      } catch (e) {
        logger.w('[AudioStreamingProxy] Failed to parse segmented descriptor: $e');
      }
    }

    try {
      final rangeHeader = request.headers['range'];
      final Map<String, String> requestHeaders = {
        'accept': '*/*',
        'accept-encoding': 'identity',
        'connection': 'keep-alive',
      };

      if (rawHeadersParam != null && rawHeadersParam.isNotEmpty) {
        try {
          final decodedJson =
              jsonDecode(utf8.decode(base64Url.decode(rawHeadersParam))) as Map;
          requestHeaders.addAll(decodedJson.cast<String, String>());
        } catch (_) {}
      }

      if (providerId == 'youtube') {
        requestHeaders.putIfAbsent(
          'user-agent',
          () => YouTubeProvider.userAgentForPlatform(),
        );
        requestHeaders.putIfAbsent('referer', () => 'https://www.youtube.com/');
        requestHeaders.putIfAbsent('origin', () => 'https://www.youtube.com');
      }

      if (rangeHeader != null) {
        requestHeaders['range'] = rangeHeader;
      }

      final options = Options(
        headers: requestHeaders,
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null && status < 500,
      );

      final response = await _dio.get<ResponseBody>(
        targetUrl,
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
          rangeHeader == 'bytes=0-' ||
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

  /// Concurrently downloads, decrypts, and streams segmented audio seamlessly.
  Future<shelf.Response> _handleSegmentedStream({
    required shelf.Request request,
    required String trackId,
    required String videoId,
    required String trackTitle,
    required String artistName,
    required SegmentedAudioDescriptor descriptor,
  }) async {
    try {
      final storage = AudioStorageService.instance;
      final cacheDir = storage.cacheDirectory;
      final container = descriptor.container;
      final cipherConfig = descriptor.cipher;
      final contentKey = cipherConfig != null && cipherConfig.keyHex.isNotEmpty
          ? JumoCryptoUtils.hexToBytes(cipherConfig.keyHex)
          : Uint8List(0);

      // Check if file was already fully assembled & cached locally
      if (cacheDir != null) {
        final fileName = storage.buildSafeCacheFileName(trackId, videoId, extension: container);
        final cachedFile = File('${cacheDir.path}/$fileName');
        if (await cachedFile.exists()) {
          final length = await cachedFile.length();
          final headers = {
            'content-type': container == 'flac' ? 'audio/flac' : 'audio/mp4',
            'content-length': length.toString(),
            'accept-ranges': 'bytes',
          };
          return shelf.Response.ok(cachedFile.openRead(), headers: headers);
        }
      }

      // 1. Fetch initialization segment (Metadata & segment table)
      final initRes = await _dio.get<List<int>>(
        descriptor.initSegmentUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (initRes.data == null || initRes.data!.isEmpty) {
        throw Exception('Failed to download audio initialization segment');
      }

      final seg0Info = JumoCryptoUtils.parseSegment0(Uint8List.fromList(initRes.data!));
      final numSegments = seg0Info.table.isNotEmpty ? seg0Info.table.length : descriptor.segmentCount;

      // Spooling setup to cache track as it plays
      final shouldSpool = AudioCacheManager.instance.autoCacheEnabled &&
          !storage.isStorageFull &&
          !storage.isTrackCached(trackId);

      String? tempPartPath;
      String? finalFilePath;
      IOSink? fileSink;
      File? partFile;

      if (shouldSpool && cacheDir != null) {
        final fileName = storage.buildSafeCacheFileName(trackId, videoId, extension: container);
        finalFilePath = '${cacheDir.path}/$fileName';
        tempPartPath = '$finalFilePath.part';
        partFile = File(tempPartPath);
        fileSink = partFile.openWrite();
      }

      final streamController = StreamController<List<int>>();

      // Write header first
      final headerBytes = seg0Info.header;
      fileSink?.add(headerBytes);
      streamController.add(headerBytes);

      // Stream segments in background sequentially as they are downloaded
      unawaited(() async {
        try {
          for (var s = 1; s <= numSegments; s++) {
            final segUrl = descriptor.segmentUrlTemplate.replaceAll(r'$SEGMENT$', s.toString());
            final segRes = await _dio.get<List<int>>(
              segUrl,
              options: Options(responseType: ResponseType.bytes),
            );
            if (segRes.data == null || segRes.data!.isEmpty) {
              throw Exception('Segment $s download failed');
            }

            final rawSegmentBytes = Uint8List.fromList(segRes.data!);
            final audioBytes = contentKey.isNotEmpty
                ? JumoCryptoUtils.decryptSegmentAudio(
                    segmentBytes: rawSegmentBytes,
                    contentKey: contentKey,
                  )
                : rawSegmentBytes;

            fileSink?.add(audioBytes);
            streamController.add(audioBytes);
          }

          await streamController.close();
          final localPartFile = partFile;
          final localSink = fileSink;
          if (localSink != null) {
            await localSink.flush();
            await localSink.close();

            if (localPartFile != null && await localPartFile.exists() && await localPartFile.length() > 0) {
              await storage.registerCompletedDownload(
                trackId: trackId,
                videoId: videoId,
                tempPartPath: tempPartPath!,
                finalFilePath: finalFilePath!,
                trackTitle: trackTitle,
                artistName: artistName,
                isUserDownload: false,
              );
              AudioCacheManager.instance.coordinator.setCompleted(trackId);
              logger.i('[AudioStreamingProxy] Segmented track assembled and cached: $trackTitle');
            }
          }
        } catch (e, st) {
          logger.e('[AudioStreamingProxy] Error assembling segmented stream: $e', error: e, stackTrace: st);
          if (!streamController.isClosed) {
            streamController.addError(e, st);
            await streamController.close();
          }
          final localPartFile = partFile;
          if (fileSink != null) {
            await fileSink.close();
            try {
              if (localPartFile != null && await localPartFile.exists()) {
                await localPartFile.delete();
              }
            } catch (_) {}
          }
        }
      }());

      final headers = {
        'content-type': container == 'flac' ? 'audio/flac' : 'audio/mp4',
        'accept-ranges': 'none',
      };

      return shelf.Response.ok(
        streamController.stream,
        headers: headers,
      );
    } catch (e, stack) {
      logger.e('[AudioStreamingProxy] Segmented stream initialization error: $e', error: e, stackTrace: stack);
      return shelf.Response.internalServerError(body: 'Segmented stream error: $e');
    }
  }
}

/// Backwards compatibility alias
final streamingServer = AudioStreamingProxy.instance;
