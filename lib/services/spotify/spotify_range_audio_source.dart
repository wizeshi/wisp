library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';

class SpotifyRangeFetchResult {
  final Stream<List<int>> stream;
  final int? sourceLength;
  final int? contentLength;
  final int offset;
  final String? contentType;

  const SpotifyRangeFetchResult({
    required this.stream,
    required this.sourceLength,
    required this.contentLength,
    required this.offset,
    required this.contentType,
  });
}

class SpotifyRangeFetcher {
  final List<Uri> _cdnUrls;
  final Map<String, String> _headers;
  final http.Client _httpClient;

  int? _sourceLength;

  SpotifyRangeFetcher({
    required List<Uri> cdnUrls,
    Map<String, String>? headers,
    http.Client? httpClient,
  }) : _cdnUrls = List.unmodifiable(cdnUrls),
       _headers = Map.unmodifiable(headers ?? const {}),
       _httpClient = httpClient ?? http.Client() {
    if (_cdnUrls.isEmpty) {
      throw ArgumentError.value(cdnUrls, 'cdnUrls', 'At least one CDN URL is required.');
    }
  }

  Future<SpotifyRangeFetchResult> fetchRange({
    int start = 0,
    int? endExclusive,
  }) async {
    final requestStart = start;
    final requestEnd = endExclusive;

    final rangeValue = requestEnd == null
        ? 'bytes=$requestStart-'
        : 'bytes=$requestStart-${requestEnd - 1}';

    Object? lastError;

    for (final url in _cdnUrls) {
      try {
        final response = await _sendRangeRequest(url, rangeValue);
        final status = response.statusCode;

        if (status == 429) {
          final retryAfter = _parseRetryAfterSeconds(response.headers['retry-after']);
          if (retryAfter > 0) {
            logger.w('[Spotify/Range] 429 from $url, waiting ${retryAfter}s');
            await Future.delayed(Duration(seconds: retryAfter));
            continue;
          }
          continue;
        }

        if (status != 206 && status != 200) {
          logger.w('[Spotify/Range] Unexpected status $status from $url');
          continue;
        }

        final sourceLength = _tryExtractSourceLength(response);
        if (sourceLength != null) {
          _sourceLength = sourceLength;
        }

        final contentLength = response.contentLength;
        final contentType = response.headers['content-type'];

        return SpotifyRangeFetchResult(
          sourceLength: _sourceLength,
          contentLength: contentLength != null && contentLength >= 0
              ? contentLength
              : null,
          offset: requestStart,
          contentType: contentType,
          stream: response.stream,
        );
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      throw StateError('[Spotify/Range] All CDN URLs failed. Last error: $lastError');
    }
    throw StateError('[Spotify/Range] All CDN URLs failed.');
  }

  Future<http.StreamedResponse> _sendRangeRequest(Uri url, String range) async {
    final request = http.Request('GET', url)
      ..headers.addAll(_headers)
      ..headers['Range'] = range;

    return _httpClient.send(request).timeout(const Duration(seconds: 20));
  }

  int _parseRetryAfterSeconds(String? value) {
    if (value == null || value.isEmpty) return 0;
    return int.tryParse(value.trim()) ?? 0;
  }

  int? _tryExtractSourceLength(http.StreamedResponse response) {
    final contentRange = response.headers['content-range'];
    if (contentRange != null) {
      final slash = contentRange.lastIndexOf('/');
      if (slash >= 0 && slash + 1 < contentRange.length) {
        final total = contentRange.substring(slash + 1).trim();
        final parsed = int.tryParse(total);
        if (parsed != null && parsed >= 0) {
          return parsed;
        }
      }
    }

    final contentLength = response.contentLength;
    if (contentLength != null && contentLength >= 0) {
      return contentLength;
    }

    return null;
  }

  void close() {
    _httpClient.close();
  }
}
