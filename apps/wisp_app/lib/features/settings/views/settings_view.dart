// Copyright © 2026 wizeshi

/// Settings page with Spotify authentication
library;

import 'dart:io' show Directory, Platform, Process;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp_assets/wisp_assets.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'settings_downloads_view.dart';
import '../widgets/settings_content.dart';
import '../widgets/provider_preferences_dialog.dart';
import '../widgets/cache_deletion_dialog.dart';
import '../widgets/trusted_devices_dialog.dart';
import '../widgets/update_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _showProviderPreferencesDialog() =>
      ProviderPreferencesDialog.show(context, showSnackBar: _showSnackBar);

  Future<void> _showCacheDeleteDialog() =>
      CacheDeletionDialog.show(context, showSnackBar: _showSnackBar);

  Future<void> _handleProviderLogin(MetadataProvider provider) async {
    try {
      await provider.login(context);
      if (mounted) {
        _showSnackBar('Successfully authenticated with ${provider.name}!');
      }
    } catch (e) {
      _showSnackBar('Login failed: $e');
    }
  }

  Future<void> _handleProviderLogout(MetadataProvider provider) async {
    await provider.logout();
    if (mounted) {
      _showSnackBar('Logged out successfully');
    }
  }

  String _handoffSecurityPageLabel(HandoffSecurityLevel level) {
    switch (level) {
      case HandoffSecurityLevel.keyExchange:
        return 'Key-Exchange';
      case HandoffSecurityLevel.pinBased:
        return 'PIN-based';
    }
  }

  String _handoffSecuritySheetDescription(HandoffSecurityLevel level) {
    switch (level) {
      case HandoffSecurityLevel.keyExchange:
        return 'Easiest, Recommended';
      case HandoffSecurityLevel.pinBased:
        return 'Safer, Inconvenient';
    }
  }

  String _handoffSecurityTooltip(HandoffSecurityLevel level) {
    switch (level) {
      case HandoffSecurityLevel.keyExchange:
        return 'Easiest, Recommended';
      case HandoffSecurityLevel.pinBased:
        return 'Safer, Inconvenient';
    }
  }

  Future<void> _showTrustedDevicesDialog() =>
      TrustedDevicesDialog.show(context);

  void _showSnackBar(String message) {
    if (!mounted) return;
    final localMessenger = ScaffoldMessenger.maybeOf(context);
    final localScaffold = Scaffold.maybeOf(context);
    if (localMessenger != null && localScaffold != null) {
      localMessenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final rootContext = NavigationHistory.instance.navigatorKey.currentContext;
    if (rootContext != null) {
      final rootMessenger = ScaffoldMessenger.maybeOf(rootContext);
      final rootScaffold = Scaffold.maybeOf(rootContext);
      if (rootMessenger != null && rootScaffold != null) {
        rootMessenger.showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  Future<Directory> _resolveAudioCacheDirectory() async {
    await AudioCacheManager.instance.initialize();
    final appDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${appDir.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<void> _openAudioCacheFolder() async {
    if (!_isDesktop) {
      return;
    }

    try {
      final cacheDir = await _resolveAudioCacheDirectory();
      if (Platform.isWindows) {
        final normalizedPath = cacheDir.absolute.path.replaceAll('/', '\\');
        await Process.start('explorer.exe', [normalizedPath]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [cacheDir.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [cacheDir.path]);
      }
    } catch (e) {
      _showSnackBar('Could not open cache folder: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;

    final content = SettingsContent(
      buildProviderCard: _buildProviderCard,
      buildCacheSettingsCard: _buildCacheSettingsCard,
      buildStylePreferenceRow: _buildStylePreferenceRow,
      buildAudioPreferenceRow: _buildAudioPreferenceRow,
      buildHandoffPreferenceRow: _buildHandoffPreferenceRow,
      buildAnimatedCanvasRow: _buildAnimatedCanvasPreferenceRow,
      buildAllowWritingRow: _buildAllowWritingPreferenceRow,
      buildPausedBackgroundWidgetsRow: _buildPausedBackgroundWidgetsRow,
      buildCreditsSection: _buildCreditsSection,
      buildDebugSection: _buildDebugSection,
      showSnackBar: _showSnackBar,
      onEditProviderPreferences: _showProviderPreferencesDialog,
    );

    if (isDesktop) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: content,
    );
  }

  Widget _buildCacheSettingsCard(BuildContext context) {
    return ListenableBuilder(
      listenable: AudioCacheManager.instance,
      builder: (context, _) {
        final cacheManager = AudioCacheManager.instance;
        final isDesktop = _isDesktop;
        final userMB = cacheManager.userDownloadsSizeMB;
        final autoMB = cacheManager.autoCacheSizeMB;
        final maxMB = cacheManager.maxCacheSizeMB;
        final freeMB = (maxMB - (userMB + autoMB)).clamp(0, maxMB);

        Color statusColor;
        String statusLabel;
        switch (cacheManager.storageStatus) {
          case StorageStatus.fullPaused:
            statusColor = Colors.redAccent;
            statusLabel = 'Cache full (Auto-cache paused)';
            break;
          case StorageStatus.warning:
            statusColor = Colors.amberAccent;
            statusLabel = 'Near limit';
            break;
          case StorageStatus.normal:
            statusColor = Theme.of(context).colorScheme.primary;
            statusLabel = 'Operational';
            break;
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.storage,
                    color: statusColor,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Storage & Audio Cache',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${cacheManager.currentCacheSizeMB} MB of $maxMB MB used '
                          '• ${cacheManager.cachedTrackCount} tracks total',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Segmented Storage Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      if (userMB > 0)
                        Expanded(
                          flex: userMB,
                          child: Container(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      if (autoMB > 0)
                        Expanded(
                          flex: autoMB,
                          child: Container(color: Colors.purpleAccent[100]),
                        ),
                      if (freeMB > 0)
                        Expanded(
                          flex: freeMB,
                          child: Container(color: const Color(0xFF333333)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Storage Legend
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _buildLegendItem(
                    color: Theme.of(context).colorScheme.primary,
                    label: '${cacheManager.userDownloadCount} downloaded ($userMB MB)',
                  ),
                  _buildLegendItem(
                    color: Colors.purpleAccent[100]!,
                    label: '${cacheManager.autoCacheCount} cached ($autoMB MB)',
                  ),
                  _buildLegendItem(
                    color: Colors.grey[600]!,
                    label: '$freeMB MB free',
                  ),
                ],
              ),
              if (cacheManager.isStorageFull)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Storage limit reached. Playback auto-caching is paused to protect your downloaded music. Clear cache or raise limit to resume.',
                          style: TextStyle(
                            color: Colors.red[200],
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (cacheManager.storageStatus == StorageStatus.warning)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.amberAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Storage is nearly full. Oldest auto-cached tracks will be pruned when new music is streamed.',
                          style: TextStyle(
                            color: Colors.amber[200],
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              _buildSliderSetting(
                'Maximum Cache Size',
                '${cacheManager.maxCacheSizeMB} MB',
                cacheManager.maxCacheSizeMB.toDouble(),
                100,
                4096,
                (value) {
                  cacheManager.setMaxCacheSize(value.toInt() * 1024 * 1024);
                },
                divisions: 19,
              ),
              const SizedBox(height: 16),
              _buildSliderSetting(
                'Pre-download Next Tracks',
                '${cacheManager.preDownloadCount} tracks',
                cacheManager.preDownloadCount.toDouble(),
                0,
                5,
                (value) {
                  cacheManager.setPreDownloadCount(value.toInt());
                },
                divisions: 5,
              ),
              const SizedBox(height: 16),
              _buildSliderSetting(
                'Concurrent Downloads',
                '${cacheManager.maxConcurrentDownloads}',
                cacheManager.maxConcurrentDownloads.toDouble(),
                1,
                5,
                (value) {
                  cacheManager.setMaxConcurrentDownloads(value.toInt());
                },
                divisions: 4,
              ),
              Divider(color: Colors.grey[800], height: 32),
              _buildToggleSetting(
                'Auto-cache while playing',
                'Download tracks as you play them',
                cacheManager.autoCacheEnabled,
                (value) {
                  cacheManager.setAutoCacheEnabled(value);
                },
              ),
              const SizedBox(height: 12),
              _buildToggleSetting(
                'WiFi/Ethernet-only downloads',
                'Only download when connected to WiFi or Ethernet',
                cacheManager.wifiOnlyDownloads,
                (value) {
                  cacheManager.setWifiOnlyDownloads(value);
                },
              ),
              const SizedBox(height: 12),
              _buildToggleSetting(
                'Network-only mode',
                'Only stream tracks, no caching',
                cacheManager.networkOnlyMode,
                (value) {
                  cacheManager.setNetworkOnlyMode(value);
                },
              ),
              Divider(color: Colors.grey[800], height: 32),
              Row(
                children: [
                  if (isDesktop) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openAudioCacheFolder,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: const Text('Go to Folder'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[400],
                          side: BorderSide(color: Colors.grey[700]!),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DownloadsSettingsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Downloads'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[400],
                        side: BorderSide(color: Colors.grey[700]!),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showCacheDeleteDialog(),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[400],
                        side: BorderSide(color: Colors.red[700]!),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildSliderSetting(
    String label,
    String valueLabel,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.grey[800],
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.2),
            trackHeight: 4,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleSetting(
    String label,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    MetadataProvider provider,
    String name,
    IconData icon,
    Color accentColor,
  ) {
    final isConnected = provider.isAuthenticated;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (isConnected) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isConnected) ...[
                    IconButton(
                      icon: Icon(Icons.logout, color: Colors.grey[400]),
                      onPressed: () => _handleProviderLogout(provider),
                      tooltip: 'Logout',
                    ),
                  ] else ...[
                    IconButton(
                      icon: Icon(Icons.login, color: accentColor),
                      onPressed: () => _handleProviderLogin(provider),
                      tooltip: 'Login',
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (!isConnected) ...[
            const SizedBox(height: 12),
            Text(
              'Log in to sync your library and lyrics',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStylePreferenceRow() {
    final options = [AppStyle.Spotify, AppStyle.AppleMusic, AppStyle.Original];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Style',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  "Replicates a style you're familiar with",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Selector<PreferencesProvider, AppStyle>(
            selector: (context, prefs) => prefs.style,
            builder: (context, selectedStyle, child) {
              if (_isMobile) {
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showStyleSelectionSheet(selectedStyle, options),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedStyle.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: DropdownButton<AppStyle>(
                  value: selectedStyle,
                  mouseCursor: SystemMouseCursors.click,
                  items: options
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<PreferencesProvider>().setStyle(value);
                  },
                  dropdownColor: const Color(0xFF282828),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showStyleSelectionSheet(
    AppStyle selectedStyle,
    List<AppStyle> options,
  ) async {
    final selected = await showModalBottomSheet<AppStyle>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ...options.map(
                (style) => ListTile(
                  title: Text(
                    style.toString(),
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: style == selectedStyle
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(style),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == selectedStyle) {
      return;
    }

    await context.read<PreferencesProvider>().setStyle(selected);
  }

  Widget _buildAudioPreferenceRow() {
    return Consumer<PreferencesProvider>(
      builder: (context, prefs, child) {
        final crossfadeEnabled = prefs.crossfadeEnabled;
        final crossfadeDurationSeconds = prefs.crossfadeDurationSeconds;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gapless Playback',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          'Minimizes empty space between tracks',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: prefs.gaplessPlaybackEnabled,
                    onChanged: (value) async {
                      await context
                          .read<PreferencesProvider>()
                          .setGaplessPlaybackEnabled(value);
                      if (context.mounted) {
                        await context
                            .read<global_audio_player.WispAudioHandler>()
                            .setGaplessPlaybackEnabled(value);
                      }
                    },
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crossfade',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          'Seamlessly transition between songs',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: crossfadeEnabled,
                    onChanged: (value) async {
                      await context
                          .read<PreferencesProvider>()
                          .setCrossfadeEnabled(value);

                      if (context.mounted) {
                        await context
                            .read<global_audio_player.WispAudioHandler>()
                            .setCrossfadeEnabled(value);
                      }
                    },
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              if (crossfadeEnabled) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crossfade Duration',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Text(
                            'How long the crossfade lasts',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    /* const Spacer(), */
                    Text(
                      '${crossfadeDurationSeconds.toInt()}s',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: Colors.grey[800],
                    thumbColor: Theme.of(context).colorScheme.primary,
                    overlayColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: crossfadeDurationSeconds.clamp(1.0, 6.0),
                    min: 1,
                    max: 6,
                    divisions: 5,
                    onChanged: (value) async {
                      await context
                          .read<PreferencesProvider>()
                          .setCrossfadeDurationSeconds(value);
                      if (context.mounted) {
                        await context
                            .read<global_audio_player.WispAudioHandler>()
                            .setCrossfadeDurationSeconds(value);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandoffPreferenceRow() {
    return Consumer<PreferencesProvider>(
      builder: (context, prefs, child) {
        final options = const [
          HandoffSecurityLevel.keyExchange,
          HandoffSecurityLevel.pinBased,
        ];
        final selectedLevel = prefs.handoffSecurityLevel;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Security Level',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          'Determines how securely devices are authenticated for handoff',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_isMobile)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showHandoffSecuritySelectionSheet(
                        selectedLevel,
                        options,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _handoffSecurityPageLabel(selectedLevel),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SegmentedButton<HandoffSecurityLevel>(
                      segments: options
                          .map(
                            (level) => ButtonSegment<HandoffSecurityLevel>(
                              value: level,
                              label: Tooltip(
                                message: _handoffSecurityTooltip(level),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Text(level.label),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      selected: {selectedLevel},
                      onSelectionChanged: (selection) async {
                        await context
                            .read<PreferencesProvider>()
                            .setHandoffSecurityLevel(selection.first);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trusted Devices',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          'Devices that are auto-allowed for handoff',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _showTrustedDevicesDialog,
                    child: const Text('View'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showHandoffSecuritySelectionSheet(
    HandoffSecurityLevel selectedLevel,
    List<HandoffSecurityLevel> options,
  ) async {
    final selected = await showModalBottomSheet<HandoffSecurityLevel>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ...options.map(
                (level) => ListTile(
                  title: Text(
                    _handoffSecurityPageLabel(level),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _handoffSecuritySheetDescription(level),
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ),
                  trailing: level == selectedLevel
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(level),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == selectedLevel) {
      return;
    }

    await context.read<PreferencesProvider>().setHandoffSecurityLevel(selected);
  }

  Widget _buildAnimatedCanvasPreferenceRow() {
    return Selector<PreferencesProvider, bool>(
      selector: (context, prefs) => prefs.animatedCanvasEnabled,
      builder: (context, enabled, child) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Animated Canvas',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Text(
                      'Enable animated canvas rendering. This increases CPU usage, but looks better.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (value) {
                  context.read<PreferencesProvider>().setAnimatedCanvasEnabled(
                    value,
                  );
                },
                activeThumbColor: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPausedBackgroundWidgetsRow(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paused Background Widgets',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  'Widgets paused when app is in the background',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Paused Background Widgets'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Some background widgets are paused when the app is not in focus.\n'
                          'This saves CPU performance while you\'re doing other things, like gaming or streaming.\n'
                          'If you want some widgets to be active, because you have a multi-monitor setup, you can disable this for them below.',
                        ),
                        const SizedBox(height: 16),
                        Selector<
                          PreferencesProvider,
                          List<PausedBackgroundWidget>
                        >(
                          selector: (context, prefs) =>
                              prefs.pausedBackgroundWidgetsEnabled,
                          builder: (context, selectedWidgets, child) {
                            return Column(
                              children: PausedBackgroundWidget.values.map((
                                widget,
                              ) {
                                final isSelected = selectedWidgets.contains(
                                  widget,
                                );
                                return CheckboxListTile(
                                  title: Text(
                                    widget.displayName,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  value: isSelected,
                                  onChanged: (value) {
                                    final prefs = context
                                        .read<PreferencesProvider>();
                                    prefs.setPausedBackgroundWidgetsEnabled(
                                      isSelected
                                          ? selectedWidgets
                                                .where((w) => w != widget)
                                                .toList()
                                          : [...selectedWidgets, widget],
                                    );
                                  },
                                  activeColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  checkColor: Colors.white,
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Save'),
                      ),
                    ],
                  );
                },
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Manage',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllowWritingPreferenceRow() {
    return Selector<PreferencesProvider, bool>(
      selector: (context, prefs) => prefs.allowWriting,
      builder: (context, enabled, child) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Allow Writing',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Text(
                      'Allow modifications to playlists/library',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (value) {
                  context.read<PreferencesProvider>().setAllowWriting(value);
                },
                activeThumbColor: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDebugSection() {
    return Selector<PreferencesProvider, bool>(
      selector: (context, prefs) => prefs.debugModeEnabled,
      builder: (context, debugModeEnabled, child) {
        if (_isDesktop && !debugModeEnabled) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'DEBUG',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: _buildToggleSetting(
                'Debug Mode',
                'Enables debug features, such as the menu on the titlebar.\n A certain code is required to enable this feature.',
                debugModeEnabled,
                (value) {
                  context.read<PreferencesProvider>().setDebugModeEnabled(
                    value,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCreditsSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              spacing: 16,
              children: [
                Image.asset(
                  WispIcons.logo,
                  width: _isDesktop ? 96 : 32,
                  height: _isDesktop ? 96 : 32,
                  filterQuality: FilterQuality.high,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'wisp',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'made with <3 by wizeshi',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          UpdateWidget(),
        ],
      ),
    );
  }
}
