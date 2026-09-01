import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:wisp_shared/models/youtube_engine.dart';
import 'package:wisp_ytdlp_manager/installer/ytdlp_installer.dart';
import 'package:wisp_ytdlp_manager/services/wisp_support_directory.dart';

class WispYtdlpManager implements YoutubeEngine {
  static final WispYtdlpManager _instance = WispYtdlpManager._internal();

  static const platform = MethodChannel('com.wizeshi.wisp_ytdlp_manager');

  late final WispSupportDirectory _supportDirectory;

  YoutubeEngineState _state = YoutubeEngineState.uninitialized;
  late final StreamController<YoutubeEngineState> _stateController;

  WispYtdlpManager._internal() {
    _supportDirectory = WispSupportDirectory();
    _stateController = StreamController<YoutubeEngineState>.broadcast();
  }

  factory WispYtdlpManager() {
    return _instance;
  }

  static WispYtdlpManager get instance => _instance;

  @override
  String get name => 'YT-DLP';

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

      // YT-DLP is not supported on iOS
      if (Platform.isIOS) {
        _setState(YoutubeEngineState.unavailable);
        return;
      }

      // On Android, binaries and dependent libraries are bundled in the plugin
      if (Platform.isAndroid) {
        _setState(YoutubeEngineState.ready);
        return;
      }

      // On desktop, check if already installed
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        if (await _isYtdlpInstalled()) {
          _setState(YoutubeEngineState.ready);
          return;
        }

        _setState(YoutubeEngineState.installing);

        final installer = YtDlpInstaller();
        try {
          await for (final progress in installer.installYtDlpAndNode()) {
            yield progress;
          }
          _setState(YoutubeEngineState.ready);
        } finally {
          await installer.cleanup();
        }
        return;
      }

      _setState(YoutubeEngineState.unavailable);
    } catch (e) {
      _setState(YoutubeEngineState.unavailable);
      rethrow;
    }
  }

  @override
  Future<String> getStreamUrl(String videoId, {Duration? timeout}) async {
    if (Platform.isAndroid) {
      return _getStreamUrlAndroid(videoId, timeout: timeout);
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _getStreamUrlDesktop(videoId, timeout: timeout);
    } else if (Platform.isIOS) {
      throw UnimplementedError('YT-DLP is not available on iOS');
    }

    throw UnimplementedError('Unsupported platform');
  }

  Future<String> _getStreamUrlAndroid(
    String videoId, {
    Duration? timeout,
  }) async {
    try {
      final url = await platform.invokeMethod<String>(
        'getStreamUrlYTDLPAndroid',
        {'videoId': videoId},
      );

      if (url == null || url.isEmpty) {
        throw Exception('No stream URL returned from YT-DLP');
      }

      return url;
    } on PlatformException catch (e) {
      throw Exception('YT-DLP error: ${e.message}');
    }
  }

  Future<String> _getStreamUrlDesktop(
    String videoId, {
    Duration? timeout,
  }) async {
    try {
      final supportDirectory = await _supportDirectory.get();
      final ytdlpPath = p.join(
        supportDirectory.path,
        'yt-dlp',
        _getYtDlpExecutable(),
      );
      final executable = await File(ytdlpPath).exists()
          ? ytdlpPath
          : _getYtDlpExecutable();

      final nodeDir = p.join(supportDirectory.path, 'node');
      final nodeBinDir = Platform.isWindows ? nodeDir : p.join(nodeDir, 'bin');

      final pathEnv = Platform.environment['PATH'] ?? '';
      final pathSeparator = Platform.isWindows ? ';' : ':';
      final updatedPath =
          '$nodeBinDir$pathSeparator$nodeDir$pathSeparator$pathEnv';

      final result = await Process.run(
        executable,
        [
          '-f',
          'bestaudio[ext=m4a]/bestaudio',
          '--get-url',
          '--no-playlist',
          '--js-runtimes',
          'node',
          'https://www.youtube.com/watch?v=$videoId',
        ],
        environment: {...Platform.environment, 'PATH': updatedPath},
      );

      if (result.exitCode != 0) {
        throw Exception('YT-DLP failed: ${result.stderr}');
      }

      final url = (result.stdout as String).trim();
      if (url.isEmpty) {
        throw Exception('No stream URL returned from YT-DLP');
      }

      return url;
    } catch (e) {
      throw Exception('YT-DLP error: $e');
    }
  }

  String _getYtDlpExecutable() {
    if (Platform.isWindows) {
      return 'yt-dlp.exe';
    }
    return 'yt-dlp';
  }

  /// Update yt-dlp to the latest version on Android
  Future<void> updateYtDlp() async {
    if (!Platform.isAndroid) {
      throw UnimplementedError(
        'YT-DLP update via plugin is only available on Android',
      );
    }

    try {
      await platform.invokeMethod<bool>('updateYtDlp');
    } on PlatformException catch (e) {
      throw Exception('YT-DLP update failed: ${e.message}');
    }
  }

  Future<bool> _isYtdlpInstalled() async {
    if (Platform.isAndroid) {
      return true;
    }

    bool ytdlpExecExists = false;
    bool nodeJsExists = false;

    try {
      final supportDirectory = await _supportDirectory.get();
      final ytdlpFile = File(
        p.join(supportDirectory.path, 'yt-dlp', _getYtDlpExecutable()),
      );
      ytdlpExecExists = await ytdlpFile.exists();
    } catch (e) {
      return false;
    }

    try {
      final supportDirectory = await _supportDirectory.get();
      final nodeJsBin = Directory(p.join(supportDirectory.path, 'node'));
      nodeJsExists = await nodeJsBin.exists();
    } catch (e) {
      return false;
    }

    return ytdlpExecExists && nodeJsExists;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
}
