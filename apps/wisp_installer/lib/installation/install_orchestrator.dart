import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wisp_newpipe_manager/installer/newpipe_installer.dart';
import 'package:wisp_ytdlp_manager/installer/ytdlp_installer.dart';
import 'package:wisp_installer/installation/install_controller.dart';
import 'package:wisp_installer/installation/models/install_session.dart';
import 'package:wisp_installer/installation/models/install_task.dart';
import 'package:wisp_installer/installation/services/download_service.dart';
import 'package:wisp_installer/installation/services/extract_service.dart';
import 'package:wisp_installer/installation/services/macos_app_installer.dart';
import 'package:wisp_installer/installation/services/platform_info.dart';

class InstallOrchestrator {
  InstallOrchestrator(this._controller);

  final InstallController _controller;
  final InstallSession _session = InstallSession();
  final DownloadService _downloadService = DownloadService();
  final ExtractService _extractService = ExtractService();
  final MacOSAppInstaller _macOSAppInstaller = MacOSAppInstaller();
  final List<Directory> _componentWorkDirectories = [];

  Future<void> run() async {
    try {
      for (var i = 0; i < _controller.tasks.length; i++) {
        _controller.advanceToTask(i);

        switch (_controller.tasks[i]) {
          case InstallTaskId.downloadCore:
            await _downloadCore();
          case InstallTaskId.extractCore:
            await _extractCore();
          case InstallTaskId.integrateOs:
            await _integrateOs();
          case InstallTaskId.downloadNewPipe:
            await _installNewPipeExtractor();
          case InstallTaskId.downloadYtDlp:
            await _installYtDlpAndNode();
        }
      }
    } finally {
      await _session.cleanup();
      for (final directory in _componentWorkDirectories) {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
      _componentWorkDirectories.clear();
    }
  }

  Future<void> _downloadCore() async {
    const category = 'Install/Core';
    final platform = PlatformInfo.current();
    final downloadUrl = platform.downloadUrl;

    _controller.log(category, 'Starting download for App Core...');
    _controller.log(
      category,
      'Got download URL from GitHub for ${platform.displayOs} | ${platform.displayArch}',
    );
    _controller.log(category, 'URL: $downloadUrl');

    _session.workDir = await Directory(
      p.join(
        Directory.systemTemp.path,
        'wisp_installer_${DateTime.now().millisecondsSinceEpoch}',
      ),
    ).create(recursive: true);

    _session.archiveFile = File(
      p.join(_session.workDir!.path, platform.releaseAssetName),
    );

    await _downloadService.download(
      url: downloadUrl,
      destination: _session.archiveFile!,
      onProgress: (received, total) {
        _controller.logTaskProgress(category, received, total);
      },
    );

    _controller.setTaskProgress(1.0);
    _controller.log(category, 'App Core download complete.');
  }

  Future<void> _extractCore() async {
    if (Platform.isMacOS) {
      await _extractCoreMacOS();
      return;
    }

    if (Platform.isWindows) {
      await _extractCoreWindows();
      return;
    }

    await _simulateExtractCore();
  }

  Future<void> _integrateOs() async {
    if (Platform.isMacOS) {
      await _integrateOsMacOS();
      return;
    }

    if (Platform.isWindows) {
      await _integrateOsWindows();
      return;
    }

    await _simulateIntegrateOs();
  }

  Future<void> _extractCoreMacOS() async {
    const category = 'Install/Core';
    final archiveFile = _session.archiveFile;
    final workDir = _session.workDir;

    if (archiveFile == null || workDir == null) {
      throw StateError(
        'Cannot extract App Core before it has been downloaded.',
      );
    }

    _controller.log(category, 'Extracting App Core archive...');

    final extractDir = Directory(p.join(workDir.path, 'extracted'));
    await _extractService.extractZipArchive(
      archiveFile: archiveFile,
      destinationDir: extractDir,
    );

    _session.appBundle = await _extractService.findAppBundle(extractDir);
    _controller.setTaskProgress(1.0);
    _controller.log(
      category,
      'Extracted ${_session.appBundle!.path.split(Platform.pathSeparator).last}.',
    );
  }

  Future<void> _integrateOsMacOS() async {
    const category = 'Install/OS';
    final appBundle = _session.appBundle;

    if (appBundle == null) {
      throw StateError(
        'Cannot integrate with OS before App Core has been extracted.',
      );
    }

    _controller.log(category, 'Copying wisp to Applications folder...');
    _controller.setTaskProgress(0.5);

    final installedApp = await _macOSAppInstaller.installToApplications(
      appBundle,
    );
    _session.installedApp = installedApp;
    _controller.setInstalledAppPath(installedApp.path);

    _controller.setTaskProgress(1.0);
    _controller.log(category, 'Installed to ${installedApp.path}.');
    _controller.log(category, 'OS integration complete.');
  }

  Future<void> _integrateOsWindows() async {
    const category = 'Install/OS';
    final installedApp = _session.installedApp;
    final executable = _session.installedExecutable;

    if (installedApp == null || executable == null) {
      throw StateError(
        'Cannot integrate with OS before App Core has been extracted.',
      );
    }

    _controller.log(category, 'Creating desktop shortcut...');
    await _createWindowsShortcut(
      directoryExpression:
          '[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)',
      executable: executable,
      workingDirectory: installedApp,
    );
    _controller.setTaskProgress(0.5);

    _controller.log(category, 'Adding Start Menu entry...');
    await _createWindowsShortcut(
      directoryExpression:
          "Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::StartMenu)) 'Programs'",
      executable: executable,
      workingDirectory: installedApp,
    );

    _controller.setInstalledAppPath(executable.path);
    _controller.setTaskProgress(1.0);
    _controller.log(category, 'OS integration complete.');
  }

  Future<void> _extractCoreWindows() async {
    const category = 'Install/Core';
    final archiveFile = _session.archiveFile;

    if (archiveFile == null) {
      throw StateError(
        'Cannot extract App Core before it has been downloaded.',
      );
    }

    final programFiles =
        Platform.environment['ProgramW6432'] ??
        Platform.environment['ProgramFiles'];
    if (programFiles == null || programFiles.isEmpty) {
      throw StateError('Could not determine the Program Files directory.');
    }

    final installationDirectory = Directory(p.join(programFiles, 'wisp'));
    _controller.log(
      category,
      'Extracting App Core to ${installationDirectory.path}...',
    );

    if (await installationDirectory.exists()) {
      await installationDirectory.delete(recursive: true);
    }
    await _extractService.extractZipArchive(
      archiveFile: archiveFile,
      destinationDir: installationDirectory,
    );

    final executable = await _findFileNamed(installationDirectory, 'wisp.exe');
    _session.installedApp = installationDirectory;
    _session.installedExecutable = executable;
    _controller.setTaskProgress(1.0);
    _controller.log(
      category,
      'Extracted wisp to ${installationDirectory.path}.',
    );
  }

  Future<File> _findFileNamed(Directory root, String name) async {
    final normalizedName = name.toLowerCase();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).toLowerCase() == normalizedName) {
        return entity;
      }
    }
    throw StateError('Extracted archive did not contain $name.');
  }

  Future<void> _createWindowsShortcut({
    required String directoryExpression,
    required File executable,
    required Directory workingDirectory,
  }) async {
    final targetPath = _powerShellSingleQuote(executable.path);
    final workingPath = _powerShellSingleQuote(workingDirectory.path);
    final script =
        '''
\$directory = $directoryExpression
[IO.Directory]::CreateDirectory(\$directory) | Out-Null
\$shell = New-Object -ComObject WScript.Shell
\$shortcut = \$shell.CreateShortcut((Join-Path \$directory 'wisp.lnk'))
\$shortcut.TargetPath = '$targetPath'
\$shortcut.WorkingDirectory = '$workingPath'
\$shortcut.IconLocation = '$targetPath,0'
\$shortcut.Save()
''';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell',
        const [],
        'Failed to create wisp shortcut: ${result.stderr}',
        result.exitCode,
      );
    }
  }

  String _powerShellSingleQuote(String value) => value.replaceAll("'", "''");

  Future<void> _simulateExtractCore() async {
    const category = 'Install/Core';

    _controller.log(category, 'Extracting App Core archive...');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    for (var step = 1; step <= 5; step++) {
      _controller.setTaskProgress(step / 5);
      _controller.log(category, 'Extracted $step/5 files...');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    _controller.log(category, 'App Core extracted successfully.');
  }

  Future<void> _simulateIntegrateOs() async {
    const category = 'Install/OS';

    _controller.log(category, 'Integrating with operating system...');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (Platform.isWindows) {
      _controller.log(category, 'Creating desktop shortcut...');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _controller.setTaskProgress(0.5);
      _controller.log(category, 'Adding Start Menu entry...');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } else if (Platform.isLinux) {
      _controller.log(category, 'Creating .desktop entry...');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _controller.setTaskProgress(0.5);
      _controller.log(category, 'Adding Start Menu entry...');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    _controller.setTaskProgress(1.0);
    _controller.log(category, 'OS integration complete.');
  }

  Future<void> _installNewPipeExtractor() async {
    const category = 'Install/NewPipe';
    
    final installer = NewPipeInstaller();
    try {
      await for (final progress in installer.installNewPipeExtractor()) {
        _controller.log(category, progress.stage);
        
        if (progress.totalBytes != null && progress.totalBytes! > 0) {
          _controller.logTaskProgress(
            category,
            progress.bytesReceived ?? 0,
            progress.totalBytes,
          );
        }
      }
      _controller.setTaskProgress(1.0);
      _controller.log(category, 'NewPipeExtractor and Java runtime installed successfully.');
    } finally {
      await installer.cleanup();
    }
  }

  Future<void> _installYtDlpAndNode() async {
    const category = 'Install/YT-DLP';

    final installer = YtDlpInstaller();
    try {
      await for (final progress in installer.installYtDlpAndNode()) {
        _controller.log(category, progress.stage);

        if (progress.totalBytes != null && progress.totalBytes! > 0) {
          _controller.logTaskProgress(
            category,
            progress.bytesReceived ?? 0,
            progress.totalBytes,
          );
        }
      }
      _controller.setTaskProgress(1.0);
      _controller.log(category, 'yt-dlp and Node.js installed successfully.');
    } finally {
      await installer.cleanup();
    }
  }
}
