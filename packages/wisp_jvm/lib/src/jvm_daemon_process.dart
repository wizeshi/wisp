import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Base wrapper for a long-running Java daemon child process.
class JvmDaemonProcess {
  final Process _process;
  final StreamController<String> _stdoutLines = StreamController<String>.broadcast();
  final StreamController<String> _stderrLines = StreamController<String>.broadcast();
  late final StreamSubscription<String> _stdoutSub;
  late final StreamSubscription<String> _stderrSub;
  bool _isTerminated = false;

  JvmDaemonProcess(this._process) {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      _stdoutLines.add,
      onError: _stdoutLines.addError,
      onDone: () => _stdoutLines.close(),
    );

    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      _stderrLines.add,
      onError: _stderrLines.addError,
      onDone: () => _stderrLines.close(),
    );

    unawaited(_process.exitCode.then((_) {
      _isTerminated = true;
    }));
  }

  Process get process => _process;
  Stream<String> get stdoutLines => _stdoutLines.stream;
  Stream<String> get stderrLines => _stderrLines.stream;
  Future<int> get exitCode => _process.exitCode;
  bool get isRunning => !_isTerminated;

  void writeLine(String line) {
    if (_isTerminated) {
      throw StateError('Cannot write to terminated JVM daemon process');
    }
    _process.stdin.writeln(line);
  }

  Future<void> shutdown({Duration timeout = const Duration(seconds: 3)}) async {
    if (_isTerminated) return;
    try {
      _process.kill(ProcessSignal.sigterm);
    } catch (_) {
      _process.kill();
    }

    try {
      await _process.exitCode.timeout(timeout);
    } catch (_) {
      _process.kill(ProcessSignal.sigkill);
    }

    _isTerminated = true;
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    if (!_stdoutLines.isClosed) await _stdoutLines.close();
    if (!_stderrLines.isClosed) await _stderrLines.close();
  }
}

