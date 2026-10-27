import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wisp_jvm/src/download_service.dart';
import 'package:wisp_jvm/src/extract_service.dart';
import 'package:wisp_jvm/src/platform_info.dart';
import 'package:wisp_jvm/src/wisp_support_directory.dart';
import 'package:wisp_shared/models/youtube_engine.dart';

class JvmRuntimeManager {
  JvmRuntimeManager._internal() {
    _downloadService = JvmDownloadService();
    _extractService = JvmExtractService();
    _supportDirectory = WispSupportDirectory();
  }

  static final JvmRuntimeManager _instance = JvmRuntimeManager._internal();
  static JvmRuntimeManager get instance => _instance;

  late final JvmDownloadService _downloadService;
  late final JvmExtractService _extractService;
  late final WispSupportDirectory _supportDirectory;

  Completer<void>? _installLock;

  Future<Directory> getJavaDirectory() async {
    final supportDir = await _supportDirectory.get();
    return Directory(p.join(supportDir.path, 'java'));
  }

  Future<String> getJavaExecutablePath() async {
    final javaDir = await getJavaDirectory();
    final platform = JvmPlatformInfo.current();

    // Check direct relative path
    final direct = File(p.join(javaDir.path, platform.javaExecutableRelativePath));
    if (await direct.exists()) {
      return direct.path;
    }

    // In case of macOS or un-nested contents, search dynamically
    final binName = Platform.isWindows ? 'java.exe' : 'java';
    await for (final entity in javaDir.list(recursive: true, followLinks: false)) {
      if (entity is File && p.basename(entity.path).toLowerCase() == binName) {
        return entity.path;
      }
    }

    throw StateError('Java executable not found in ${javaDir.path}');
  }

  Future<bool> isInstalled() async {
    try {
      final javaDir = await getJavaDirectory();
      if (!await javaDir.exists()) return false;
      final execPath = await getJavaExecutablePath();
      return await File(execPath).exists();
    } catch (_) {
      return false;
    }
  }

  Stream<EngineInstallProgress> installJre({bool force = false}) async* {
    if (!force && await isInstalled()) {
      yield const EngineInstallProgress('Java 21 runtime is already installed');
      return;
    }

    while (_installLock != null) {
      yield const EngineInstallProgress('Waiting for concurrent Java installation to finish...');
      await _installLock!.future;
      if (await isInstalled()) {
        yield const EngineInstallProgress('Java 21 runtime is ready');
        return;
      }
    }

    final lock = Completer<void>();
    _installLock = lock;

    final tempDirs = <Directory>[];

    try {
      final platform = JvmPlatformInfo.current();
      final javaDirectory = await getJavaDirectory();
      await javaDirectory.parent.create(recursive: true);

      final javaUrl = 'https://api.adoptium.net/v3/binary/latest/21/ga/'
          '${platform.javaOsSlug}/${platform.javaArchSlug}/jre/hotspot/normal/eclipse';

      yield EngineInstallProgress('Downloading Java 21 runtime from $javaUrl');

      final tempDir = await Directory.systemTemp.createTemp('wisp_java_');
      tempDirs.add(tempDir);

      final archiveFile = File(
        p.join(tempDir.path, 'java_21.${platform.javaArchiveExtension}'),
      );

      final progressController = StreamController<(int, int?)>();

      unawaited(_downloadService.download(
        url: javaUrl,
        destination: archiveFile,
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

      int? lastLoggedPercent;
      await for (final (received, total) in progressController.stream) {
        if (total != null && total > 0) {
          final percent = ((received * 100) ~/ total).clamp(0, 100);
          if (percent != lastLoggedPercent) {
            lastLoggedPercent = percent;
            yield EngineInstallProgress(
              'Downloading Java 21 runtime...',
              bytesReceived: received,
              totalBytes: total,
            );
          }
        }
      }

      yield const EngineInstallProgress('Installing Java 21 runtime...');

      final extractedDir = Directory(p.join(tempDir.path, 'extracted_java'));
      if (platform.javaArchiveExtension == 'zip') {
        await _extractService.extractZipArchive(
          archiveFile: archiveFile,
          destinationDir: extractedDir,
        );
      } else {
        await _extractService.extractTarGzArchive(
          archiveFile: archiveFile,
          destinationDir: extractedDir,
        );
      }

      final extractedJavaDir = await _findDirectoryContaining(
        extractedDir,
        platform.javaExecutableRelativePath,
      );

      final javaHome = Platform.isMacOS
          ? Directory(p.join(extractedJavaDir.path, 'Contents', 'Home'))
          : extractedJavaDir;

      await _replaceDirectory(javaHome, javaDirectory);

      yield const EngineInstallProgress(
        'Java 21 runtime installed successfully',
        bytesReceived: 1,
        totalBytes: 1,
      );
    } finally {
      for (final dir in tempDirs) {
        if (await dir.exists()) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
      }
      _installLock = null;
      lock.complete();
    }
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
}

