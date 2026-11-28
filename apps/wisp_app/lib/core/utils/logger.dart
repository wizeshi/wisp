// Copyright © 2026 wizeshi

/// Centralized logging utility
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:logger/logger.dart' as l;
import 'package:path_provider/path_provider.dart';

class Logger {
  static final Logger _instance = Logger._internal();

  static const int _maxLogFiles = 15;
  static const Duration _maxLogAge = Duration(days: 7);

  File? logFile;
  IOSink? _sink;
  bool _initFailed = false;

  late final Future<void> _initFuture;

  Future<void> _writeQueue = Future.value();

  factory Logger() {
    return _instance;
  }

  Logger._internal() {
    _initFuture = _init();
  }

  /// Removes log files older than [maxAge] and keeps at most `maxFiles - 1`
  /// most recent files so a new session log stays within [maxFiles].
  @visibleForTesting
  static Future<void> pruneOldLogFiles(
    Directory logDir, {
    int maxFiles = _maxLogFiles,
    Duration maxAge = _maxLogAge,
    DateTime? now,
  }) async {
    if (!await logDir.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    final files = <({File file, DateTime modified})>[];

    await for (final entity in logDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';
      if (!name.startsWith('log_') || !name.endsWith('.txt')) continue;
      try {
        final modified = await entity.lastModified();
        if (modified.isBefore(cutoff)) {
          await entity.delete();
        } else {
          files.add((file: entity, modified: modified));
        }
      } catch (_) {}
    }

    final keepLimit = maxFiles > 1 ? maxFiles - 1 : 0;
    if (files.length > keepLimit) {
      files.sort((a, b) => b.modified.compareTo(a.modified));
      for (var i = keepLimit; i < files.length; i++) {
        try {
          await files[i].file.delete();
        } catch (_) {}
      }
    }
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

      await pruneOldLogFiles(logDir, now: startTime);

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
    } catch (_) {
      _initFailed = true;
    }
  }

  final _logger = l.Logger(
    level: kReleaseMode ? l.Level.info : l.Level.debug,
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
    _writeToLogFile(
      "[${time ?? getCurrentTime()}] [INFO]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}",
    );
  }

  void d(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kReleaseMode) return;
    _logger.d(message, error: error, stackTrace: stackTrace, time: time);
    _writeToLogFile(
      "[${time ?? getCurrentTime()}] [DEBUG]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}",
    );
  }

  void w(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.w(message, error: error, stackTrace: stackTrace, time: time);
    _writeToLogFile(
      "[${time ?? getCurrentTime()}] [WARN]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}",
    );
  }

  void e(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.e(message, error: error, stackTrace: stackTrace, time: time);
    _writeToLogFile(
      "[${time ?? getCurrentTime()}] [ERROR]: $message\n${error != null ? " Error: $error\n" : ""}${stackTrace != null ? "StackTrace: $stackTrace\n" : ""}",
    );
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
    if (_initFailed) return _writeQueue;
    _writeQueue = _writeQueue
        .then((_) async {
          await _initFuture;

          if (_initFailed || _sink == null) {
            return;
          }

          _sink!.write(data);
        })
        .catchError((_) {});

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
