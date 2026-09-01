import 'package:wisp_installer/navigation/shell.dart';

enum InstallTaskId {
  downloadCore,
  extractCore,
  integrateOs,
  downloadNewPipe,
  downloadYtDlp,
}

String labelForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.downloadCore => 'Downloading App Core',
    InstallTaskId.extractCore => 'Extracting App Core',
    InstallTaskId.integrateOs => 'Integrating with OS',
    InstallTaskId.downloadNewPipe => 'Installing NewPipeExtractor + Java',
    InstallTaskId.downloadYtDlp => 'Installing YT-DLP + Node.js',
  };
}

String categoryForTask(InstallTaskId task) {
  return switch (task) {
    InstallTaskId.downloadCore => 'Install/Core',
    InstallTaskId.extractCore => 'Install/Core',
    InstallTaskId.integrateOs => 'Install/OS',
    InstallTaskId.downloadNewPipe => 'Install/NewPipe',
    InstallTaskId.downloadYtDlp => 'Install/YT-DLP',
  };
}

List<InstallTaskId> buildTaskPlan(Map<InstallationComponent, bool> selected) {
  final tasks = <InstallTaskId>[
    InstallTaskId.downloadCore,
    InstallTaskId.extractCore,
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
