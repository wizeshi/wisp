import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_installer/installation/models/install_task.dart';
import 'package:wisp_installer/navigation/shell.dart';

void main() {
  group('Installer Task Planning Tests', () {
    test('buildTaskPlan includes JavaRuntime when NewPipe is selected', () {
      final selected = {
        InstallationComponent.Core: true,
        InstallationComponent.EdgeWebView2: false,
        InstallationComponent.JavaRuntime: false,
        InstallationComponent.NewPipeExtractor: true,
        InstallationComponent.InnerTubeX: false,
        InstallationComponent.YT_DLP: false,
      };

      final plan = buildTaskPlan(selected);
      expect(plan, contains(InstallTaskId.installCore));
      expect(plan, contains(InstallTaskId.integrateOs));
      expect(plan, contains(InstallTaskId.downloadJavaRuntime));
      expect(plan, contains(InstallTaskId.downloadNewPipe));

      // Java must be scheduled before NewPipe
      final javaIndex = plan.indexOf(InstallTaskId.downloadJavaRuntime);
      final newPipeIndex = plan.indexOf(InstallTaskId.downloadNewPipe);
      expect(javaIndex, lessThan(newPipeIndex));
    });

    test('buildTaskPlan includes JavaRuntime when InnerTubeX is selected', () {
      final selected = {
        InstallationComponent.Core: true,
        InstallationComponent.EdgeWebView2: false,
        InstallationComponent.JavaRuntime: false,
        InstallationComponent.NewPipeExtractor: false,
        InstallationComponent.InnerTubeX: true,
        InstallationComponent.YT_DLP: false,
      };

      final plan = buildTaskPlan(selected);
      expect(plan, contains(InstallTaskId.installCore));
      expect(plan, contains(InstallTaskId.integrateOs));
      expect(plan, contains(InstallTaskId.downloadJavaRuntime));
      expect(plan, contains(InstallTaskId.downloadInnerTubeX));

      // Java must be scheduled before InnerTubeX
      final javaIndex = plan.indexOf(InstallTaskId.downloadJavaRuntime);
      final innerTubeIndex = plan.indexOf(InstallTaskId.downloadInnerTubeX);
      expect(javaIndex, lessThan(innerTubeIndex));
    });

    test('buildTaskPlan excludes JavaRuntime when neither Java nor JVM engines selected', () {
      final selected = {
        InstallationComponent.Core: true,
        InstallationComponent.EdgeWebView2: false,
        InstallationComponent.JavaRuntime: false,
        InstallationComponent.NewPipeExtractor: false,
        InstallationComponent.InnerTubeX: false,
        InstallationComponent.YT_DLP: true,
      };

      final plan = buildTaskPlan(selected);
      expect(plan, isNot(contains(InstallTaskId.downloadJavaRuntime)));
      expect(plan, isNot(contains(InstallTaskId.downloadNewPipe)));
      expect(plan, isNot(contains(InstallTaskId.downloadInnerTubeX)));
      expect(plan, contains(InstallTaskId.downloadYtDlp));
    });

    test('labels and categories for tasks are non-empty and formatted', () {
      for (final task in InstallTaskId.values) {
        expect(labelForTask(task), isNotEmpty);
        expect(categoryForTask(task), startsWith('Install/'));
      }
    });
  });
}
