// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/features/library/state/local_playlists.dart';

class SettingsContent extends StatelessWidget {
  final Widget Function(BuildContext, MetadataProvider, String, IconData, Color)
  buildProviderCard;
  final Widget Function(BuildContext) buildCacheSettingsCard;
  final Widget Function() buildStylePreferenceRow;
  final Widget Function() buildAudioPreferenceRow;
  final Widget Function() buildHandoffPreferenceRow;
  final Widget Function() buildAnimatedCanvasRow;
  final Widget Function() buildAllowWritingRow;
  final Widget Function() buildCreditsSection;
  final Widget Function() buildDebugSection;
  final Widget Function(BuildContext) buildPausedBackgroundWidgetsRow;
  final void Function(String) showSnackBar;
  final VoidCallback onEditProviderPreferences;

  const SettingsContent({
    super.key,
    required this.buildProviderCard,
    required this.buildCacheSettingsCard,
    required this.buildStylePreferenceRow,
    required this.buildAudioPreferenceRow,
    required this.buildHandoffPreferenceRow,
    required this.buildAnimatedCanvasRow,
    required this.buildPausedBackgroundWidgetsRow,
    required this.buildAllowWritingRow,
    required this.buildCreditsSection,
    required this.buildDebugSection,
    required this.showSnackBar,
    required this.onEditProviderPreferences,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget Function()> providerConsumers = [
      () => Consumer<SpotifyInternalProvider>(
        builder: (context, providerInstance, child) {
          return buildProviderCard(
            context,
            providerInstance,
            providerInstance.name,
            Icons.library_music,
            Theme.of(context).colorScheme.primary,
          );
        },
      ),
    ];

    final providerCards = providerConsumers
        .map((builder) => builder())
        .expand((w) => [w, const SizedBox(height: 16)])
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Text(
          'PROVIDERS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        ...providerCards,
        Row(
          children: [
            Text(
              'PREFERENCES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Edit providers',
              onPressed: onEditProviderPreferences,
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        buildStylePreferenceRow(),
        const SizedBox(height: 16),
        buildAnimatedCanvasRow(),
        const SizedBox(height: 16),
        buildAllowWritingRow(),
        const SizedBox(height: 16),
        buildPausedBackgroundWidgetsRow(context),
        const SizedBox(height: 16),
        Text(
          'AUDIO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        buildAudioPreferenceRow(),
        const SizedBox(height: 16),
        Text(
          'HANDOFF',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        buildHandoffPreferenceRow(),
        const SizedBox(height: 16),
        Text(
          'CACHE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        buildCacheSettingsCard(context),
        const SizedBox(height: 16),
        Text(
          'TRASH',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Consumer<LocalPlaylistState>(
          builder: (context, trashState, child) {
            final trashed = trashState.trashedPlaylists;
            if (trashed.isEmpty) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No trashed playlists',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: trashed.map((p) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      p.title,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      p.authorName,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Restore',
                          icon: Icon(
                            Icons.restore_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () async {
                            await context
                                .read<LocalPlaylistState>()
                                .restorePlaylist(p.id);
                            showSnackBar('Playlist restored');
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete permanently',
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red[400],
                          ),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF282828),
                                title: const Text(
                                  'Delete permanently',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: Text(
                                  'This will permanently delete the playlist and its thumbnail. '
                                  'This cannot be undone.',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(color: Colors.grey[400]),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[700],
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              if (!context.mounted) return;
                              await context
                                  .read<LocalPlaylistState>()
                                  .permanentlyDeletePlaylist(p.id);
                              showSnackBar('Playlist deleted');
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recover a provider playlist by ID',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Text(
                      'If you accidentally hid (not deleted) a playlist, and you know its provider ID, you can unhide it here. This is inteded for advanced users.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () async {
                  final idController = TextEditingController();
                  final bool? ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF282828),
                      title: const Text(
                        'Unhide Provider Playlist',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: TextField(
                        controller: idController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Provider playlist id',
                          labelStyle: TextStyle(color: Colors.grey[400]),
                          hintText: 'e.g. spotify:playlist:... or playlist id',
                        ),
                      ),
                      actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Unhide'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final providerId = idController.text.trim();
                  if (providerId.isEmpty) {
                    showSnackBar('No id entered');
                    return;
                  }
                  if (!context.mounted) return;
                  await context
                      .read<LocalPlaylistState>()
                      .unhideProviderPlaylist(providerId);
                  showSnackBar(
                    'Provider id unhidden — open provider playlist to restore',
                  );
                }
              },
              child: const Text('Unhide'),
            ),
          ],
        ),
      ),

        buildDebugSection(),

        const SizedBox(height: 16),
        Text(
          'CREDITS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        buildCreditsSection(),
      ],
    );
  }
}
