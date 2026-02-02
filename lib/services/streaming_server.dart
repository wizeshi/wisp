import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import '../utils/logger.dart';

/// HTTP server that proxies YouTube audio streams with proper headers
class StreamingServer {
  HttpServer? _server;
  int _port = 0;
  final Dio _dio = Dio();
  
  // Random user agents from different YouTube clients to avoid 403 errors
  static final List<String> _userAgents = [
    'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Safari/605.1.15',
    'Mozilla/5.0 (iPad; CPU OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1',
  ];
  
  String get _randomUserAgent => 
      _userAgents[Random().nextInt(_userAgents.length)];
  
  int get port => _port;
  String get host => Platform.isWindows ? 'localhost' : '0.0.0.0';
  
  /// Start the streaming server on a random port
  Future<void> start() async {
    if (_server != null) return;
    
    // Find a random available port
    _port = Random().nextInt(10000) + 10000; // Ports 10000-20000
    
    final handler = shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handleRequest);
    
    _server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      _port,
    );
    
    logger.i('🌐 Streaming server started at http://localhost:$_port');
  }
  
  /// Stop the streaming server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    logger.i('🛑 Streaming server stopped');
  }
  
  /// Handle incoming streaming requests
  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    // Extract YouTube URL from query parameter
    final youtubeUrl = request.url.queryParameters['url'];
    
    if (youtubeUrl == null) {
      return shelf.Response.badRequest(
        body: 'Missing url parameter',
      );
    }
    
    try {
      // Make request to YouTube with proper headers
      final options = Options(
        headers: {
          'user-agent': _randomUserAgent,
          'accept': '*/*',
          'accept-encoding': 'identity',
          'connection': 'keep-alive',
          'range': request.headers['range'] ?? 'bytes=0-',
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
      
      // Forward the YouTube response headers
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          headers[name] = values.first;
        }
      });
      
      // Ensure we have content-type
      headers['content-type'] ??= 'audio/webm';
      
      return shelf.Response(
        response.statusCode ?? 200,
        body: response.data!.stream,
        headers: headers,
      );
    } catch (e, stack) {
      logger.e('❌ Streaming error', error: e, stackTrace: stack);
      return shelf.Response.internalServerError(
        body: 'Streaming error: $e',
      );
    }
  }
}

/// Global streaming server instance
final streamingServer = StreamingServer();
