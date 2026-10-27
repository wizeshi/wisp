import 'dart:io';

import 'package:archive/archive_io.dart';

class JvmExtractService {
  Future<Directory> extractZipArchive({
    required File archiveFile,
    required Directory destinationDir,
  }) async {
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }

    await extractFileToDisk(archiveFile.path, destinationDir.path);
    return destinationDir;
  }

  Future<Directory> extractTarGzArchive({
    required File archiveFile,
    required Directory destinationDir,
  }) async {
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }

    final compressedBytes = await archiveFile.readAsBytes();
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(compressedBytes),
    );
    await extractArchiveToDisk(archive, destinationDir.path);
    return destinationDir;
  }
}

