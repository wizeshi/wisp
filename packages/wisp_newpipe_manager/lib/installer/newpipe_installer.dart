import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wisp_jvm/wisp_jvm.dart';
import 'package:wisp_shared/models/youtube_engine.dart';

/// Handles installation of NewPipeStreamExtractor and Java runtime.
class NewPipeInstaller {
  late final JvmDownloadService _downloadService;
  late final WispSupportDirectory _wispSupportDirectory;

  NewPipeInstaller() {
    _downloadService = JvmDownloadService();
    _wispSupportDirectory = WispSupportDirectory();
  }

  /// Installs NewPipeStreamExtractor and Java 21 runtime, yielding progress updates.
  Stream<EngineInstallProgress> installNewPipeExtractor() async* {
    if (!await JvmRuntimeManager.instance.isInstalled()) {
      yield* JvmRuntimeManager.instance.installJre();
    }

    yield* installJarOnly();
  }

  /// Installs only the NewPipeStreamExtractor JAR, assuming Java 21 runtime is installed.
  Stream<EngineInstallProgress> installJarOnly() async* {
    const newPipeUrl =
        'https://github.com/wizeshi/NewPipeStreamExtractor/releases/latest/download/newpipestreamextractor.jar';
    final supportDirectory = await _wispSupportDirectory.get();
    final newPipeFile = File(
      p.join(supportDirectory.path, 'newpipe', 'newpipestreamextractor.jar'),
    );
    await newPipeFile.parent.create(recursive: true);

    yield const EngineInstallProgress('Downloading NewPipeStreamExtractor...');
    await for (final progress in _downloadWithProgress(newPipeUrl, newPipeFile)) {
      yield progress;
    }

    yield const EngineInstallProgress(
      'NewPipeStreamExtractor installation complete',
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

      int? lastLoggedProgressPercent;
      yield const EngineInstallProgress('Downloading NewPipeStreamExtractor...');

      await for (final (received, total) in progressController.stream) {
        if (total != null && total > 0) {
          final int currentProgressPercent =
              ((received * 100) ~/ total).clamp(0, 100);
          if (currentProgressPercent != lastLoggedProgressPercent) {
            lastLoggedProgressPercent = currentProgressPercent;
            yield EngineInstallProgress(
              'Downloading NewPipeStreamExtractor...',
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

  /// Cleans up temporary resources.
  Future<void> cleanup() async {}
}
