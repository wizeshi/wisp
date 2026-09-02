import 'package:wisp_installer/navigation/shell.dart';

enum InstallTaskId {
  installCore,
  integrateOs,
  downloadNewPipe,
  downloadYtDlp,
}

String labelForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.installCore => 'Downloading App Core',
    InstallTaskId.integrateOs => 'Integrating with OS',
    InstallTaskId.downloadNewPipe => 'Installing NewPipeExtractor + Java',
    InstallTaskId.downloadYtDlp => 'Installing YT-DLP + Node.js',
  };
}

String categoryForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.installCore => 'Install/Core',
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

  if (selected[InstallationComponent.NewPipeExtractor] == true) {
    tasks.add(InstallTaskId.downloadNewPipe);
  }
  if (selected[InstallationComponent.YT_DLP] == true) {
    tasks.add(InstallTaskId.downloadYtDlp);
  }

  return tasks;
}
