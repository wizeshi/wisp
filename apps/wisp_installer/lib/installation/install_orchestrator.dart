import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wisp_newpipe_manager/installer/newpipe_installer.dart';
import 'package:wisp_ytdlp_manager/installer/ytdlp_installer.dart';
import 'package:wisp_installer/installation/install_controller.dart';
import 'package:wisp_installer/installation/models/install_session.dart';
import 'package:wisp_installer/installation/models/install_task.dart';
import 'package:wisp_installer/installation/services/macos_app_installer.dart';

class InstallOrchestrator {
  InstallOrchestrator(this._controller);

  final InstallController _controller;
  final InstallSession _session = InstallSession();
  final MacOSAppInstaller _macOSAppInstaller = MacOSAppInstaller();
  final List<Directory> _componentWorkDirectories = [];

  Future<void> run() async {
    try {
      for (var i = 0; i < _controller.tasks.length; i++) {
        _controller.advanceToTask(i);

        switch (_controller.tasks[i]) {
          case InstallTaskId.installCore:
            await _installCore();
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

  // ---------------------------------------------------------------------
  // App core: now installed from the payload embedded in this installer
  // binary rather than downloaded from GitHub at run time.
  // ---------------------------------------------------------------------

  Future<void> _installCore() async {
    if (Platform.isMacOS) {
      await _installCoreMacOS();
      return;
    }

    if (Platform.isWindows) {
      await _installCoreWindows();
      return;
    }

    if (Platform.isLinux) {
      await _installCoreLinux();
      return;
    }

    throw UnsupportedError(
      'No embedded-payload install path defined for this platform.',
    );
  }

  Future<void> _installCoreMacOS() async {
    const category = 'Install/Core';

    final appBundle = resolveMacOSAppBundle();
    if (!await appBundle.exists()) {
      throw StateError(
        'Embedded app bundle not found at ${appBundle.path}. '
        'This installer build is missing its payload.',
      );
    }

    _session.appBundle = appBundle;
    _controller.setTaskProgress(1.0);
    _controller.log(category, 'Located embedded wisp.app.');
  }

  Future<void> _installCoreWindows() async {
    const category = 'Install/Core';

    final payloadDir = resolveWindowsPayloadDir();
    if (!await payloadDir.exists()) {
      throw StateError(
        'Embedded app payload not found at ${payloadDir.path}. '
        'This installer build is missing its payload.',
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
      'Installing wisp to ${installationDirectory.path}...',
    );

    if (await installationDirectory.exists()) {
      await installationDirectory.delete(recursive: true);
    }
    await _copyDirectoryRecursive(
      payloadDir,
      installationDirectory,
      onProgress: (copied, total) {
        _controller.logTaskProgress(category, copied, total);
      },
    );

    final executable = await _findFileNamed(installationDirectory, 'wisp.exe');
    _session.installedApp = installationDirectory;
    _session.installedExecutable = executable;
    _controller.setTaskProgress(1.0);
    _controller.log(
      category,
      'Installed wisp to ${installationDirectory.path}.',
    );
  }

  Future<void> _installCoreLinux() async {
    const category = 'Install/Core';

    final payloadDir = resolveLinuxPayloadDir();
    if (!await payloadDir.exists()) {
      throw StateError(
        'Embedded app payload not found at ${payloadDir.path}. '
        'Make sure this installer is being run from within its AppImage.',
      );
    }

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Could not determine the home directory.');
    }

    final installationDirectory = Directory(
      p.join(home, '.local', 'share', 'wisp'),
    );
    _controller.log(
      category,
      'Installing wisp to ${installationDirectory.path}...',
    );

    if (await installationDirectory.exists()) {
      await installationDirectory.delete(recursive: true);
    }
    await _copyDirectoryRecursive(
      payloadDir,
      installationDirectory,
      onProgress: (copied, total) {
        _controller.logTaskProgress(category, copied, total);
      },
    );

    final executable = await _findFileNamed(installationDirectory, 'wisp');
    await Process.run('chmod', ['+x', executable.path]);

    _session.installedApp = installationDirectory;
    _session.installedExecutable = executable;
    _controller.setTaskProgress(1.0);
    _controller.log(
      category,
      'Installed wisp to ${installationDirectory.path}.',
    );
  }

  // ---------------------------------------------------------------------
  // OS integration — unchanged in spirit, Linux now implemented for real
  // instead of simulated.
  // ---------------------------------------------------------------------

  Future<void> _integrateOs() async {
    if (Platform.isMacOS) {
      await _integrateOsMacOS();
      return;
    }

    if (Platform.isWindows) {
      await _integrateOsWindows();
      return;
    }

    if (Platform.isLinux) {
      await _integrateOsLinux();
      return;
    }

    throw UnsupportedError(
      'No OS integration path defined for this platform.',
    );
  }

  Future<void> _integrateOsMacOS() async {
    const category = 'Install/OS';
    final appBundle = _session.appBundle;

    if (appBundle == null) {
      throw StateError(
        'Cannot integrate with OS before App Core has been installed.',
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
        'Cannot integrate with OS before App Core has been installed.',
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

  Future<void> _integrateOsLinux() async {
    const category = 'Install/OS';
    final executable = _session.installedExecutable;

    if (executable == null) {
      throw StateError(
        'Cannot integrate with OS before App Core has been installed.',
      );
    }

    final home = Platform.environment['HOME']!;
    final applicationsDir = Directory(
      p.join(home, '.local', 'share', 'applications'),
    );
    await applicationsDir.create(recursive: true);

    _controller.log(category, 'Creating .desktop entry...');
    final desktopFile = File(p.join(applicationsDir.path, 'wisp.desktop'));
    await desktopFile.writeAsString('''
[Desktop Entry]
Type=Application
Name=Wisp
Exec=${executable.path}
Icon=wisp
Terminal=false
Categories=AudioVideo;Audio;Player;
''');
    _controller.setTaskProgress(0.5);

    _controller.log(category, 'Adding Start Menu entry...');
    // .desktop files under ~/.local/share/applications are picked up by
    // most Linux desktop environments' menus automatically; nothing
    // further to do here, but kept as a distinct log line to mirror the
    // Windows/step structure the UI already expects.
    _controller.setTaskProgress(1.0);

    _controller.setInstalledAppPath(executable.path);
    _controller.log(category, 'OS integration complete.');
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  Future<void> _copyDirectoryRecursive(
    Directory source,
    Directory destination, {
    void Function(int copied, int total)? onProgress,
  }) async {
    await destination.create(recursive: true);

    final entries = await source.list(recursive: true).toList();
    final files = entries.whereType<File>().toList();
    var copied = 0;

    for (final file in files) {
      final relativePath = p.relative(file.path, from: source.path);
      final destinationFile = File(p.join(destination.path, relativePath));
      await destinationFile.parent.create(recursive: true);
      await file.copy(destinationFile.path);

      copied++;
      onProgress?.call(copied, files.length);
    }
  }

  Future<File> _findFileNamed(Directory root, String name) async {
    final normalizedName = name.toLowerCase();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).toLowerCase() == normalizedName) {
        return entity;
      }
    }
    throw StateError('Installed payload did not contain $name.');
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

  /// Windows: EVB virtualizes a `payload/` folder placed next to the
  /// installer exe at pack time (see scripts/windows/build_installer.ps1).
  Directory resolveWindowsPayloadDir() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return Directory(p.join(exeDir, 'payload'));
  }
 
  /// macOS: the app bundle is copied into this installer's own
  /// Contents/Resources/ at packaging time (see
  /// scripts/macos/build_installer.sh). The installer executable itself
  /// lives at Wisp Installer.app/Contents/MacOS/wisp_installer, so
  /// Resources is one level up and over.
  Directory resolveMacOSAppBundle() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return Directory(
      p.join(exeDir, '..', 'Resources', 'wisp_app.app'),
    );
  }
 
  /// Linux: the AppImage runtime sets $APPDIR to the mount point of the
  /// image while it's running. The app payload was placed under
  /// usr/wisp_app_payload/ inside the AppDir at packaging time (see
  /// scripts/linux/build_installer.sh).
  Directory resolveLinuxPayloadDir() {
    final appDir = Platform.environment['APPDIR'];
    if (appDir == null || appDir.isEmpty) {
      throw StateError(
        'APPDIR is not set. This installer must be run from within its '
        'AppImage, not invoked as a bare binary.',
      );
    }
    return Directory(p.join(appDir, 'usr', 'wisp_app_payload'));
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
      _controller.log(
        category,
        'NewPipeExtractor and Java runtime installed successfully.',
      );
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