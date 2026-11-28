import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_newpipe_manager/services/newpipe_daemon_manager.dart';

class _FakeIOSink implements IOSink {
  final void Function(String line)? onLine;
  final Completer<void> _done = Completer<void>();

  _FakeIOSink({this.onLine});

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) {
    onLine?.call(object?.toString() ?? '');
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    onLine?.call(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    onLine?.call(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    onLine?.call(object?.toString() ?? '');
  }
}

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  late final _FakeIOSink _stdin;
  int killCalls = 0;

  _FakeProcess({void Function(String line)? onStdinLine}) {
    _stdin = _FakeIOSink(onLine: onStdinLine);
  }

  void emitStdoutLine(String line) {
    _stdout.add(utf8.encode('$line\n'));
  }

  void exitWith([int code = 0]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCalls++;
    exitWith(0);
    return true;
  }

  @override
  int get pid => 23456;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Stream<List<int>> get stdout => _stdout.stream;
}

void main() {
  group('NewPipeDaemonManager startup mutex and shutdown', () {
    test('concurrent getStreamUrl spawns only one JVM with -Xmx192m', () async {
      var startCalls = 0;
      List<String>? capturedArgs;
      late _FakeProcess fakeProcess;

      fakeProcess = _FakeProcess(
        onStdinLine: (line) {
          final req = json.decode(line) as Map<String, dynamic>;
          final id = req['id'] as String;
          final url = req['url'] as String;
          fakeProcess.emitStdoutLine(
            json.encode({'id': id, 'url': 'https://cdn.example/$url'}),
          );
        },
      );

      final manager = NewPipeDaemonManager.forTesting(
        javaExecutableResolver: () async => 'java',
        jarPathResolver: () async => '/tmp/newpipestreamextractor.jar',
        processStarter: (executable, arguments) async {
          startCalls++;
          capturedArgs = arguments;
          return fakeProcess;
        },
      );

      final results = await Future.wait([
        manager.getStreamUrl('vid1'),
        manager.getStreamUrl('vid2'),
        manager.getStreamUrl('vid3'),
      ]);

      expect(startCalls, 1);
      expect(capturedArgs, contains('-Xmx192m'));
      expect(manager.isRunning, isTrue);
      expect(results, [
        'https://cdn.example/https://www.youtube.com/watch?v=vid1',
        'https://cdn.example/https://www.youtube.com/watch?v=vid2',
        'https://cdn.example/https://www.youtube.com/watch?v=vid3',
      ]);

      await manager.shutdown();
      expect(manager.isRunning, isFalse);
      expect(fakeProcess.killCalls, greaterThanOrEqualTo(1));
    });

    test('shutdown fails pending requests promptly', () async {
      late _FakeProcess fakeProcess;
      fakeProcess = _FakeProcess();

      final manager = NewPipeDaemonManager.forTesting(
        javaExecutableResolver: () async => 'java',
        jarPathResolver: () async => '/tmp/newpipestreamextractor.jar',
        processStarter: (executable, arguments) async => fakeProcess,
      );

      final pending = manager.getStreamUrl('vid_pending');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final expectation = expectLater(
        pending,
        throwsA(isA<NewPipeDaemonException>()),
      );
      await manager.shutdown();
      await expectation;
      expect(manager.isRunning, isFalse);
    });
  });
}
