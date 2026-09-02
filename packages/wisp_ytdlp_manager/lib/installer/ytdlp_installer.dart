import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:wisp_shared/models/youtube_engine.dart';
import 'package:wisp_ytdlp_manager/services/platform_info.dart';
import 'package:wisp_ytdlp_manager/services/wisp_support_directory.dart';
import 'package:wisp_ytdlp_manager/services/download_service.dart';
import 'package:wisp_ytdlp_manager/services/extract_service.dart';

class YtDlpInstaller {
  static const String _nodeVersion = 'v24.18.0';

  final WispSupportDirectory _supportDirectory = WispSupportDirectory();
  final DownloadService _downloadService = DownloadService();
  final ExtractService _extractService = ExtractService();

  final List<Directory> _workDirectories = [];

  /// Install YT-DLP and Node.js for desktop platforms
  /// Yields progress updates as installation proceeds
  Stream<EngineInstallProgress> installYtDlpAndNode() async* {
    final platform = PlatformInfo.current();
    final supportDirectory = await _supportDirectory.get();
    final ytDlpBinaryName = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
    final ytDlpFile = File(p.join(supportDirectory.path, 'yt-dlp', ytDlpBinaryName));
    final nodeDirectory = Directory(p.join(supportDirectory.path, 'node'));

    try {
      // Download yt-dlp
      yield const EngineInstallProgress('Downloading yt-dlp...');
      await ytDlpFile.parent.create(recursive: true);

      await for (final progress in _downloadWithProgress(
        url:
            'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp${platform.ytDlpAssetSuffix}',
        destination: ytDlpFile,
      )) {
        yield progress;
      }

      if (!Platform.isWindows) {
        await Process.run('chmod', ['755', ytDlpFile.path]);
      }

      // Download Node.js
      yield const EngineInstallProgress('Downloading Node.js...');
      final extension = platform.archiveExtension;
      File? nodeArchive;
      await for (final progress in _downloadToTemporaryFileWithProgress(
        name: 'Node.js $_nodeVersion',
        url:
            'https://nodejs.org/dist/$_nodeVersion/'
            'node-$_nodeVersion-${platform.nodeOsSlug}-${platform.nodeArchSlug}.$extension',
        extension: extension,
      )) {
        if (progress is File) {
          nodeArchive = progress;
        } else {
          yield progress as EngineInstallProgress;
        }
      }

      // Extract Node.js
      yield const EngineInstallProgress('Extracting Node.js...');
      if (nodeArchive != null) {
        final extractedNodeDirectory = Directory(
          p.join(nodeArchive.parent.path, 'node'),
        );

        if (extension == 'zip') {
          await _extractService.extractZipArchive(
            archiveFile: nodeArchive,
            destinationDir: extractedNodeDirectory,
          );
        } else {
          await _extractService.extractTarGzArchive(
            archiveFile: nodeArchive,
            destinationDir: extractedNodeDirectory,
          );
        }

        // Find and move Node.js
        yield const EngineInstallProgress('Installing Node.js...');
        final nodeHome = await _findDirectoryContaining(
          extractedNodeDirectory,
          Platform.isWindows ? 'node.exe' : 'bin/node',
        );
        await _replaceDirectory(nodeHome, nodeDirectory);
      }

      yield const EngineInstallProgress(
        'Installation complete',
        bytesReceived: 1,
        totalBytes: 1,
      );
    } finally {
      await cleanup();
    }
  }

  /// Download a file with progress reporting
  Stream<EngineInstallProgress> _downloadWithProgress({
    required String url,
    required File destination,
  }) async* {
    final progressController = StreamController<(int, int?)>();

    try {
      unawaited(
        _downloadService.download(
          url: url,
          destination: destination,
          onProgress: (received, total) {
            progressController.add((received, total));
          },
        ).then((_) => progressController.close()),
      );

      int? lastLoggedProgressPercent; // Reset progress logging for this download
      yield const EngineInstallProgress('Downloading...');

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

  /// Download to a temporary file with progress reporting
  Stream<dynamic> _downloadToTemporaryFileWithProgress({
    required String name,
    required String url,
    required String extension,
  }) async* {
    final directory = await Directory.systemTemp.createTemp('wisp_ytdlp_');
    _workDirectories.add(directory);
    final file = File(
      p.join(directory.path, '${name.replaceAll(' ', '_')}.$extension'),
    );

    final progressController = StreamController<(int, int?)>();

    try {
      unawaited(
        _downloadService.download(
          url: url,
          destination: file,
          onProgress: (received, total) {
            progressController.add((received, total));
          },
        ).then((_) => progressController.close()),
      );

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

  /// Find a directory containing a specific file
  Future<Directory> _findDirectoryContaining(
    Directory rootDir,
    String fileName,
  ) async {
    if (!await rootDir.exists()) {
      throw Exception('Directory does not exist: ${rootDir.path}');
    }

    // Check if the file is in root
    final fileInRoot = File(p.join(rootDir.path, fileName));
    if (await fileInRoot.exists()) {
      return rootDir;
    }

    // Check subdirectories
    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        if (await File(p.join(entity.path, fileName)).exists()) {
          return entity;
        }
      }
    }

    throw Exception(
      'Could not find "$fileName" in directory tree: ${rootDir.path}',
    );
  }

  /// Replace a directory by moving it to the destination, removing the old one
  Future<void> _replaceDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }

    destination.parent.createSync(recursive: true);

    try {
      await source.rename(destination.path);
    } catch (_) {
      // Fallback: copy then delete
      await _copyDirectory(source, destination);
      await source.delete(recursive: true);
    }
  }

  /// Recursively copy a directory
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    await for (final entity in source.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: source.path);
      final newPath = p.join(destination.path, relativePath);

      if (entity is Directory) {
        await Directory(newPath).create(recursive: true);
      } else if (entity is File) {
        await File(entity.path).copy(newPath);
      }
    }
  }

  /// Cleanup temporary directories
  Future<void> cleanup() async {
    for (final directory in _workDirectories) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    _workDirectories.clear();
  }
}
