import 'dart:io';

import 'package:http/http.dart' as http;

class DownloadService {
  Future<File> download({
    required String url,
    required File destination,
    required void Function(int received, int? total) onProgress,
  }) async {
    final client = http.Client();
    IOSink? sink;

    try {
      await destination.parent.create(recursive: true);
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      final total = response.contentLength;
      sink = destination.openWrite();
      var received = 0;

      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }

      await sink.close();
      sink = null;
      return destination;
    } finally {
      await sink?.close();
      client.close();
    }
  }
}
