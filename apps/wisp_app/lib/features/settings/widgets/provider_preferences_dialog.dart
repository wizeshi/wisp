// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

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
                        SwitchListTile.adaptive(
                          title: const Text(
                            'Spotify',
                            style: TextStyle(color: Colors.white),
                          ),
                          value: prefs.metadataSpotifyEnabled,
                          activeThumbColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onChanged: (enabled) async {
                            final hasAny =
                                enabled || prefs.metadataYouTubeEnabled;
                            await prefs.setMetadataSpotifyEnabled(enabled);
                            if (!hasAny) {
                              showSnackBar(
                                'Warning: all Metadata providers are disabled.',
                              );
                            }
                          },
                        ),
                        SwitchListTile.adaptive(
                          title: const Text(
                            'YouTube',
                            style: TextStyle(color: Colors.white),
                          ),
                          value: prefs.metadataYouTubeEnabled,
                          activeThumbColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onChanged: (enabled) async {
                            final hasAny =
                                enabled || prefs.metadataSpotifyEnabled;
                            await prefs.setMetadataYouTubeEnabled(enabled);
                            if (!hasAny) {
                              showSnackBar(
                                'Warning: all Metadata providers are disabled.',
                              );
                            }
                          },
                        ),
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
                        SwitchListTile.adaptive(
                          title: const Text(
                            'Lrclib',
                            style: TextStyle(color: Colors.white),
                          ),
                          value: prefs.lyricsLrclibEnabled,
                          activeThumbColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onChanged: (enabled) async {
                            final hasAny =
                                enabled || prefs.lyricsSpotifyEnabled;
                            await prefs.setLyricsLrclibEnabled(enabled);
                            if (!hasAny) {
                              showSnackBar(
                                'Warning: all Lyrics providers are disabled.',
                              );
                            }
                          },
                        ),
                        SwitchListTile.adaptive(
                          title: const Text(
                            'Spotify',
                            style: TextStyle(color: Colors.white),
                          ),
                          value: prefs.lyricsSpotifyEnabled,
                          activeThumbColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onChanged: (enabled) async {
                            final hasAny =
                                enabled || prefs.lyricsLrclibEnabled;
                            await prefs.setLyricsSpotifyEnabled(enabled);
                            if (!hasAny) {
                              showSnackBar(
                                'Warning: all Lyrics providers are disabled.',
                              );
                            }
                          },
                        ),
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

