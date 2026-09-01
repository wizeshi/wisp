/// Manages the long-running NewPipeExtractor Java daemon
/// used to resolve YouTube stream URLs on desktop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:wisp_newpipe_manager/services/wisp_support_directory.dart';

class NewPipeDaemonException implements Exception {
  final String message;
  NewPipeDaemonException(this.message);

  @override
  String toString() => 'NewPipeDaemonException: $message';
}

/// Owns a single instance of the NewPipeExtractor daemon process and
/// multiplexes concurrent stream-URL requests over its line-delimited JSON
/// stdin/stdout protocol.
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
    final supportDir = await WispSupportDirectory().get();
    final binName = Platform.isWindows ? 'java.exe' : 'java';
    return p.join(supportDir.path, 'java', 'bin', binName);
  }

  Future<String> _jarPath() async {
    final supportDir = await WispSupportDirectory().get();
    return p.join(supportDir.path, 'newpipe', 'newpipestreamextractor.jar');
  }

  /// Starts the daemon if it isn't already running. Concurrent callers block
  /// until startup is complete or fails. Blocks indefinitely if the daemon
  /// process exits after startup (i.e., does not auto-restart on crash).
  Future<void> _ensureStarted() async {
    if (_process != null) return;

    final starting = _starting ?? (_starting = Completer<void>());
    if (_starting != starting) {
      // Another caller beat us here; wait for them
      return starting.future;
    }

    try {
      final javaExec = await _javaExecutable();
      final jar = await _jarPath();

      final process = await Process.start(
        javaExec,
        ['-jar', jar],
      );

      _process = process;

      // Process stdout line-by-line
      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        try {
          final response = json.decode(line) as Map<String, dynamic>;
          final id = response['id']?.toString();
          final completer = id != null ? _pending.remove(id) : null;
          completer?.complete(response);
        } catch (e) {
          // Ignore parse errors; lines might be debug output
        }
      });

      // Log stderr for debugging
      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        // Optionally log: print('[NewPipe Daemon] $line');
      });

      // Clean up on exit
      unawaited(process.exitCode.then((_) {
        _process = null;
        _stdoutSub?.cancel();
        _stderrSub?.cancel();
        _starting = null;
        _pending.clear();
      }));

      _starting?.complete();
    } catch (e) {
      _starting?.completeError(e);
      _starting = null;
      rethrow;
    }
  }

  /// Requests a stream URL from the daemon. Each request gets a unique ID
  /// and the response is matched back by that ID, so concurrent requests
  /// are safe. If the daemon is not running, it is started.
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
      process.stdin.close();
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (e) {
      process.kill();
    } finally {
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
      _process = null;
      _starting = null;
    }
  }
}
