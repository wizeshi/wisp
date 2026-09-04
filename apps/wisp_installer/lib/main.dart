import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp_assets/wisp_assets.dart';
import 'package:wisp_installer/navigation/shell.dart';
import 'package:wisp_installer/utils/logger.dart';
import 'package:wisp_installer/utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows && !await _isWindowsAdministrator()) {
    await _relaunchElevated();
    exit(0);
  }

  initializeWindowsCertificates();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(800, 600),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      logger.e("[Main] Failed to initialize window manager: $e");
    }
  }

  runApp(const WispInstallerApp());
}

Future<bool> _isWindowsAdministrator() async {
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r'''
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  exit 0
}
exit 1
''',
  ]);
  return result.exitCode == 0;
}

Future<void> _relaunchElevated() async {
  final exe = Platform.resolvedExecutable.replaceAll("'", "''");
  await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    "Start-Process -FilePath '$exe' -Verb RunAs | Out-Null",
  ]);
}

class WispInstallerApp extends StatelessWidget {
  const WispInstallerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wisp Installer',
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
