// Copyright © 2026 wizeshi

/// Centralized logging utility
library;

import 'dart:io';

import 'package:logger/logger.dart' as l;
import 'package:path_provider/path_provider.dart';

class Logger {
  static final Logger _instance = Logger._internal();

  File? logFile;
  IOSink? _sink;

  late final Future<void> _initFuture;

  Future<void> _writeQueue = Future.value();

  factory Logger() {
    return _instance;
  }

  Logger._internal() {
    _initFuture = _init();
  }

  Future<void> _init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFolderPath = '${dir.path}/logs';

      final startTime = DateTime.now();
      final startDate =
          "${startTime.year}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}";

      final logDir = Directory(logFolderPath);

      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final List<FileSystemEntity> existingLogs = await logDir
          .list()
          .where((file) => file is File && file.path.contains('log_$startDate'))
          .toList();

      final logIndex = existingLogs.length + 1;
      final logFilePath = '$logFolderPath/log_${startDate}_$logIndex.txt';

      logFile = File(logFilePath);

      if (!await logFile!.exists()) {
        await logFile!.create(recursive: true);
      }

      _sink = logFile!.openWrite(mode: FileMode.append);
    } catch (err) {
      print("Failed to initialize log file: $err");
    }
  }

  final _logger = l.Logger(
    printer: l.PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: false,
      dateTimeFormat: l.DateTimeFormat.onlyTime,
      noBoxingByDefault: true,
    ),
  );

  void i(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.i(message, error: error, stackTrace: stackTrace, time: time);
    _writeToLogFile("[${time ?? getCurrentTime()}] [INFO]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}");
  }

  void d(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.d(message, error: error, stackTrace: stackTrace, time: time);
    _writeToLogFile("[${time ?? getCurrentTime()}] [DEBUG]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}");
  }

  void w(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.w(message, error: error, stackTrace: stackTrace, time: time);
    _writeToLogFile("[${time ?? getCurrentTime()}] [WARN]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}");
  }

  void e(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.e(message, error: error, stackTrace: stackTrace, time: time);
    _writeToLogFile("[${time ?? getCurrentTime()}] [ERROR]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}");
  }

  String getCurrentTime() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  }

  /// Queues [data] to be written to the log file. Calls are chained
  /// onto [_writeQueue] so that, no matter how fast they arrive, each
  /// write completes fully before the next one starts — and any calls
  /// made before initialization finishes are simply queued behind it
  /// rather than dropped.
  Future<void> _writeToLogFile(String data) {
    _writeQueue = _writeQueue.then((_) async {
      await _initFuture;

      if (_sink == null) {
        throw Exception("Log file is not initialized");
      }

      _sink!.write(data);
    }).catchError((err) {
      print("Failed to write to log file: $err");
    });

    return _writeQueue;
  }

  /// Flushes and closes the underlying sink. Call this on app
  /// shutdown to make sure buffered log lines are actually persisted
  /// to disk before the process exits.
  Future<void> close() async {
    await _writeQueue;
    await _sink?.flush();
    await _sink?.close();
  }
}

final logger = Logger();