import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wisp_shared/models/youtube_engine.dart';
import 'package:wisp_newpipe_manager/services/download_service.dart';
import 'package:wisp_newpipe_manager/services/extract_service.dart';
import 'package:wisp_newpipe_manager/services/platform_info.dart';
import 'package:wisp_newpipe_manager/services/wisp_support_directory.dart';

/// Handles installation of NewPipeStreamExtractor and Java runtime.
class NewPipeInstaller {
  late final DownloadService _downloadService;
  late final ExtractService _extractService;
  late final WispSupportDirectory _wispSupportDirectory;
  final List<Directory> _componentWorkDirectories = [];

  NewPipeInstaller() {
    _downloadService = DownloadService();
    _extractService = ExtractService();
    _wispSupportDirectory = WispSupportDirectory();
  }

  /// Installs NewPipeStreamExtractor and Java 21 runtime, yielding progress updates.
  Stream<EngineInstallProgress> installNewPipeExtractor() async* {
    const newPipeUrl =
        'https://github.com/wizeshi/NewPipeStreamExtractor/releases/latest/download/newpipestreamextractor.jar';
    final platform = PlatformInfo.current();
    final supportDirectory = await _wispSupportDirectory.get();
    final javaDirectory = Directory(p.join(supportDirectory.path, 'java'));
    final newPipeFile = File(
      p.join(supportDirectory.path, 'newpipe', 'newpipestreamextractor.jar'),
    );
    await newPipeFile.parent.create(recursive: true);

    final javaUrl = 'https://api.adoptium.net/v3/binary/latest/21/ga/'
          '${platform.javaOsSlug}/${platform.javaArchSlug}/jre/hotspot/normal/eclipse';

    yield EngineInstallProgress('Downloading Java 21 runtime from $javaUrl');
    
    File? javaArchive;
    await for (final progress in _downloadToTemporaryFileWithProgress(
      name: 'Java 21 runtime',
      url: javaUrl,
      extension: platform.javaArchiveExtension,
    )) {
      if (progress is File) {
        javaArchive = progress;
      } else {
        yield progress as EngineInstallProgress;
      }
    }

    yield EngineInstallProgress('Installing Java 21 runtime...');
    if (javaArchive != null) {
      await _installJavaRuntime(javaArchive, javaDirectory, platform);
    }

    yield EngineInstallProgress('Downloading NewPipeStreamExtractor...');
    await for (final progress in _downloadWithProgress(newPipeUrl, newPipeFile)) {
      yield progress;
    }

    yield EngineInstallProgress(
      'Installation complete',
      bytesReceived: 1,
      totalBytes: 1,
    );
  }

  /// Downloads a file and yields progress updates.
  Stream<EngineInstallProgress> _downloadWithProgress(
    String url,
    File destination,
  ) async* {
    final progressController = StreamController<(int, int?)>();
    
    try {
      await destination.parent.create(recursive: true);
      unawaited(_downloadService.download(
        url: url,
        destination: destination,
        onProgress: (received, total) {
          progressController.add((received, total));
        },
      ).then<void>(
        (_) => progressController.close(),
        onError: (Object error, StackTrace stackTrace) {
          progressController.addError(error, stackTrace);
          return progressController.close();
        },
      ));

      int? lastLoggedProgressPercent; // Reset progress logging for this download
      yield EngineInstallProgress('Downloading...');

      await for (final (received, total) in progressController.stream) {
        if (total != null && total > 0) {
          int currentProgressPercent = ((received * 100) ~/ total).clamp(0, 100);
          // Only log each percent increment once to avoid flooding the logs with messages.
          if (currentProgressPercent != lastLoggedProgressPercent) {
            lastLoggedProgressPercent = currentProgressPercent;
            yield EngineInstallProgress(
              'Downloading...',
              bytesReceived: received,
              totalBytes: total,
            );
          }
        }
      }
    } finally {
      await progressController.close();
    }
  }

  /// Downloads a file to a temporary location and yields progress updates.
  /// Yields progress updates and finally yields the File itself.
  Stream<dynamic> _downloadToTemporaryFileWithProgress({
    required String name,
    required String url,
    required String extension,
  }) async* {
    final directory = await Directory.systemTemp.createTemp('wisp_component_');
    _componentWorkDirectories.add(directory);
    yield EngineInstallProgress("Created temporary directory: ${directory.path.split("\\").last}");
    final file = File(
      p.join(directory.path, '${name.replaceAll(' ', '_')}.$extension'),
    );

    final progressController = StreamController<(int, int?)>();
    
    try {
      unawaited(_downloadService.download(
        url: url,
        destination: file,
        onProgress: (received, total) {
          progressController.add((received, total));
        },
      ).then<void>(
        (_) => progressController.close(),
        onError: (Object error, StackTrace stackTrace) {
          progressController.addError(error, stackTrace);
          return progressController.close();
        },
      ));
  
      int? lastLoggedProgressPercent; // Reset progress logging for this download
      yield EngineInstallProgress('Downloading $name...');

      await for (final (received, total) in progressController.stream) {
        if (total != null && total > 0) {
          int currentProgressPercent = ((received * 100) ~/ total).clamp(0, 100);
          // Only log each percent increment once to avoid flooding the logs with messages.
          if (currentProgressPercent != lastLoggedProgressPercent) {
            lastLoggedProgressPercent = currentProgressPercent;
            yield EngineInstallProgress(
              'Downloading $name...',
              bytesReceived: received,
              totalBytes: total,
            );
          }
        }
      }
      
      yield file;
    } finally {
      await progressController.close();
    }
  }

  Future<void> _installJavaRuntime(
    File archive,
    Directory destination,
    PlatformInfo platform,
  ) async {
    final extractedDirectory = Directory(p.join(archive.parent.path, 'java'));

    if (platform.javaArchiveExtension == 'zip') {
      await _extractService.extractZipArchive(
        archiveFile: archive,
        destinationDir: extractedDirectory,
      );
    } else {
      await _extractService.extractTarGzArchive(
        archiveFile: archive,
        destinationDir: extractedDirectory,
      );
    }

    final extractedJavaDirectory = await _findDirectoryContaining(
      extractedDirectory,
      Platform.isMacOS
          ? 'Contents/Home/bin/java'
          : (Platform.isWindows ? 'bin/java.exe' : 'bin/java'),
    );
    final javaHome = Platform.isMacOS
        ? Directory(p.join(extractedJavaDirectory.path, 'Contents', 'Home'))
        : extractedJavaDirectory;
    await _replaceDirectory(javaHome, destination);
  }

  Future<Directory> _findDirectoryContaining(
    Directory root,
    String relativePath,
  ) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! Directory) continue;
      if (await File(p.join(entity.path, relativePath)).exists()) return entity;
    }
    throw StateError('Extracted archive did not contain $relativePath.');
  }

  Future<void> _replaceDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
    await source.rename(destination.path);
  }

  /// Cleans up temporary directories created during installation.
  Future<void> cleanup() async {
    for (final directory in _componentWorkDirectories) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    _componentWorkDirectories.clear();
  }
}
