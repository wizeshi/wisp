
import 'package:wisp_shared/models/youtube_engine.dart';

import 'wisp_ytdlp_manager_platform_interface.dart';

/* class WispYtdlpManager {
  Future<String?> getPlatformVersion() {
    return WispYtdlpManagerPlatform.instance.getPlatformVersion();
  }
} */

class WispYtdlpManager implements YoutubeEngine {
  @override
  Future<void> dispose() {
    // TODO: implement dispose
    throw UnimplementedError();
  }

  @override
  Stream<EngineInstallProgress> ensureReady({Object? additionalData}) {
    // TODO: implement ensureReady
    throw UnimplementedError();
  }

  @override
  Future<String> getStreamUrl(String videoId, {Duration? timeout}) {
    // TODO: implement getStreamUrl
    throw UnimplementedError();
  }

  @override
  // TODO: implement name
  String get name => throw UnimplementedError();

  @override
  // TODO: implement state
  YoutubeEngineState get state => throw UnimplementedError();

  @override
  // TODO: implement stateChanges
  Stream<YoutubeEngineState> get stateChanges => throw UnimplementedError();

}