enum YoutubeEngineState {
  uninitialized,
  checking,
  installing,
  updating,
  ready,
  degraded,
  unavailable,
}

class EngineInstallProgress {
  final String stage;
  final int? bytesReceived;
  final int? totalBytes;
  const EngineInstallProgress(
    this.stage, {
    this.bytesReceived,
    this.totalBytes,
  });
}

abstract class EngineException implements Exception {
  final String message;
  const EngineException(this.message);
}

abstract class YoutubeEngine {
  String get name;
  YoutubeEngineState get state;
  Stream<YoutubeEngineState> get stateChanges;

  Stream<EngineInstallProgress> ensureReady({Object additionalData});
  Future<String> getStreamUrl(String videoId, {Duration timeout});

  Future<void> dispose();
}
