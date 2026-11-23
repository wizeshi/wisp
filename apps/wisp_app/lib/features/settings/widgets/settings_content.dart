// Copyright © 2026 wizeshi

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/data/sources/auth/js_auth_source.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/settings/views/providers_marketplace_view.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert_extensions.dart';

class SettingsContent extends StatelessWidget {
  final Widget Function(BuildContext, JsAuthSource, String, IconData, Color)
  buildProviderCard;
  final Widget Function(BuildContext)? buildYouTubeCard;
  final Widget Function(BuildContext) buildCacheSettingsCard;
  final Widget Function() buildStylePreferenceRow;
  final Widget Function() buildThemePreferenceRow;
  final Widget Function() buildAudioPreferenceRow;
  final Widget Function() buildHandoffPreferenceRow;
  final Widget Function() buildAnimatedCanvasRow;
  final Widget Function() buildAllowWritingRow;
  final Widget Function() buildCreditsSection;
  final Widget Function() buildDebugSection;
  final Widget Function(BuildContext) buildPausedBackgroundWidgetsRow;
  final void Function(String)? showSnackBar;

  const SettingsContent({
    super.key,
    required this.buildProviderCard,
    this.buildYouTubeCard,
    required this.buildCacheSettingsCard,
    required this.buildStylePreferenceRow,
    required this.buildThemePreferenceRow,
    required this.buildAudioPreferenceRow,
    required this.buildHandoffPreferenceRow,
    required this.buildAnimatedCanvasRow,
    required this.buildPausedBackgroundWidgetsRow,
    required this.buildAllowWritingRow,
    required this.buildCreditsSection,
    required this.buildDebugSection,
    this.showSnackBar,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final colors = context.colors;

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

        return WispListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            Text(
              'ACCOUNTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colors.textMuted,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (buildYouTubeCard != null) ...[
              buildYouTubeCard!(context),
              const SizedBox(height: 16),
            ],
            ...providerCards,
            _buildMarketplaceRow(context),
        const SizedBox(height: 16),
        Text(
          'PREFERENCES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: colors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        buildStylePreferenceRow(),
        const SizedBox(height: 16),
        buildThemePreferenceRow(),
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
            color: colors.textMuted,
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
            color: colors.textMuted,
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
            color: colors.textMuted,
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
            color: colors.textMuted,
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
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No trashed playlists',
                  style: TextStyle(color: colors.textMuted),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: trashed.map((p) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      p.title,
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      p.authorName,
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GenericIconButton(
                          tooltip: 'Restore',
                          icon: Icon(
                            Icons.restore_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () async {
                            await context
                                .read<LocalPlaylistState>()
                                .restorePlaylist(p.id);
                            if (!context.mounted) return;
                            context.showSuccessAlert('Playlist restored');
                            showSnackBar?.call('Playlist restored');
                          },
                        ),
                        GenericIconButton(
                          tooltip: 'Delete permanently',
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red[400],
                          ),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) {
                                final dialogColors = ctx.colors;
                                return AlertDialog(
                                  backgroundColor: dialogColors.surfaceElevated,
                                  title: Text(
                                    'Delete permanently',
                                    style: TextStyle(
                                      color: dialogColors.textPrimary,
                                    ),
                                  ),
                                  content: Text(
                                    'This will permanently delete the playlist and its thumbnail. '
                                    'This cannot be undone.',
                                    style: TextStyle(
                                      color: dialogColors.textSecondary,
                                    ),
                                  ),
                                  actions: [
                                    GenericTextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: dialogColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    GenericElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      backgroundColor: Colors.red[700],
                                      foregroundColor: Colors.white,
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirm == true) {
                              if (!context.mounted) return;
                              await context
                                  .read<LocalPlaylistState>()
                                  .permanentlyDeletePlaylist(p.id);
                              if (!context.mounted) return;
                              context.showSuccessAlert('Playlist deleted');
                              showSnackBar?.call('Playlist deleted');
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
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recover a provider playlist by ID',
                      style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    ),
                    Text(
                      'If you accidentally hid (not deleted) a playlist, and you know its provider ID, you can unhide it here. This is inteded for advanced users.',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GenericOutlinedButton(
                onPressed: () async {
                  final idController = TextEditingController();
                  final bool? ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) {
                      final dialogColors = ctx.colors;
                      return AlertDialog(
                        backgroundColor: dialogColors.surfaceElevated,
                        title: Text(
                          'Unhide Provider Playlist',
                          style: TextStyle(color: dialogColors.textPrimary),
                        ),
                        content: TextField(
                          controller: idController,
                          style: TextStyle(color: dialogColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Provider playlist id',
                            labelStyle: TextStyle(
                              color: dialogColors.textSecondary,
                            ),
                            hintText: 'e.g. spotify:playlist:... or playlist id',
                          ),
                        ),
                        actions: [
                          GenericTextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: dialogColors.textSecondary,
                              ),
                            ),
                          ),
                          GenericElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Unhide'),
                          ),
                        ],
                      );
                    },
                  );
                if (ok == true) {
                  if (!context.mounted) return;
                  final providerId = idController.text.trim();
                  if (providerId.isEmpty) {
                    context.showWarningAlert('No id entered');
                    showSnackBar?.call('No id entered');
                    return;
                  }
                  if (!context.mounted) return;
                  await context
                      .read<LocalPlaylistState>()
                      .unhideProviderPlaylist(providerId);
                  if (!context.mounted) return;
                  const msg =
                      'Provider id unhidden — open provider playlist to restore';
                  context.showSuccessAlert(msg);
                  showSnackBar?.call(msg);
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
            color: colors.textMuted,
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
    final colors = context.colors;
    return ValueListenableBuilder<int>(
      valueListenable: ProvidersRepositoryService.instance.updatesAvailableCount,
      builder: (context, updateCount, child) {
        final hasUpdates = updateCount > 0;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final amberAccent = colors.isDark ? Colors.amber : Colors.amber[800]!;

        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: hasUpdates
                ? Border.all(
                    color: amberAccent.withValues(alpha: 0.5),
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
                      color: (hasUpdates ? amberAccent : primaryColor)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      hasUpdates
                          ? Icons.system_update_alt
                          : Icons.storefront_outlined,
                      color: hasUpdates ? amberAccent : primaryColor,
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
                          color: amberAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.surface,
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
                        Text(
                          'Marketplace',
                          style: TextStyle(
                            color: colors.textPrimary,
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
                              color: amberAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: amberAccent.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  size: 10,
                                  color: amberAccent,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$updateCount ${updateCount == 1 ? "update" : "updates"} available',
                                  style: TextStyle(
                                    color: amberAccent,
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
                        color: hasUpdates
                            ? (colors.isDark ? Colors.amber[200] : Colors.amber[900])
                            : colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GenericButton.tonalIcon(
                onPressed: () => ProvidersMarketplaceView.push(context),
                icon: Icon(
                  hasUpdates ? Icons.system_update_alt : Icons.arrow_forward,
                  size: 16,
                ),
                label: Text(hasUpdates ? 'Updates ($updateCount)' : 'Browse'),
                backgroundColor: (hasUpdates ? amberAccent : primaryColor)
                    .withValues(alpha: 0.2),
                foregroundColor: hasUpdates ? amberAccent : primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

