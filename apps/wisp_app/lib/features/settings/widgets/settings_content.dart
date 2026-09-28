// Copyright © 2026 wizeshi

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/data/sources/auth/js_auth_source.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/settings/views/providers_marketplace_view.dart';

class SettingsContent extends StatelessWidget {
  final Widget Function(BuildContext, JsAuthSource, String, IconData, Color)
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
  });

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return ListenableBuilder(
      listenable: AuthSourceManager.instance,
      builder: (context, _) {
        final authSources = AuthSourceManager.instance.sources.values.where((auth) {
          return prefs.isProviderEnabled(auth.id, type: 'auth');
        }).toList();

        final providerCards = authSources
            .map(
              (auth) => buildProviderCard(
                context,
                auth,
                auth.displayName,
                Icons.library_music,
                Theme.of(context).colorScheme.primary,
              ),
            )
            .expand((w) => [w, const SizedBox(height: 16)])
            .toList();

        return ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            Text(
              'ACCOUNTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            ...providerCards,
            _buildMarketplaceRow(context),
        const SizedBox(height: 16),
        Text(
          'PREFERENCES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        buildStylePreferenceRow(),
        const SizedBox(height: 16),
        buildAnimatedCanvasRow(),
        const SizedBox(height: 16),
        buildAllowWritingRow(),
        if (!(Platform.isAndroid || Platform.isIOS)) ...[
          const SizedBox(height: 16),
          buildPausedBackgroundWidgetsRow(context),
        ],
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
      },
    );
  }

  Widget _buildMarketplaceRow(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ProvidersRepositoryService.instance.updatesAvailableCount,
      builder: (context, updateCount, child) {
        final hasUpdates = updateCount > 0;
        final primaryColor = Theme.of(context).colorScheme.primary;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
            border: hasUpdates
                ? Border.all(
                    color: Colors.amber.withValues(alpha: 0.5),
                    width: 1.2,
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (hasUpdates ? Colors.amber : primaryColor)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      hasUpdates
                          ? Icons.system_update_alt
                          : Icons.storefront_outlined,
                      color: hasUpdates ? Colors.amber : primaryColor,
                      size: 22,
                    ),
                  ),
                  if (hasUpdates)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF181818),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Marketplace',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasUpdates) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.arrow_upward,
                                  size: 10,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$updateCount ${updateCount == 1 ? "update" : "updates"} available',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasUpdates
                          ? 'New version available for installed providers'
                          : 'Browse, install, and update custom metadata & lyrics providers',
                      style: TextStyle(
                        color: hasUpdates ? Colors.amber[200] : Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => ProvidersMarketplaceView.push(context),
                icon: Icon(
                  hasUpdates ? Icons.system_update_alt : Icons.arrow_forward,
                  size: 16,
                ),
                label: Text(hasUpdates ? 'Updates ($updateCount)' : 'Browse'),
                style: FilledButton.styleFrom(
                  backgroundColor: (hasUpdates ? Colors.amber : primaryColor)
                      .withValues(alpha: 0.2),
                  foregroundColor: hasUpdates ? Colors.amber : primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
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

