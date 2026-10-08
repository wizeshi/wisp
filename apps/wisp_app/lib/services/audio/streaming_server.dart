// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:pointycastle/export.dart';
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
  final Map<String, Future<void>> _inFlightSpools = {};

  int get port => _port;
  bool get isRunning => _server != null;

  /// Serves a local file with full RFC 7233 HTTP Range (206 Partial Content) support.
  Future<shelf.Response> _serveLocalFile({
    required File file,
    required shelf.Request request,
    required String contentType,
  }) async {
    final length = await file.length();
    final rangeHeader = request.headers['range'];

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeSpec = rangeHeader.substring(6).trim();
      final parts = rangeSpec.split('-');
      final startStr = parts[0].trim();
      final endStr = parts.length > 1 ? parts[1].trim() : '';

      int start = 0;
      int end = length - 1;

      if (startStr.isNotEmpty && endStr.isNotEmpty) {
        start = int.tryParse(startStr) ?? 0;
        end = int.tryParse(endStr) ?? (length - 1);
      } else if (startStr.isNotEmpty && endStr.isEmpty) {
        start = int.tryParse(startStr) ?? 0;
        end = length - 1;
      } else if (startStr.isEmpty && endStr.isNotEmpty) {
        final suffix = int.tryParse(endStr) ?? 0;
        start = (length - suffix).clamp(0, length - 1);
        end = length - 1;
      }

      if (start >= length || start < 0 || end < start) {
        return shelf.Response(
          416, // Range Not Satisfiable
          headers: {
            'content-range': 'bytes */$length',
            'accept-ranges': 'bytes',
          },
        );
      }

      end = end.clamp(start, length - 1);
      final chunkSize = end - start + 1;

      final headers = {
        'content-type': contentType,
        'content-range': 'bytes $start-$end/$length',
        'content-length': chunkSize.toString(),
        'accept-ranges': 'bytes',
      };

      return shelf.Response(
        206, // Partial Content
        body: file.openRead(start, end + 1),
        headers: headers,
      );
    }

    final headers = {
      'content-type': contentType,
      'content-length': length.toString(),
      'accept-ranges': 'bytes',
    };
    return shelf.Response.ok(file.openRead(), headers: headers);
  }

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
    bool spool = true,
  }) {
    final queryParams = {
      'trackId': trackId,
      'videoId': videoId,
      'title': trackTitle,
      'artist': artistName,
      'url': targetUrl,
      'providerId': ?providerId,
      if (!spool) 'spool': '0',
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
    final rawCustomDataParam = request.url.queryParameters['customData'];

    if (targetUrl == null || trackId == null) {
      return shelf.Response.badRequest(body: 'Missing required parameters');
    }

    Map<String, dynamic>? customData;
    if (rawCustomDataParam != null && rawCustomDataParam.isNotEmpty) {
      try {
        customData = (jsonDecode(utf8.decode(base64Url.decode(rawCustomDataParam))) as Map).cast<String, dynamic>();
      } catch (_) {}
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

    final spoolParam = request.url.queryParameters['spool'];
    final allowSpool = spoolParam != '0' && spoolParam != 'false';

    // Generic AES-CTR streaming decryption (protocol-driven, provider agnostic)
    if (customData != null && customData['cipher'] is Map) {
      final cipherMap = (customData['cipher'] as Map).cast<String, dynamic>();
      final algorithm = cipherMap['algorithm']?.toString().toLowerCase();
      if (algorithm == 'aes-128-ctr' || algorithm == 'aes-ctr') {
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
        return await _handleAesCtrStream(
          request: request,
          trackId: trackId,
          videoId: videoId,
          trackTitle: trackTitle,
          artistName: artistName,
          targetUrl: targetUrl,
          headers: requestHeaders,
          cipherMap: cipherMap,
          allowSpool: allowSpool,
        );
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
      final shouldSpool = allowSpool &&
          isStartOfStream &&
          AudioCacheManager.instance.autoCacheEnabled &&
          !storage.isStorageFull &&
          !storage.isTrackCached(trackId) &&
          !AudioCacheManager.instance.isDownloading(trackId);

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
      final cachedPath = storage.getCachedPath(trackId) ??
          (videoId.isNotEmpty ? storage.getCachedPath(videoId) : null) ??
          (cacheDir != null
              ? '${cacheDir.path}/${storage.buildSafeCacheFileName(trackId, videoId, extension: container)}'
              : null);
      if (cachedPath != null) {
        final cachedFile = File(cachedPath);
        if (await cachedFile.exists()) {
          return await _serveLocalFile(
            file: cachedFile,
            request: request,
            contentType: container == 'flac' ? 'audio/flac' : 'audio/mp4',
          );
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

  /// Concurrently downloads, decrypts AES-CTR chunks, and streams audio seamlessly.
  Future<shelf.Response> _handleAesCtrStream({
    required shelf.Request request,
    required String trackId,
    required String videoId,
    required String trackTitle,
    required String artistName,
    required String targetUrl,
    required Map<String, String> headers,
    required Map<String, dynamic> cipherMap,
    bool allowSpool = true,
  }) async {
    try {
      final storage = AudioStorageService.instance;
      final cacheDir = storage.cacheDirectory;
      final format = cipherMap['format']?.toString() ?? 'ogg';
      final keyHex = cipherMap['keyHex']?.toString() ?? '';
      final ivHex = cipherMap['ivHex']?.toString() ?? '72e067fbddcbcf77ebe8bc643f630d93';
      final skipBytes = (cipherMap['skipBytes'] as num?)?.toInt() ?? 0;

      final normalizedTrackId = storage.normalizeTrackId(trackId);
      final spoolKey = '$normalizedTrackId|$videoId';

      // 1. Check if cached file already exists locally
      final cachedPath = storage.getCachedPath(trackId) ??
          (videoId.isNotEmpty ? storage.getCachedPath(videoId) : null) ??
          (cacheDir != null
              ? '${cacheDir.path}/${storage.buildSafeCacheFileName(normalizedTrackId, videoId, extension: format)}'
              : null);

      if (cachedPath != null) {
        final cachedFile = File(cachedPath);
        if (await cachedFile.exists()) {
          logger.i('[AudioStreamingProxy] Serving cached decrypted audio: $trackTitle');
          return await _serveLocalFile(
            file: cachedFile,
            request: request,
            contentType: format == 'ogg' ? 'audio/ogg' : 'audio/mp4',
          );
        }
      }

      // 2. If a background download/spool is currently in flight for this track, wait for it
      if (_inFlightSpools.containsKey(spoolKey)) {
        try {
          logger.d('[AudioStreamingProxy] Awaiting in-flight spool for $trackTitle');
          await _inFlightSpools[spoolKey]?.timeout(const Duration(seconds: 15));
          if (cachedPath != null) {
            final cachedFile = File(cachedPath);
            if (await cachedFile.exists()) {
              return await _serveLocalFile(
                file: cachedFile,
                request: request,
                contentType: format == 'ogg' ? 'audio/ogg' : 'audio/mp4',
              );
            }
          }
        } catch (_) {}
      }

      final keyBytes = JumoCryptoUtils.hexToBytes(keyHex);
      final ivBytes = JumoCryptoUtils.hexToBytes(ivHex);

      final cipher = CTRStreamCipher(AESEngine());
      cipher.init(false, ParametersWithIV(KeyParameter(keyBytes), ivBytes));

      final options = Options(
        headers: headers,
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null && status < 500,
      );

      final response = await _dio.get<ResponseBody>(
        targetUrl,
        options: options,
      );

      final statusCode = response.statusCode ?? 200;
      final upstreamStream = response.data?.stream;
      if (upstreamStream == null) {
        return shelf.Response(statusCode);
      }

      final isStartOfStream = request.headers['range'] == null ||
          request.headers['range'] == 'bytes=0-' ||
          request.headers['range'] == 'bytes=0';
      final shouldSpool = allowSpool &&
          isStartOfStream &&
          AudioCacheManager.instance.autoCacheEnabled &&
          !storage.isStorageFull &&
          !storage.isTrackCached(normalizedTrackId) &&
          !AudioCacheManager.instance.isDownloading(trackId) &&
          !_inFlightSpools.containsKey(spoolKey);

      String? tempPartPath;
      String? finalFilePath;
      IOSink? fileSink;
      File? partFile;
      Completer<void>? spoolCompleter;

      if (shouldSpool && cacheDir != null) {
        final fileName = storage.buildSafeCacheFileName(normalizedTrackId, videoId, extension: format);
        finalFilePath = '${cacheDir.path}/$fileName';
        tempPartPath = '$finalFilePath.part';
        partFile = File(tempPartPath);
        fileSink = partFile.openWrite();
        spoolCompleter = Completer<void>();
        _inFlightSpools[spoolKey] = spoolCompleter.future;
      }

      final streamController = StreamController<List<int>>();
      var skipRemaining = skipBytes;

      upstreamStream.listen(
        (chunk) {
          final decrypted = cipher.process(Uint8List.fromList(chunk));
          if (skipRemaining > 0) {
            if (decrypted.length <= skipRemaining) {
              skipRemaining -= decrypted.length;
              return;
            } else {
              final valid = Uint8List.fromList(decrypted.sublist(skipRemaining));
              skipRemaining = 0;
              fileSink?.add(valid);
              streamController.add(valid);
            }
          } else {
            fileSink?.add(decrypted);
            streamController.add(decrypted);
          }
        },
        onError: (Object e, StackTrace st) {
          fileSink?.close();
          try {
            if (partFile?.existsSync() == true) partFile?.deleteSync();
          } catch (_) {}
          _inFlightSpools.remove(spoolKey);
          if (spoolCompleter != null && !spoolCompleter.isCompleted) {
            spoolCompleter.completeError(e);
          }
          if (!streamController.isClosed) {
            streamController.addError(e, st);
            streamController.close();
          }
        },
        onDone: () async {
          if (!streamController.isClosed) {
            await streamController.close();
          }
          final localSink = fileSink;
          final localPart = partFile;
          if (localSink != null && localPart != null) {
            try {
              await localSink.flush();
              await localSink.close();
              if (await localPart.exists() && await localPart.length() > 0) {
                await storage.registerCompletedDownload(
                  trackId: normalizedTrackId,
                  videoId: videoId,
                  tempPartPath: tempPartPath!,
                  finalFilePath: finalFilePath!,
                  trackTitle: trackTitle,
                  artistName: artistName,
                  isUserDownload: false,
                );
                AudioCacheManager.instance.coordinator.setCompleted(trackId);
                logger.i('[AudioStreamingProxy] Decrypted track cached: $trackTitle');
              }
            } catch (e) {
              logger.w('[AudioStreamingProxy] Failed to finalize cached decrypted audio: $e');
              try {
                if (await localPart.exists()) await localPart.delete();
              } catch (_) {}
            } finally {
              _inFlightSpools.remove(spoolKey);
              if (spoolCompleter != null && !spoolCompleter.isCompleted) {
                spoolCompleter.complete();
              }
            }
          } else {
            _inFlightSpools.remove(spoolKey);
            if (spoolCompleter != null && !spoolCompleter.isCompleted) {
              spoolCompleter.complete();
            }
          }
        },
        cancelOnError: true,
      );

      // For live unseekable AES-CTR streaming, advertise 'accept-ranges': 'none' and omit
      // static 'content-length' so media players (MediaKit/mpv) treat the stream as chunked
      // sequential audio rather than attempting backwards seeks for container trailers.
      final responseHeaders = <String, String>{
        'content-type': format == 'ogg' ? 'audio/ogg' : 'audio/mp4',
        'accept-ranges': 'none',
      };

      return shelf.Response(statusCode, body: streamController.stream, headers: responseHeaders);
    } catch (e, stack) {
      logger.e('[AudioStreamingProxy] AES-CTR stream error: $e', error: e, stackTrace: stack);
      return shelf.Response.internalServerError(body: 'AES-CTR stream error: $e');
    }
  }
}

/// Backwards compatibility alias
final streamingServer = AudioStreamingProxy.instance;
