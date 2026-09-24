// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

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
    return AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text(
        'Trusted Devices',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 620,
        child: Consumer<PreferencesProvider>(
          builder: (context, prefs, child) {
            final devices = prefs.trustedDevices;
            if (devices.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No trusted devices yet.',
                  style: TextStyle(color: Colors.white70),
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
                      color: const Color(0xFF1F1F1F),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                device.platform,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Trusted: ${_formatDateTime(context, device.trustedAt)}',
                                style: TextStyle(
                                  color: Colors.grey[350],
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                'Last connection: ${_formatDateTime(context, device.lastConnectionAt)}',
                                style: TextStyle(
                                  color: Colors.grey[350],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            final confirmed =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (confirmContext) {
                                    return AlertDialog(
                                      backgroundColor: const Color(
                                        0xFF282828,
                                      ),
                                      title: const Text(
                                        'Forget device?',
                                        style: TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      content: Text(
                                        'Remove ${device.name} from trusted devices?',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(
                                            confirmContext,
                                          ).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
