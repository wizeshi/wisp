import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_innertubex_manager/wisp_innertubex_manager.dart';

class _FakeIOSink implements IOSink {
  final List<String> lines = [];
  final Completer<void> _done = Completer<void>();
  bool closed = false;

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
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) {
    lines.add(object?.toString() ?? '');
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    lines.add(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    lines.add(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    lines.add(object?.toString() ?? '');
  }
}

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final _FakeIOSink _stdin = _FakeIOSink();
  int killCalls = 0;

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
  int get pid => 12345;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Stream<List<int>> get stdout => _stdout.stream;
}

void main() {
  group('InnerTubeXBackend startup mutex and shutdown', () {
    late Directory tempDir;
    late File fakeJar;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wisp_innertubex_test_');
      fakeJar = File('${tempDir.path}/innertubexstreamextractor.jar')
        ..writeAsBytesSync([0x50, 0x4b]);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('concurrent ensureStarted spawns only one JVM with -Xmx192m', () async {
      var startCalls = 0;
      List<String>? capturedArgs;
      final fakeProcess = _FakeProcess();

      final backend = InnerTubeXBackend.forTesting(
        javaExecutableResolver: () async => 'java',
        jarFileResolver: () async => fakeJar,
        processStarter: (executable, arguments) async {
          startCalls++;
          capturedArgs = arguments;
          return fakeProcess;
        },
      );

      final f1 = backend.ensureStarted();
      final f2 = backend.ensureStarted();
      final f3 = backend.ensureStarted();

      // Wait until the process starter has run, then emit ready handshake.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fakeProcess.emitStdoutLine('{"status":"ready","port":48123}');

      await Future.wait([f1, f2, f3]);

      expect(startCalls, 1);
      expect(capturedArgs, contains('-Xmx192m'));
      expect(capturedArgs, contains('-jar'));
      expect(backend.isRunning, isTrue);
      expect(backend.localPort, 48123);

      await backend.shutdown();
      expect(backend.isRunning, isFalse);
      expect(backend.localPort, isNull);
      expect(fakeProcess.killCalls, greaterThanOrEqualTo(1));
    });
  });
}
