import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:wisp_jvm/wisp_jvm.dart';
import 'package:wisp_innertubex_manager/src/models/innertubex_models.dart';

typedef InnerTubeXProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

class InnerTubeXBackendException implements Exception {
  final String message;
  InnerTubeXBackendException(this.message);

  @override
  String toString() => 'InnerTubeXBackendException: $message';
}

class InnerTubeXBackend {
  InnerTubeXBackend._internal({
    InnerTubeXProcessStarter? processStarter,
    Future<String> Function()? javaExecutableResolver,
    Future<File> Function()? jarFileResolver,
  })  : _processStarter = processStarter ?? Process.start,
        _javaExecutableResolver =
            javaExecutableResolver ?? JvmRuntimeManager.instance.getJavaExecutablePath,
        _jarFileResolver = jarFileResolver;

  @visibleForTesting
  factory InnerTubeXBackend.forTesting({
    InnerTubeXProcessStarter? processStarter,
    Future<String> Function()? javaExecutableResolver,
    Future<File> Function()? jarFileResolver,
  }) {
    return InnerTubeXBackend._internal(
      processStarter: processStarter,
      javaExecutableResolver: javaExecutableResolver,
      jarFileResolver: jarFileResolver,
    );
  }

  static final InnerTubeXBackend instance = InnerTubeXBackend._internal();

  static const _androidChannel = MethodChannel('dev.wizeshi.wisp/innertubex_android');
  static const List<String> defaultJvmArgs = [
    '-Xmx192m',
    '-Djava.net.preferIPv6Addresses=true',
  ];

  final InnerTubeXProcessStarter _processStarter;
  final Future<String> Function() _javaExecutableResolver;
  final Future<File> Function()? _jarFileResolver;

  JvmDaemonProcess? _daemon;
  int? _localPort;
  Completer<void>? _starting;
  final http.Client _httpClient = http.Client();

  bool get isRunning => Platform.isAndroid || (_daemon != null && _localPort != null);
  int? get localPort => _localPort;

  String get baseUrl => 'http://127.0.0.1:$_localPort';

  Future<File> resolveJarFile() async {
    final override = _jarFileResolver;
    if (override != null) {
      return override();
    }
    final supportDir = await WispSupportDirectory().get();
    final jar = File(p.join(supportDir.path, 'innertubex', 'innertubexstreamextractor.jar'));
    if (await jar.exists()) {
      return jar;
    }
    return File(p.join(supportDir.path, 'innertubex', 'innertubex.jar'));
  }

  Future<void> ensureStarted() async {
    if (Platform.isAndroid) return; // Android uses native in-process plugin
    if (isRunning) return;

    final existing = _starting;
    if (existing != null) {
      return existing.future;
    }

    final starting = Completer<void>();
    starting.future.ignore();
    _starting = starting;

    try {
      final javaExec = await _javaExecutableResolver();
      final jarFile = await resolveJarFile();

      if (!await jarFile.exists()) {
        throw InnerTubeXBackendException(
          'InnerTubeX companion JAR not found at ${jarFile.path}.',
        );
      }

      final process = await _processStarter(
        javaExec,
        [...defaultJvmArgs, '-jar', jarFile.path],
      );

      final daemon = JvmDaemonProcess(process);
      _daemon = daemon;

      final readyCompleter = Completer<int>();

      // Listen for ready handshake line
      final sub = daemon.stdoutLines.listen((line) {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          if (json['status'] == 'ready' && json['port'] is int) {
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete(json['port'] as int);
            }
          }
        } catch (_) {}
      });

      unawaited(daemon.exitCode.then((code) {
        if (identical(_daemon, daemon)) {
          _daemon = null;
          _localPort = null;
        }
        if (identical(_starting, starting)) {
          _starting = null;
        }
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
            InnerTubeXBackendException('InnerTubeX daemon exited with code $code before ready.'),
          );
        }
      }));

      try {
        _localPort = await readyCompleter.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            unawaited(daemon.shutdown());
            throw InnerTubeXBackendException('InnerTubeX daemon startup timed out.');
          },
        );
      } finally {
        await sub.cancel();
      }

      if (!starting.isCompleted) {
        starting.complete();
      }
      if (identical(_starting, starting)) {
        _starting = null;
      }
    } catch (e, st) {
      if (!starting.isCompleted) {
        starting.completeError(e, st);
      }
      if (identical(_starting, starting)) {
        _starting = null;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resolveStream(String videoId) async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('resolveStream', {'videoId': videoId});
      return Map<String, dynamic>.from(res as Map);
    }

    await ensureStarted();
    final res = await _httpClient.get(Uri.parse('$baseUrl/resolve/$videoId'));
    if (res.statusCode != 200) {
      throw InnerTubeXBackendException('Failed to resolve stream: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<InnerTubeSearchResult>> search(String query, {String? type, int limit = 20}) async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('search', {
        'query': query,
        'type': type,
        'limit': limit,
      });
      final list = res as List? ?? [];
      return list.map((e) => InnerTubeSearchResult.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }

    await ensureStarted();
    final res = await _httpClient.post(
      Uri.parse('$baseUrl/search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'type': type, 'limit': limit}),
    );
    if (res.statusCode != 200) {
      throw InnerTubeXBackendException('Search failed with status ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = data['items'] as List? ?? [];
    return items.map((e) => InnerTubeSearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<InnerTubeTrack> getTrackDetails(String videoId) async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('getTrackDetails', {'videoId': videoId});
      return InnerTubeTrack.fromJson(Map<String, dynamic>.from(res as Map));
    }

    await ensureStarted();
    final res = await _httpClient.get(Uri.parse('$baseUrl/track/$videoId'));
    if (res.statusCode != 200) {
      throw InnerTubeXBackendException('Track fetch failed with status ${res.statusCode}');
    }
    return InnerTubeTrack.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<InnerTubeAlbum> getAlbumDetails(String browseId) async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('getAlbumDetails', {'browseId': browseId});
      return InnerTubeAlbum.fromJson(Map<String, dynamic>.from(res as Map));
    }

    await ensureStarted();
    final res = await _httpClient.get(Uri.parse('$baseUrl/album/$browseId'));
    if (res.statusCode != 200) {
      throw InnerTubeXBackendException('Album fetch failed with status ${res.statusCode}');
    }
    return InnerTubeAlbum.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<InnerTubeArtist> getArtistDetails(String browseId) async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('getArtistDetails', {'browseId': browseId});
      return InnerTubeArtist.fromJson(Map<String, dynamic>.from(res as Map));
    }

    await ensureStarted();
    final res = await _httpClient.get(Uri.parse('$baseUrl/artist/$browseId'));
    if (res.statusCode != 200) {
      throw InnerTubeXBackendException('Artist fetch failed with status ${res.statusCode}');
    }
    return InnerTubeArtist.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<InnerTubePlaylist> getPlaylistDetails(String browseId) async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('getPlaylistDetails', {'browseId': browseId});
      return InnerTubePlaylist.fromJson(Map<String, dynamic>.from(res as Map));
    }

    await ensureStarted();
    final res = await _httpClient.get(Uri.parse('$baseUrl/playlist/$browseId'));
    if (res.statusCode != 200) {
      throw InnerTubeXBackendException('Playlist fetch failed with status ${res.statusCode}');
    }
    return InnerTubePlaylist.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<InnerTubeAuthStatus> updateSessionCookies(Map<String, String> cookies) async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('updateSessionCookies', {'cookies': cookies});
      return InnerTubeAuthStatus.fromJson(Map<String, dynamic>.from(res as Map));
    }

    await ensureStarted();
    final res = await _httpClient.post(
      Uri.parse('$baseUrl/auth/session'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'cookies': cookies}),
    );
    return InnerTubeAuthStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<InnerTubeAuthStatus> getAuthStatus() async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('getAuthStatus');
      return InnerTubeAuthStatus.fromJson(Map<String, dynamic>.from(res as Map));
    }

    await ensureStarted();
    final res = await _httpClient.get(Uri.parse('$baseUrl/auth/status'));
    return InnerTubeAuthStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<InnerTubeAuthStatus> clearSession() async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('clearSession');
      return InnerTubeAuthStatus.fromJson(Map<String, dynamic>.from(res as Map));
    }

    await ensureStarted();
    final res = await _httpClient.post(Uri.parse('$baseUrl/auth/logout'));
    return InnerTubeAuthStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<InnerTubeSearchResult>> getLikedTracks() async {
    if (Platform.isAndroid) {
      final res = await _androidChannel.invokeMethod('getLikedTracks');
      final list = res as List? ?? [];
      return list.map((e) => InnerTubeSearchResult.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }

    await ensureStarted();
    final res = await _httpClient.get(Uri.parse('$baseUrl/library/liked'));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = data['items'] as List? ?? [];
    return items.map((e) => InnerTubeSearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> shutdown() async {
    final pending = _starting;
    _starting = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        InnerTubeXBackendException('InnerTubeX backend shut down during startup.'),
      );
    }
    final daemon = _daemon;
    _daemon = null;
    _localPort = null;
    await daemon?.shutdown();
  }
}
