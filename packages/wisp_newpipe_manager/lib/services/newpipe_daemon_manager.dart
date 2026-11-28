/// Manages the long-running NewPipeExtractor Java daemon
/// used to resolve YouTube stream URLs on desktop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:wisp_jvm/wisp_jvm.dart';

typedef NewPipeProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

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
  NewPipeDaemonManager._internal({
    NewPipeProcessStarter? processStarter,
    Future<String> Function()? javaExecutableResolver,
    Future<String> Function()? jarPathResolver,
  })  : _processStarter = processStarter ?? Process.start,
        _javaExecutableResolver =
            javaExecutableResolver ?? JvmRuntimeManager.instance.getJavaExecutablePath,
        _jarPathResolver = jarPathResolver ?? _defaultJarPath;

  @visibleForTesting
  factory NewPipeDaemonManager.forTesting({
    NewPipeProcessStarter? processStarter,
    Future<String> Function()? javaExecutableResolver,
    Future<String> Function()? jarPathResolver,
  }) {
    return NewPipeDaemonManager._internal(
      processStarter: processStarter,
      javaExecutableResolver: javaExecutableResolver,
      jarPathResolver: jarPathResolver,
    );
  }

  static final NewPipeDaemonManager instance = NewPipeDaemonManager._internal();

  static const List<String> defaultJvmArgs = [
    '-Xmx192m',
    '-Djava.net.preferIPv6Addresses=true',
  ];

  final NewPipeProcessStarter _processStarter;
  final Future<String> Function() _javaExecutableResolver;
  final Future<String> Function() _jarPathResolver;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _idCounter = 0;
  Completer<void>? _starting;

  bool get isRunning => _process != null;

  static Future<String> _defaultJarPath() async {
    final supportDir = await WispSupportDirectory().get();
    return p.join(supportDir.path, 'newpipe', 'newpipestreamextractor.jar');
  }

  Future<String> _javaExecutable() async {
    return _javaExecutableResolver();
  }

  Future<String> _jarPath() => _jarPathResolver();

  /// Starts the daemon if it isn't already running. Concurrent callers block
  /// until startup is complete or fails.
  Future<void> _ensureStarted() async {
    if (_process != null) return;

    final existing = _starting;
    if (existing != null) {
      return existing.future;
    }

    final starting = Completer<void>();
    starting.future.ignore();
    _starting = starting;

    try {
      final javaExec = await _javaExecutable();
      final jar = await _jarPath();

      final process = await _processStarter(
        javaExec,
        [...defaultJvmArgs, '-jar', jar],
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
          if (completer != null && !completer.isCompleted) {
            completer.complete(response);
          }
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
        if (identical(_process, process)) {
          _process = null;
          unawaited(_stdoutSub?.cancel());
          _stdoutSub = null;
          unawaited(_stderrSub?.cancel());
          _stderrSub = null;
          for (final completer in _pending.values) {
            if (!completer.isCompleted) {
              completer.completeError(
                NewPipeDaemonException('NewPipe daemon exited unexpectedly'),
              );
            }
          }
          _pending.clear();
        }
        if (identical(_starting, starting)) {
          _starting = null;
        }
      }));

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

    if (response['error'] != null) {
      throw NewPipeDaemonException(
        'daemon error for video $videoId: ${response['error']}',
      );
    }

    final audioUrl = response['url'] as String?;
    if (audioUrl == null || audioUrl.isEmpty) {
      throw NewPipeDaemonException(
        'daemon returned no stream URL for video $videoId',
      );
    }

    return audioUrl;
  }

  /// Shuts down the running daemon process, if any. Safe to call when already stopped.
  Future<void> shutdown() async {
    final pendingStartup = _starting;
    _starting = null;
    if (pendingStartup != null && !pendingStartup.isCompleted) {
      pendingStartup.completeError(
        NewPipeDaemonException('NewPipe daemon shut down during startup'),
      );
    }

    final process = _process;
    _process = null;

    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          NewPipeDaemonException('NewPipe daemon shut down'),
        );
      }
    }
    _pending.clear();

    if (process == null) return;

    try {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Best-effort shutdown; ignore timeouts or signals already delivered
    }
  }
}
