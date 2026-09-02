import 'package:flutter/foundation.dart';
import 'package:wisp_installer/installation/install_orchestrator.dart';
import 'package:wisp_installer/installation/models/install_log_entry.dart';
import 'package:wisp_installer/installation/models/install_status.dart';
import 'package:wisp_installer/installation/models/install_task.dart';
import 'package:wisp_installer/navigation/shell.dart';
import 'package:wisp_installer/utils/logger.dart';

class InstallController extends ChangeNotifier {
  InstallStatus status = InstallStatus.idle;
  int currentTaskIndex = 0;
  List<InstallTaskId> tasks = [];
  double taskProgress = 0.0;
  bool showDetailedProgress = false;
  final List<InstallLogEntry> logs = [];
  String? errorMessage;
  String? installedAppPath;
  int? _lastLoggedProgressPercent;

  String get currentTaskLabel {
    if (tasks.isEmpty || currentTaskIndex >= tasks.length) {
      return 'Preparing installation...';
    }
    return labelForTask(tasks[currentTaskIndex]);
  }

  double get overallProgress {
    if (tasks.isEmpty) return 0;
    return ((currentTaskIndex + taskProgress) / tasks.length).clamp(0.0, 1.0);
  }

  int get currentStepNumber => tasks.isEmpty ? 0 : currentTaskIndex + 1;
  int get totalSteps => tasks.length;

  void toggleDetailedProgress() {
    showDetailedProgress = !showDetailedProgress;
    notifyListeners();
  }

  void log(String category, String message) {
    logs.add(InstallLogEntry(category: category, message: message));
    logger.i('[$category] $message');
    notifyListeners();
  }

  void logError(String category, String message) {
    logs.add(InstallLogEntry(category: category, message: message));
    logger.e('[$category] $message');
    notifyListeners();
  }

  void setTaskProgress(double value) {
    taskProgress = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void logTaskProgress(
    String category,
    int received,
    int? total, {
    double taskProgressStart = 0.0,
    double taskProgressEnd = 1.0,
  }) {
    final downloadProgress = total != null && total > 0
        ? received / total
        : 0.0;
    final taskProgress =
        taskProgressStart +
        (taskProgressEnd - taskProgressStart) * downloadProgress;
    setTaskProgress(taskProgress);

    if (total == null || total <= 0) return;

    // Do not round here: every chunk after 99.5% would otherwise become 100%
    // and bypass the log throttle. Flooring emits 100% only once the final
    // byte has actually been received.
    final percent = ((received * 100) ~/ total).clamp(0, 100);
    final shouldLog =
        _lastLoggedProgressPercent == null ||
        percent - _lastLoggedProgressPercent! >= 5;

    if (!shouldLog) return;

    _lastLoggedProgressPercent = percent;
    log(category, 'Progress: $percent% ($received/$total bytes)');
  }

  void resetProgressLogging() {
    _lastLoggedProgressPercent = null;
  }

  void setInstalledAppPath(String path) {
    installedAppPath = path;
  }

  void advanceToTask(int index) {
    currentTaskIndex = index;
    taskProgress = 0.0;
    resetProgressLogging();
    notifyListeners();
  }

  Future<void> start(Map<InstallationComponent, bool> selected) async {
    if (status == InstallStatus.running) return;

    tasks = buildTaskPlan(selected);
    currentTaskIndex = 0;
    taskProgress = 0.0;
    errorMessage = null;
    installedAppPath = null;
    logs.clear();
    status = InstallStatus.running;
    notifyListeners();

    try {
      await InstallOrchestrator(this).run();
      status = InstallStatus.success;
      log('Install', 'Installation completed successfully.');
    } catch (e) {
      status = InstallStatus.failed;
      errorMessage = e.toString();
      logError('Install', 'Installation failed: $e');
    }

    notifyListeners();
  }
}
