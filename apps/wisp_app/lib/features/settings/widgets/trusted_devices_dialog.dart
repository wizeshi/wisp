// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

class TrustedDevicesDialog extends StatelessWidget {
  const TrustedDevicesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => const TrustedDevicesDialog(),
    );
  }

  static IconData _trustedDeviceIcon(String platform) {
    final normalized = platform.toLowerCase();
    if (normalized.contains('android') || normalized.contains('ios')) {
      return Icons.smartphone;
    }
    if (normalized.contains('windows') ||
        normalized.contains('macos') ||
        normalized.contains('linux')) {
      return Icons.computer;
    }
    return Icons.devices;
  }

  static String _formatDateTime(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(value);
    final time = TimeOfDay.fromDateTime(value).format(context);
    return '$date $time';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Text(
        'Trusted Devices',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SizedBox(
        width: 620,
        child: Consumer<PreferencesProvider>(
          builder: (context, prefs, child) {
            final devices = prefs.trustedDevices;
            if (devices.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No trusted devices yet.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              );
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: devices.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _trustedDeviceIcon(device.platform),
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                device.platform,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Trusted: ${_formatDateTime(context, device.trustedAt)}',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                'Last connection: ${_formatDateTime(context, device.lastConnectionAt)}',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GenericTextButton(
                          onPressed: () async {
                            final confirmed =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (confirmContext) {
                                    final confirmColors = confirmContext.colors;
                                    return AlertDialog(
                                      backgroundColor:
                                          confirmColors.surfaceElevated,
                                      title: Text(
                                        'Forget device?',
                                        style: TextStyle(
                                          color: confirmColors.textPrimary,
                                        ),
                                      ),
                                      content: Text(
                                        'Remove ${device.name} from trusted devices?',
                                        style: TextStyle(
                                          color: confirmColors.textSecondary,
                                        ),
                                      ),
                                      actions: [
                                        GenericTextButton(
                                          onPressed: () => Navigator.of(
                                            confirmContext,
                                          ).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        GenericTextButton(
                                          onPressed: () => Navigator.of(
                                            confirmContext,
                                          ).pop(true),
                                          child: const Text('Forget'),
                                        ),
                                      ],
                                    );
                                  },
                                ) ??
                                false;
                            if (!confirmed) {
                              return;
                            }
                            await prefs.forgetTrustedDevice(device.id);
                          },
                          child: const Text('Forget'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        GenericTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
