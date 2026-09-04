import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp_installer/installation/install_controller.dart';
import 'package:wisp_installer/installation/models/install_status.dart';
import 'package:wisp_installer/utils/logger.dart';
import 'package:wisp_installer/views/component_select.dart';
import 'package:wisp_installer/views/install_complete.dart';
import 'package:wisp_installer/views/installation_progress.dart';
import 'package:wisp_installer/views/license_agreement.dart';
import 'package:wisp_installer/views/welcome.dart';
import 'package:wisp_installer/widgets/titlebar.dart';

enum InstallationStep {
  welcome,
  licenseAgreement,
  componentSelection,
  installationProgress,
  completion,
}

enum InstallationComponent {
  // ignore: constant_identifier_names
  Core,
  // ignore: constant_identifier_names
  EdgeWebView2,
  // ignore: constant_identifier_names
  NewPipeExtractor,
  // ignore: constant_identifier_names
  YT_DLP,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  InstallationStep currentStep = InstallationStep.welcome;
  bool isLicenseAccepted = false;
  Map<InstallationComponent, bool> selectedComponents = {
    InstallationComponent.Core: true,
    InstallationComponent.EdgeWebView2: true,
    InstallationComponent.NewPipeExtractor: true,
    InstallationComponent.YT_DLP: true,
  };
  bool installationInProgress = false;
  final InstallController installController = InstallController();

  @override
  void dispose() {
    installController.dispose();
    super.dispose();
  }

  void goToPreviousStep() {
    setState(() {
      final currentIndex = InstallationStep.values.indexOf(currentStep);
      if (currentIndex > 0) {
        currentStep = InstallationStep.values[currentIndex - 1];
      }
    });
  }

  void goToNextStep() {
    setState(() {
      final currentIndex = InstallationStep.values.indexOf(currentStep);
      if (currentIndex < InstallationStep.values.length - 1) {
        currentStep = InstallationStep.values[currentIndex + 1];
      }
    });
  }

  Future<void> startInstallation() async {
    setState(() {
      installationInProgress = true;
      currentStep = InstallationStep.installationProgress;
    });

    await installController.start(selectedComponents);

    if (!mounted) return;

    setState(() {
      installationInProgress = false;
      if (installController.status == InstallStatus.success) {
        currentStep = InstallationStep.completion;
      }
    });
  }

  void toggleLicenseAcceptance(bool? value) {
    setState(() {
      isLicenseAccepted = value ?? false;
    });
  }

  void toggleComponentSelection(InstallationComponent component, bool? value) {
    setState(() {
      selectedComponents[component] = value ?? false;
    });
  }

  bool isComponentSelected(InstallationComponent component) {
    return selectedComponents[component] ?? false;
  }

  String get detectedPlatform {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }

  Widget buildWelcomeStep() {
    return WelcomeStep(goToNextStep: goToNextStep);
  }

  Widget buildLicenseAgreementStep() {
    return LicenseAgreementStep(
      isLicenseAccepted: isLicenseAccepted,
      toggleLicenseAcceptance: toggleLicenseAcceptance,
      goToNextStep: goToNextStep,
    );
  }

  Widget buildComponentSelectionStep() {
    return ComponentSelectStep(
      toggleComponentSelection: toggleComponentSelection,
      isComponentSelected: isComponentSelected,
      detectedPlatform: detectedPlatform,
      isWindows: Platform.isWindows,
      onStartInstallation: startInstallation,
    );
  }

  Widget buildInstallationProgressStep() {
    return InstallationProgressStep(controller: installController);
  }

  Widget buildCompletionStep() {
    return InstallationCompleteStep(
      installedComponents: [
        'wisp',
        if (isComponentSelected(InstallationComponent.NewPipeExtractor))
          'NewPipeExtractor + Java',
        if (isComponentSelected(InstallationComponent.YT_DLP))
          'yt-dlp + Node.js',
      ],
      onFinish: windowManager.close,
      onOpenApp: _openInstalledApp,
    );
  }

  Future<void> _closeInstaller() async {
    await windowManager.close();
  }

  Future<void> _openInstalledApp() async {
    final installedAppPath = installController.installedAppPath;
    logger.d("Opening installed app at path: $installedAppPath");
    
    if (installedAppPath == null) return;

    if (Platform.isMacOS) {
      Process.start('open', [installedAppPath]).then((x) => _closeInstaller());
    } else if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', installedAppPath]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [installedAppPath]);
    }
  }

  Widget buildCurrentStep(InstallationStep activeStep) {
    switch (activeStep) {
      case InstallationStep.welcome:
        return buildWelcomeStep();
      case InstallationStep.licenseAgreement:
        return buildLicenseAgreementStep();
      case InstallationStep.componentSelection:
        return buildComponentSelectionStep();
      case InstallationStep.installationProgress:
        return buildInstallationProgressStep();
      case InstallationStep.completion:
        return buildCompletionStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final canRegress =
        (InstallationStep.values.indexOf(currentStep) > 0) &&
        !installationInProgress;
    final canAdvance =
        !installationInProgress &&
        currentStep != InstallationStep.installationProgress &&
        ((currentStep != InstallationStep.licenseAgreement) ||
            isLicenseAccepted);

    return Scaffold(
      body: Column(
        children: [
          InstallerTitleBar(),

          // This is the content area
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Backward button
                if (InstallationStep.values.indexOf(currentStep) > 0 &&
                    currentStep != InstallationStep.completion)
                  Positioned.directional(
                    textDirection: Directionality.of(context),
                    top: 12,
                    start: 12,
                    child: IconButton.filled(
                      onPressed: canRegress ? goToPreviousStep : null,
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      color: primaryColor,
                      iconSize: 28,
                    ),
                  ),
                // Forward button
                if (InstallationStep.values.indexOf(currentStep) <
                    InstallationStep.values.length - 1)
                  Positioned.directional(
                    textDirection: Directionality.of(context),
                    top: 12,
                    end: 12,
                    child: IconButton.filled(
                      onPressed: canAdvance ? goToNextStep : null,
                      icon: Icon(Icons.arrow_forward, color: Colors.white),
                      color: primaryColor,
                      iconSize: 28,
                    ),
                  ),

                Container(
                  padding: EdgeInsets.all(12.0),
                  child: buildCurrentStep(currentStep),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
