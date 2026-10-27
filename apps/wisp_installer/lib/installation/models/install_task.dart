import 'dart:io';

import 'package:wisp_installer/navigation/shell.dart';

enum InstallTaskId {
  installCore,
  installEdgeWebView2,
  integrateOs,
  downloadJavaRuntime,
  downloadNewPipe,
  downloadInnerTubeX,
  downloadYtDlp,
}

String labelForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.installCore => 'Downloading App Core',
    InstallTaskId.installEdgeWebView2 =>
      'Installing Edge WebView2 (may take a while)',
    InstallTaskId.integrateOs => 'Integrating with OS',
    InstallTaskId.downloadJavaRuntime => 'Installing Java 21 Runtime (JVM)',
    InstallTaskId.downloadNewPipe => 'Installing NewPipeExtractor',
    InstallTaskId.downloadInnerTubeX => 'Installing InnerTubeX',
    InstallTaskId.downloadYtDlp => 'Installing YT-DLP + Node.js',
  };
}

String categoryForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.installCore => 'Install/Core',
    InstallTaskId.installEdgeWebView2 => 'Install/WebView2',
    InstallTaskId.integrateOs => 'Install/OS',
    InstallTaskId.downloadJavaRuntime => 'Install/Java',
    InstallTaskId.downloadNewPipe => 'Install/NewPipe',
    InstallTaskId.downloadInnerTubeX => 'Install/InnerTubeX',
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

  final needsJava = selected[InstallationComponent.JavaRuntime] == true ||
      selected[InstallationComponent.NewPipeExtractor] == true ||
      selected[InstallationComponent.InnerTubeX] == true;

  if (needsJava) {
    tasks.add(InstallTaskId.downloadJavaRuntime);
  }

  if (selected[InstallationComponent.NewPipeExtractor] == true) {
    tasks.add(InstallTaskId.downloadNewPipe);
  }
  if (selected[InstallationComponent.InnerTubeX] == true) {
    tasks.add(InstallTaskId.downloadInnerTubeX);
  }
  if (selected[InstallationComponent.YT_DLP] == true) {
    tasks.add(InstallTaskId.downloadYtDlp);
  }

  return tasks;
}
