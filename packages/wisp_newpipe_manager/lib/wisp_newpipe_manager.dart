import "dart:async";
import "dart:io";
import "package:path/path.dart" as p;
import "package:wisp_newpipe_manager/services/android_extractor_delegate.dart";
import "package:wisp_shared/models/youtube_engine.dart";
import "package:wisp_newpipe_manager/installer/newpipe_installer.dart";
import "package:wisp_newpipe_manager/services/wisp_support_directory.dart";
import "package:wisp_newpipe_manager/services/newpipe_daemon_manager.dart";

class NewPipeManager implements YoutubeEngine {
  static final NewPipeManager _instance = NewPipeManager._internal();

  late final WispSupportDirectory _supportDirectory;

  YoutubeEngineState _state = YoutubeEngineState.uninitialized;
  late final StreamController<YoutubeEngineState> _stateController;

  NewPipeAndroidDelegate? androidDelegate;

  NewPipeManager._internal() {
    _supportDirectory = WispSupportDirectory();
    _stateController = StreamController<YoutubeEngineState>.broadcast();
  }

  factory NewPipeManager() {
    return _instance;
  }

  static NewPipeManager get instance => _instance;

  @override
  String get name => "NewPipe";

  @override
  YoutubeEngineState get state => _state;

  @override
  Stream<YoutubeEngineState> get stateChanges => _stateController.stream;

  @override
  Stream<EngineInstallProgress> ensureReady({Object? additionalData}) async* {

    try {
      _setState(YoutubeEngineState.checking);

      // NewPipe is not avaliable on iOS
      if (Platform.isIOS) {
        _setState(YoutubeEngineState.unavailable);
        return;
      }

      // It is avaliable on Android, through newpipeextractor_dart. Doesn't even need init. 
      if (Platform.isAndroid) {
        _setState(YoutubeEngineState.ready);
        return;
      }

      // Check if already installed
      if (await _isNewPipeInstalled()) {
        _setState(YoutubeEngineState.ready);
        return;
      }

      _setState(YoutubeEngineState.installing);

      final installer = NewPipeInstaller();
      try {
        await for (final progress in installer.installNewPipeExtractor()) {
          yield progress;
        }
        _setState(YoutubeEngineState.ready);
      } finally {
        await installer.cleanup();
      }
    } catch (e) {
      _setState(YoutubeEngineState.unavailable);
      rethrow;
    }
  }

  @override
  Future<String> getStreamUrl(String videoId, {Duration? timeout}) async {
    if (Platform.isAndroid) {
      if (androidDelegate == null) {
        throw StateError(
          "NewPipeAndroidDelegate must be provided on Android before calling getStreamUrl."
        );
      }
      return androidDelegate!.getStreamUrl(videoId, timeout: timeout);
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _getStreamUrlDesktop(videoId, timeout: timeout);
    } else if (Platform.isIOS) {
      throw UnimplementedError('NewPipe is not available on iOS');
    }
    throw UnimplementedError('Unsupported platform');
  }

  /// Gets stream URL on desktop by spawning a NewPipe daemon.
  Future<String> _getStreamUrlDesktop(String videoId, {Duration? timeout}) async {
    final daemon = NewPipeDaemonManager.instance;
    return daemon.getStreamUrl(videoId, timeout: timeout ?? const Duration(seconds: 20));
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await NewPipeDaemonManager.instance.shutdown();
  }

  /// Checks if NewPipe is already installed.
  Future<bool> _isNewPipeInstalled() async {
    bool newPipeDaemonExists = false;
    bool jdkExists = false;

    try {
      final supportDirectory = await _supportDirectory.get();
      final newPipeFile = File(
        p.join(supportDirectory.path, 'newpipe', 'newpipestreamextractor.jar'),
      );
      newPipeDaemonExists = await newPipeFile.exists();
    } catch (e) {
      return false;
    }

    try {
      final supportDirectory = await _supportDirectory.get();
      final jdkDir = Directory(
        p.join(supportDirectory.path, 'java'),
      );
      jdkExists = await jdkDir.exists();
    } catch (e) {
      return false;
    }

    return newPipeDaemonExists && jdkExists;
  }

  /// Updates the internal state and broadcasts the change.
  void _setState(YoutubeEngineState newState) {
    _state = newState;
    _stateController.add(newState);
  }
}
