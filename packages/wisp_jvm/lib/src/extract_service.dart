import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

class JvmExtractService {
  Future<Directory> extractZipArchive({
    required File archiveFile,
    required Directory destinationDir,
  }) async {
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }

    final archivePath = archiveFile.path;
    final destPath = destinationDir.path;
    await Isolate.run(() => extractFileToDisk(archivePath, destPath));
    return destinationDir;
  }

  Future<Directory> extractTarGzArchive({
    required File archiveFile,
    required Directory destinationDir,
  }) async {
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }

    final archivePath = archiveFile.path;
    final destPath = destinationDir.path;
    await Isolate.run(() => extractFileToDisk(archivePath, destPath));
    return destinationDir;
  }
}

