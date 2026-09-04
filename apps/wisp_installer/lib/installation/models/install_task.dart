import 'dart:io';

import 'package:wisp_installer/navigation/shell.dart';

enum InstallTaskId {
  installCore,
  installEdgeWebView2,
  integrateOs,
  downloadNewPipe,
  downloadYtDlp,
}

String labelForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.installCore => 'Downloading App Core',
    InstallTaskId.installEdgeWebView2 => 'Installing Edge WebView2 (may take a while)',
    InstallTaskId.integrateOs => 'Integrating with OS',
    InstallTaskId.downloadNewPipe => 'Installing NewPipeExtractor + Java',
    InstallTaskId.downloadYtDlp => 'Installing YT-DLP + Node.js',
  };
}

String categoryForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.installCore => 'Install/Core',
    InstallTaskId.installEdgeWebView2 => 'Install/WebView2',
    InstallTaskId.integrateOs => 'Install/OS',
    InstallTaskId.downloadNewPipe => 'Install/NewPipe',
    InstallTaskId.downloadYtDlp => 'Install/YT-DLP',
  };
}

List<InstallTaskId> buildTaskPlan(Map<InstallationComponent, bool> selected) {
  final tasks = <InstallTaskId>[
    InstallTaskId.installCore,
    InstallTaskId.integrateOs,
  ];

  if (Platform.isWindows &&
      selected[InstallationComponent.EdgeWebView2] == true) {
    tasks.add(InstallTaskId.installEdgeWebView2);
  }

  if (selected[InstallationComponent.NewPipeExtractor] == true) {
    tasks.add(InstallTaskId.downloadNewPipe);
  }
  if (selected[InstallationComponent.YT_DLP] == true) {
    tasks.add(InstallTaskId.downloadYtDlp);
  }

  return tasks;
}
