// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source_manager.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/display/provider_icon.dart';

class ProviderPreferencesDialog extends StatelessWidget {
  final void Function(String message) showSnackBar;

  const ProviderPreferencesDialog({super.key, required this.showSnackBar});

  static Future<void> show(
    BuildContext context, {
    required void Function(String message) showSnackBar,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => ProviderPreferencesDialog(
        showSnackBar: showSnackBar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text(
        'Provider Preferences',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 520,
        child: Consumer<PreferencesProvider>(
          builder: (context, prefs, child) {
            return SingleChildScrollView(
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExpansionTile(
                      initiallyExpanded: true,
                      title: const Text(
                        'Metadata',
                        style: TextStyle(color: Colors.white),
                      ),
                      children: [
                        ...context.watch<MetadataManager>().allProviders.map((provider) {
                          final isEnabled = prefs.isProviderEnabled(
                            provider.providerId,
                            type: 'metadata',
                          );
                          final hasUpdate = ProvidersRepositoryService.instance
                              .hasUpdateForProvider(provider.providerId);
                          return SwitchListTile.adaptive(
                            title: Row(
                              children: [
                                ProviderIcon(
                                  providerId: provider.providerId,
                                  type: 'metadata',
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  provider.displayName,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (hasUpdate) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.amber.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: const Text(
                                      'UPDATE',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            value: isEnabled,
                            activeThumbColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            onChanged: (enabled) async {
                              final metadataManager = context.read<MetadataManager>();
                              await prefs.setProviderEnabled(
                                provider.providerId,
                                enabled,
                                type: 'metadata',
                              );
                              if (metadataManager.availableProviders.isEmpty) {
                                showSnackBar(
                                  'Warning: all Metadata providers are disabled.',
                                );
                              }
                            },
                          );
                        }),
                      ],
                    ),
                    ExpansionTile(
                      title: const Text(
                        'Audio',
                        style: TextStyle(color: Colors.white),
                      ),
                      children: [
                        SwitchListTile.adaptive(
                          title: const Text(
                            'YouTube',
                            style: TextStyle(color: Colors.white),
                          ),
                          value: prefs.audioYouTubeEnabled,
                          activeThumbColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onChanged: (enabled) async {
                            final hasAny = enabled;
                            await prefs.setAudioYouTubeEnabled(enabled);
                            if (!hasAny) {
                              showSnackBar(
                                'Warning: all Audio providers are disabled.',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    ExpansionTile(
                      title: const Text(
                        'Lyrics',
                        style: TextStyle(color: Colors.white),
                      ),
                      children: [
                        ...LyricsSourceManager.instance.allSources.map((source) {
                          final isEnabled = prefs.isProviderEnabled(source.id);
                          final hasUpdate = ProvidersRepositoryService.instance
                              .hasUpdateForProvider(source.id);
                          return SwitchListTile.adaptive(
                            title: Row(
                              children: [
                                Text(
                                  source.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (hasUpdate) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.amber.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: const Text(
                                      'UPDATE AVAILABLE',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              'Priority: ${source.priority}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[400],
                              ),
                            ),
                            value: isEnabled,
                            activeThumbColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            onChanged: (enabled) async {
                              await prefs.setProviderEnabled(
                                source.id,
                                enabled,
                              );
                            },
                          );
                        }),
                      ],
                    ),
                  ],
                ),
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

