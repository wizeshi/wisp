import 'package:flutter/material.dart';
import 'package:wisp_installer/installation/install_controller.dart';
import 'package:wisp_installer/installation/models/install_status.dart';
import 'package:wisp_installer/widgets/install_console.dart';

class InstallationProgressStep extends StatelessWidget {
  const InstallationProgressStep({super.key, required this.controller});

  final InstallController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isFailed = controller.status == InstallStatus.failed;
        final progressColor = isFailed
            ? Colors.red
            : Theme.of(context).colorScheme.primary;

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 28 + 12 + 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                controller.currentTaskLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (controller.totalSteps > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Step ${controller.currentStepNumber} of ${controller.totalSteps}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:
                      controller.status == InstallStatus.running ||
                          controller.status == InstallStatus.success
                      ? controller.overallProgress
                      : null,
                  minHeight: 8,
                  backgroundColor: Colors.grey[800],
                  color: progressColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(controller.overallProgress * 100).round()}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
              if (isFailed && controller.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.errorMessage!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: controller.toggleDetailedProgress,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        controller.showDetailedProgress
                            ? 'Hide Detailed Progress'
                            : 'Show Detailed Progress',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      controller.showDetailedProgress
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: controller.showDetailedProgress
                      ? Padding(
                          key: const ValueKey('console'),
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: InstallConsole(logs: controller.logs),
                        )
                      : const SizedBox(
                          key: ValueKey('empty'),
                          width: double.infinity,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
