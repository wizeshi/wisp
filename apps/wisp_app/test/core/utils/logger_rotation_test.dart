import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/core/utils/logger.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wisp_logger_rotation_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('pruneOldLogFiles removes expired logs and enforces maxFiles cap', () async {
    final now = DateTime(2026, 6, 15, 12);

    // 2 expired log files (> 7 days old)
    for (var i = 0; i < 2; i++) {
      final f = File('${tempDir.path}/log_2026-06-01_$i.txt')
        ..writeAsStringSync('old');
      await f.setLastModified(now.subtract(Duration(days: 10 + i)));
    }

    // 5 recent log files (timestamps staggered 1..5 hours ago)
    final recentFiles = <File>[];
    for (var i = 0; i < 5; i++) {
      final f = File('${tempDir.path}/log_2026-06-15_$i.txt')
        ..writeAsStringSync('recent $i');
      await f.setLastModified(now.subtract(Duration(hours: 5 - i)));
      recentFiles.add(f);
    }

    // Non-log file should never be touched
    final unrelated = File('${tempDir.path}/other.txt')..writeAsStringSync('keep');

    await Logger.pruneOldLogFiles(
      tempDir,
      maxFiles: 4, // keeps max 3 newest before new session opens 4th
      maxAge: const Duration(days: 7),
      now: now,
    );

    final remainingNames = tempDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();

    expect(
      remainingNames,
      equals({
        'log_2026-06-15_2.txt',
        'log_2026-06-15_3.txt',
        'log_2026-06-15_4.txt',
        'other.txt',
      }),
    );
    expect(unrelated.existsSync(), isTrue);
  });
}
