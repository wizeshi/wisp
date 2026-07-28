/// Manages the long-running NewPipeExtractor Java daemon (YtAudioExtractorDaemon)
/// used to resolve YouTube m4a stream URLs on desktop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

class NewPipeDaemonException implements Exception {
  final String message;
  NewPipeDaemonException(this.message);

  @override
  String toString() => 'NewPipeDaemonException: $message';
}

/// Owns a single instance of the NewPipeExtractor daemon process and
/// multiplexes concurrent stream-URL requests over its line-delimited JSON
/// stdin/stdout protocol (see YtAudioExtractorDaemon.java).
///
/// Safe to call `getStreamUrl` concurrently from multiple call sites: each
/// call gets its own request id, and responses are routed back to the
/// caller that made the matching request regardless of completion order.
class NewPipeDaemonManager {
  NewPipeDaemonManager._internal();
  static final NewPipeDaemonManager instance = NewPipeDaemonManager._internal();

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _idCounter = 0;
  Completer<void>? _starting;

  bool get isRunning => _process != null;

  Future<String> _javaExecutable() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final binName = Platform.isWindows ? 'java.exe' : 'java';
    return '${appSupportDir.path}/java/bin/$binName';
  }

  Future<String> _jarPath() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return '${appSupportDir.path}/newpipe/newpipestreamextractor.jar';
  }

  /// Starts the daemon if it isn't already running. Concurrent callers
  /// share the same in-flight start rather than spawning multiple processes.
  Future<void> _ensureStarted() async {
    if (_process != null) return;
    if (_starting != null) return _starting!.future;

    final completer = Completer<void>();
    _starting = completer;

    try {
      final javaExec = await _javaExecutable();
      final jarPath = await _jarPath();

      if (!await File(javaExec).exists()) {
        throw NewPipeDaemonException('Bundled JDK not found at $javaExec');
      }
      if (!await File(jarPath).exists()) {
        throw NewPipeDaemonException('NewPipe daemon jar not found at $jarPath');
      }

      logger.d('[NewPipe/Daemon] Starting: $javaExec -jar $jarPath');
      final process = await Process.start(javaExec, ['-jar', jarPath]);
      _process = process;

      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleStdoutLine,
            onError: (e) => logger.w('[NewPipe/Daemon] stdout error', error: e),
          );

      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => logger.d('[NewPipe/Daemon] $line'));

      // If the process dies (crash, OOM, killed, etc.), fail everything
      // waiting on it and clear state so the next call respawns cleanly.
      unawaited(process.exitCode.then((code) {
        logger.w('[NewPipe/Daemon] process exited (code $code)');
        _process = null;
        _stdoutSub?.cancel();
        _stderrSub?.cancel();
        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(
              NewPipeDaemonException('daemon exited (code $code) before responding'),
            );
          }
        }
        _pending.clear();
      }));

      completer.complete();
    } catch (e) {
      _process = null;
      completer.completeError(e);
      rethrow;
    } finally {
      _starting = null;
    }
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    Map<String, dynamic> obj;
    try {
      obj = json.decode(trimmed) as Map<String, dynamic>;
    } catch (e) {
      logger.w('[NewPipe/Daemon] Unparseable output line, ignoring: $trimmed');
      return;
    }

    final id = obj['id']?.toString();
    if (id == null) {
      logger.w('[NewPipe/Daemon] Response missing id, ignoring: $trimmed');
      return;
    }

    final completer = _pending.remove(id);
    if (completer == null) {
      // Already timed out on our side, or a stray/duplicate line — safe to drop.
      logger.d('[NewPipe/Daemon] No pending request for id $id, ignoring');
      return;
    }
    if (!completer.isCompleted) {
      completer.complete(obj);
    }
  }

  /// Resolves the best m4a stream URL for [videoId] via the daemon.
  /// Can be called concurrently for different video IDs — each call is
  /// independent and does not block behind slower/earlier ones.
  Future<String> getStreamUrl(
    String videoId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await _ensureStarted();

    final process = _process;
    if (process == null) {
      throw NewPipeDaemonException('daemon failed to start');
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final url = 'https://www.youtube.com/watch?v=$videoId';
    final requestLine = json.encode({'id': id, 'url': url});

    try {
      process.stdin.writeln(requestLine);
    } catch (e) {
      _pending.remove(id);
      throw NewPipeDaemonException('failed to write request to daemon: $e');
    }

    final response = await completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw NewPipeDaemonException(
          'daemon timed out after $timeout for video $videoId',
        );
      },
    );

    if (response['ok'] != true) {
      throw NewPipeDaemonException(
        response['error']?.toString() ?? 'unknown daemon error',
      );
    }

    final streamUrl = response['streamUrl']?.toString();
    if (streamUrl == null || streamUrl.isEmpty) {
      throw NewPipeDaemonException('daemon returned no streamUrl');
    }
    return streamUrl;
  }

  /// Gracefully stops the daemon. Call this on app shutdown; not required
  /// between individual requests — the process is meant to stay resident.
  Future<void> shutdown() async {
    final process = _process;
    if (process == null) return;

    try {
      process.stdin.writeln('__shutdown__');
      await process.stdin.flush();
    } catch (_) {
      // best-effort; fall through to killing subscriptions/state regardless
    }

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _process = null;

    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(NewPipeDaemonException('daemon shut down'));
      }
    }
    _pending.clear();
  }
}