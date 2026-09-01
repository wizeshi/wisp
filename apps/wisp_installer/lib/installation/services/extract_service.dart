import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class ExtractService {
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

  Future<Directory> findAppBundle(Directory root) async {
    final matches = <Directory>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! Directory) continue;
      if (!entity.path.endsWith('.app')) continue;
      if (p.basename(entity.path).startsWith('._')) continue;
      if (entity.path.contains(
        '${Platform.pathSeparator}__MACOSX${Platform.pathSeparator}',
      )) {
        continue;
      }
      matches.add(entity);
    }

    if (matches.isEmpty) {
      throw StateError('No .app bundle found in extracted archive.');
    }

    matches.sort((a, b) => a.path.length.compareTo(b.path.length));
    return matches.first;
  }
}
