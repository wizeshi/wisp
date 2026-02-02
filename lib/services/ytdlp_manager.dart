/// yt-dlp binary manager for desktop platforms
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'notification_service.dart';

class YtDlpManager {
  static final YtDlpManager instance = YtDlpManager._();

  YtDlpManager._();

  static const String _prefsLastUpdateKey = 'ytdlp_last_update_check';
  static const String _installFolderName = 'yt-dlp';
  static const String _binaryName = 'yt-dlp';
  static const String _windowsBinaryName = 'yt-dlp.exe';

  bool _sessionUpdateAttempted = false;
  Future<String?>? _ensureFuture;
  String? _resolvedPath;

  bool get _isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<String?> ensureReady({bool notifyOnFailure = false}) async {
    if (!_isDesktop) return null;
    if (_resolvedPath != null) return _resolvedPath;

    if (_ensureFuture != null) {
      return _ensureFuture;
    }

    _ensureFuture = _ensureReadyInternal(notifyOnFailure);
    final result = await _ensureFuture;
    _ensureFuture = null;
    return result;
  }

  Future<String?> _ensureReadyInternal(bool notifyOnFailure) async {
    try {
      final installPath = await _getInstallPath();
      final installedOk = await _ensureInstalledBinary(installPath);
      if (installedOk) {
        await _maybeUpdate(installPath);
        if (await _verifyExecutable(installPath)) {
          _resolvedPath = installPath;
          return installPath;
        }
      }

      if (await _verifyExecutable(_binaryName)) {
        _resolvedPath = _binaryName;
        return _binaryName;
      }

      if (notifyOnFailure) {
        await _notifyFailure();
      }
      return null;
    } catch (e) {
      logger.e('[yt-dlp] Failed to prepare binary', error: e);
      if (notifyOnFailure) {
        await _notifyFailure();
      }
      return null;
    }
  }

  Future<bool> _ensureInstalledBinary(String installPath) async {
    final file = File(installPath);
    if (await file.exists()) {
      if (await _verifyExecutable(installPath)) {
        return true;
      }
      logger.w('[yt-dlp] Existing binary failed verification, re-downloading');
    }

    try {
      await _downloadLatestBinary(installPath);
      return await _verifyExecutable(installPath);
    } catch (e) {
      logger.e('[yt-dlp] Download failed', error: e);
      return false;
    }
  }

  Future<void> _maybeUpdate(String installPath) async {
    if (_sessionUpdateAttempted) return;
    _sessionUpdateAttempted = true;

    if (!await _isUpdateDue()) return;

    try {
      logger.i('[yt-dlp] Checking for updates...');
      await _downloadLatestBinary(installPath);
      logger.i('[yt-dlp] ✓ Update complete');
    } catch (e) {
      logger.w('[yt-dlp] Update failed', error: e);
    } finally {
      await _recordUpdateAttempt();
    }
  }

  Future<bool> _isUpdateDue() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMillis = prefs.getInt(_prefsLastUpdateKey);
    if (lastMillis == null) return true;

    final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastMillis);
    return DateTime.now().difference(lastCheck) >= const Duration(days: 1);
  }

  Future<void> _recordUpdateAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastUpdateKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _downloadLatestBinary(String installPath) async {
    final assetName = await _getAssetName();
    final url = Uri.parse(
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/$assetName',
    );

    final installDir = await _getInstallDir();
    await installDir.create(recursive: true);

    final tempPath = '${installPath}.download';
    final tempFile = File(tempPath);

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    logger.i('[yt-dlp] Downloading $assetName...');

    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final sink = tempFile.openWrite();
      await response.pipe(sink);

      final finalFile = File(installPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }

      try {
        await tempFile.rename(installPath);
      } catch (_) {
        await tempFile.copy(installPath);
        await tempFile.delete();
      }

      await _ensureExecutablePermissions(installPath);
      logger.i('[yt-dlp] ✓ Installed to $installPath');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _ensureExecutablePermissions(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['+x', path]);
    } catch (e) {
      logger.w('[yt-dlp] Failed to set executable bit', error: e);
    }
  }

  Future<bool> _verifyExecutable(String path) async {
    try {
      final result = await Process.run(path, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<Directory> _getInstallDir() async {
    final appSupport = await getApplicationSupportDirectory();
    return Directory('${appSupport.path}/$_installFolderName');
  }

  Future<String> _getInstallPath() async {
    final dir = await _getInstallDir();
    final name = Platform.isWindows ? _windowsBinaryName : _binaryName;
    return '${dir.path}/$name';
  }

  Future<String> _getAssetName() async {
    if (Platform.isWindows) return _windowsBinaryName;
    if (Platform.isMacOS) return 'yt-dlp_macos';

    if (Platform.isLinux) {
      final arch = await _getMachineArch();
      if (arch.contains('aarch64') || arch.contains('arm64')) {
        return 'yt-dlp_linux_aarch64';
      }
      return 'yt-dlp_linux';
    }

    return _binaryName;
  }

  Future<String> _getMachineArch() async {
    try {
      final result = await Process.run('uname', ['-m']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim().toLowerCase();
      }
    } catch (_) {}
    return '';
  }

  Future<void> _notifyFailure() async {
    await NotificationService.instance.showAlert(
      id: 'yt-dlp-failure'.hashCode,
      title: 'yt-dlp unavailable',
      body: 'Failed to download or run yt-dlp. Streaming may be limited.',
    );
  }
}
