import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wisp_jvm/wisp_jvm.dart';
import 'package:wisp_shared/models/youtube_engine.dart';

/// Handles installation of InnerTubeXStreamExtractor and Java runtime.
class InnerTubeXInstaller {
  late final JvmDownloadService _downloadService;
  late final WispSupportDirectory _wispSupportDirectory;

  InnerTubeXInstaller() {
    _downloadService = JvmDownloadService();
    _wispSupportDirectory = WispSupportDirectory();
  }

  /// Installs InnerTubeXStreamExtractor and Java 21 runtime, yielding progress updates.
  Stream<EngineInstallProgress> installInnerTubeX() async* {
    if (!await JvmRuntimeManager.instance.isInstalled()) {
      yield* JvmRuntimeManager.instance.installJre();
    }

    yield* installJarOnly();
  }

  /// Installs only the InnerTubeXStreamExtractor JAR, assuming Java 21 runtime is installed.
  Stream<EngineInstallProgress> installJarOnly() async* {
    const innerTubeUrl =
        'https://github.com/wizeshi/InnerTubeXStreamExtractor/releases/latest/download/innertubex.jar';
    final supportDirectory = await _wispSupportDirectory.get();
    final jarFile = File(
      p.join(supportDirectory.path, 'innertubex', 'innertubex.jar'),
    );
    await jarFile.parent.create(recursive: true);

    yield const EngineInstallProgress('Downloading InnerTubeXStreamExtractor...');
    await for (final progress in _downloadWithProgress(innerTubeUrl, jarFile)) {
      yield progress;
    }

    yield const EngineInstallProgress(
      'InnerTubeXStreamExtractor installation complete',
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
      yield const EngineInstallProgress('Downloading InnerTubeXStreamExtractor...');

      await for (final (received, total) in progressController.stream) {
        if (total != null && total > 0) {
          final int currentProgressPercent =
              ((received * 100) ~/ total).clamp(0, 100);
          if (currentProgressPercent != lastLoggedProgressPercent) {
            lastLoggedProgressPercent = currentProgressPercent;
            yield EngineInstallProgress(
              'Downloading InnerTubeXStreamExtractor...',
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
