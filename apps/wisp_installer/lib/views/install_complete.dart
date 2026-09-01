import 'dart:io';

import 'package:flutter/material.dart';

class InstallationCompleteStep extends StatefulWidget {
  const InstallationCompleteStep({
    super.key,
    required this.installedComponents,
    required this.onFinish,
    required this.onOpenApp,
  });

  final List<String> installedComponents;
  final VoidCallback onFinish;
  final VoidCallback onOpenApp;

  @override
  State<InstallationCompleteStep> createState() =>
      _InstallationCompleteStepState();
}

class _InstallationCompleteStepState extends State<InstallationCompleteStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, _) {
        final progress = _animationController.value;
        final checkScale = Curves.elasticOut.transform(
          const Interval(0, 0.4).transform(progress),
        );
        final checkOpacity = 1 - const Interval(0.42, 0.68).transform(progress);
        final contentOpacity = const Interval(0.55, 1).transform(progress);

        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: checkOpacity,
              child: Transform.scale(
                scale: checkScale,
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: colors.primary,
                    size: 60,
                  ),
                ),
              ),
            ),
            IgnorePointer(
              ignoring: contentOpacity < 1,
              child: Opacity(
                opacity: contentOpacity,
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - contentOpacity)),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Installation complete',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              Platform.isWindows
                                  ? 'wisp is ready to use. You can open it now or launch it later from the Start menu or Desktop.'
                                  : 'wisp is ready to use. You can open it now or launch it later from your Applications folder.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[400],
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Installed components',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: widget.installedComponents
                                  .map(
                                    (component) => Chip(
                                      avatar: Icon(
                                        Icons.check,
                                        size: 16,
                                        color: colors.primary,
                                      ),
                                      label: Text(component),
                                      side: BorderSide(
                                        color: colors.outlineVariant.withValues(alpha: 0.12),
                                      ),
                                      backgroundColor:
                                          colors.surfaceContainerHighest,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 28),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: widget.onFinish,
                                    icon: const Icon(Icons.close),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.surface,
                                      foregroundColor: Colors.white,
                                    ),
                                    label: const Text('Close installer'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: widget.onOpenApp,
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text('Open wisp'),
                                    style: FilledButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
