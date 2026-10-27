import 'dart:async';
import 'dart:io';

import 'package:wisp_jvm/wisp_jvm.dart';
import 'package:wisp_shared/models/youtube_engine.dart';
import 'package:wisp_innertubex_manager/src/innertubex_backend.dart';
import 'package:wisp_innertubex_manager/src/installer/innertubex_installer.dart';

class WispInnerTubeXEngine implements YoutubeEngine {
  static final WispInnerTubeXEngine _instance = WispInnerTubeXEngine._internal();
  WispInnerTubeXEngine._internal() {
    _stateController = StreamController<YoutubeEngineState>.broadcast();
  }
  factory WispInnerTubeXEngine() => _instance;
  static WispInnerTubeXEngine get instance => _instance;

  final InnerTubeXBackend _backend = InnerTubeXBackend.instance;
  YoutubeEngineState _state = YoutubeEngineState.uninitialized;
  late final StreamController<YoutubeEngineState> _stateController;

  @override
  String get name => 'InnerTubeX';

  @override
  YoutubeEngineState get state => _state;

  @override
  Stream<YoutubeEngineState> get stateChanges => _stateController.stream;

  void _setState(YoutubeEngineState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  @override
  Stream<EngineInstallProgress> ensureReady({Object? additionalData}) async* {
    try {
      _setState(YoutubeEngineState.checking);

      if (Platform.isIOS) {
        _setState(YoutubeEngineState.unavailable);
        return;
      }

      if (Platform.isAndroid) {
        _setState(YoutubeEngineState.ready);
        return;
      }

      // 1. Ensure shared JVM is installed
      if (!await JvmRuntimeManager.instance.isInstalled()) {
        _setState(YoutubeEngineState.installing);
        yield* JvmRuntimeManager.instance.installJre();
      }

      // 2. Ensure InnerTubeX jar is available
      final jarFile = await _backend.resolveJarFile();
      if (!await jarFile.exists()) {
        _setState(YoutubeEngineState.installing);
        yield* InnerTubeXInstaller().installJarOnly();
      }

      // 3. Ensure daemon starts
      await _backend.ensureStarted();
      _setState(YoutubeEngineState.ready);
    } catch (e) {
      _setState(YoutubeEngineState.unavailable);
      rethrow;
    }
  }

  @override
  Future<String> getStreamUrl(String videoId, {Duration? timeout}) async {
    final res = await _backend.resolveStream(videoId);
    final url = res['url'] as String?;
    if (url == null || url.isEmpty) {
      throw EngineExceptionImpl('InnerTubeX returned empty stream URL for $videoId');
    }
    return url;
  }

  Future<Map<String, dynamic>> getStreamDetails(String videoId) async {
    return _backend.resolveStream(videoId);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _backend.shutdown();
  }
}

class EngineExceptionImpl extends EngineException {
  const EngineExceptionImpl(super.message);
}
