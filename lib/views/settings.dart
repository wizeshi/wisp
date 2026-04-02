/// Settings page with Spotify authentication
library;

import 'dart:io' show Directory, Platform, Process;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:wisp/models/metadata_provider.dart';
import 'package:wisp/providers/audio/youtube.dart';
import 'package:wisp/providers/lyrics/provider.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';
import '../providers/library/local_playlists.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/cache_manager.dart';
import '../services/metadata_cache.dart';
import '../services/navigation_history.dart';
import 'settings_downloads.dart';
import '../utils/logger.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _showProviderPreferencesDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
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
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
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
                              activeThumbColor:
                                  Theme.of(context).colorScheme.primary,
                              onChanged: (enabled) async {
                                final hasAny = enabled || prefs.metadataYouTubeEnabled;
                                await prefs.setMetadataSpotifyEnabled(enabled);
                                if (!hasAny) {
                                  _showSnackBar(
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
                              activeThumbColor:
                                  Theme.of(context).colorScheme.primary,
                              onChanged: (enabled) async {
                                final hasAny = enabled || prefs.metadataSpotifyEnabled;
                                await prefs.setMetadataYouTubeEnabled(enabled);
                                if (!hasAny) {
                                  _showSnackBar(
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
                              activeThumbColor:
                                  Theme.of(context).colorScheme.primary,
                              onChanged: (enabled) async {
                                final hasAny = enabled || prefs.audioSpotifyEnabled;
                                await prefs.setAudioYouTubeEnabled(enabled);
                                if (!hasAny) {
                                  _showSnackBar(
                                    'Warning: all Audio providers are disabled.',
                                  );
                                }
                              },
                            ),
                            SwitchListTile.adaptive(
                              title: const Text(
                                'Spotify (EXPERIMENTAL)',
                                style: TextStyle(color: Colors.white),
                              ),
                              value: prefs.audioSpotifyEnabled,
                              activeThumbColor:
                                  Theme.of(context).colorScheme.primary,
                              onChanged: (enabled) async {
                                final hasAny = enabled || prefs.audioYouTubeEnabled;
                                await prefs.setAudioSpotifyEnabled(enabled);
                                if (!hasAny) {
                                  _showSnackBar(
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
                              activeThumbColor:
                                  Theme.of(context).colorScheme.primary,
                              onChanged: (enabled) async {
                                final hasAny = enabled || prefs.lyricsSpotifyEnabled;
                                await prefs.setLyricsLrclibEnabled(enabled);
                                if (!hasAny) {
                                  _showSnackBar(
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
                              activeThumbColor:
                                  Theme.of(context).colorScheme.primary,
                              onChanged: (enabled) async {
                                final hasAny = enabled || prefs.lyricsLrclibEnabled;
                                await prefs.setLyricsSpotifyEnabled(enabled);
                                if (!hasAny) {
                                  _showSnackBar(
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _deleteCacheByType(String type) async {
    try {
      switch (type) {
        case 'audio':
          await AudioCacheManager.instance.clearCache();
          return true;

        case 'metadata':
          await MetadataCacheStore.instance.clearProvider('spotify');
          await MetadataCacheStore.instance.clearProvider('spotify_internal');
          await MetadataCacheStore.instance.clearProvider('youtube');
          return true;

        case 'yt-sp-link':
          await YouTubeProvider.clearVideoIdCache();
          return true;

        case 'lyrics':
          await context.read<LyricsProvider>().clearCache();
          return true;
      }
    } catch (e) {
      logger.e('[Views/Settings] Failed to delete $type cache: $e');
      return false;
    }
    // Shouldn't reach here since the options are fixed, but the linter complains without a return
    return false;
  }

  Future<void> _showCacheDeleteDialog() async {
    const Map<String, String> cacheTypes = {
      'audio': 'Audio',
      'metadata': 'Metadata',
      'lyrics': 'Lyrics',
      'yt-sp-link': 'Youtube - Spotify Link'
    };

    // Dynamically create a map using the types above, as to not have
    // to update both code sections when adding new cache types
    Map<String, bool> cacheDeleteEnabled = cacheTypes.map((key, value) => MapEntry(key, false));
    
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF282828),
              title: const Text(
                'Provider Preferences',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: cacheTypes.entries.map((entry) {
                        return SwitchListTile.adaptive(
                          title: Text(
                            entry.value,
                            style: const TextStyle(color: Colors.white),
                          ),
                          value: cacheDeleteEnabled[entry.key]!,
                          onChanged: (value) {
                            setState(() {
                              cacheDeleteEnabled[entry.key] = value;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (var key in cacheDeleteEnabled.keys) {
                        cacheDeleteEnabled[key] = false;
                      }
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    var hadFailure = false;
                    for (var key in cacheDeleteEnabled.keys) {
                      if (cacheDeleteEnabled[key] == true) {
                        final success = await _deleteCacheByType(key);
                        if (!success) {
                          hadFailure = true;
                        }
                      }
                    }
                    if (mounted) {
                      _showSnackBar(
                        hadFailure
                            ? 'Some selected caches could not be deleted.'
                            : 'Selected caches deleted.',
                      );
                    }
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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

  void _showSnackBar(String message) {
    if (!mounted) return;
    final localMessenger = ScaffoldMessenger.maybeOf(context);
    if (localMessenger != null) {
      localMessenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final rootContext = NavigationHistory.instance.navigatorKey.currentContext;
    final rootMessenger =
        rootContext == null ? null : ScaffoldMessenger.maybeOf(rootContext);
    rootMessenger?.showSnackBar(SnackBar(content: Text(message)));
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
      buildAnimatedCanvasRow: _buildAnimatedCanvasPreferenceRow,
      buildAllowWritingRow: _buildAllowWritingPreferenceRow,
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
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Audio Cache',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${cacheManager.currentCacheSizeMB} MB / '
                          '${cacheManager.maxCacheSizeMB} MB used '
                          '• ${cacheManager.cachedTrackCount} tracks',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
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
            overlayColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
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
    final options = ['Spotify', 'Apple Music', 'YouTube Music'];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Style', style: TextStyle(color: Colors.white, fontSize: 14)),
          Selector<PreferencesProvider, String>(
            selector: (context, prefs) => prefs.style,
            builder: (context, selectedStyle, child) {
              if (_isMobile) {
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showStyleSelectionSheet(selectedStyle, options),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedStyle,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
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
                child: DropdownButton<String>(
                  value: selectedStyle,
                  mouseCursor: SystemMouseCursors.click,
                  items: options
                      .map((style) => DropdownMenuItem(
                            value: style,
                            child: Text(
                              style,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ))
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
    String selectedStyle,
    List<String> options,
  ) async {
    final selected = await showModalBottomSheet<String>(
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
                    style,
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
                child: Text(
                  'Animated Canvas',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (value) {
                  context
                      .read<PreferencesProvider>()
                      .setAnimatedCanvasEnabled(value);
                },
                activeThumbColor: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        );
      },
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
                child: Text(
                  'Allow Writing',
                  style: TextStyle(color: Colors.white, fontSize: 14),
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
}

class SettingsContent extends StatelessWidget {
  final Widget Function(BuildContext, MetadataProvider, String, IconData, Color)
      buildProviderCard;
  final Widget Function(BuildContext) buildCacheSettingsCard;
  final Widget Function() buildStylePreferenceRow;
  final Widget Function() buildAnimatedCanvasRow;
  final Widget Function() buildAllowWritingRow;
  final void Function(String) showSnackBar;
  final VoidCallback onEditProviderPreferences;

  const SettingsContent({
    super.key,
    required this.buildProviderCard,
    required this.buildCacheSettingsCard,
    required this.buildStylePreferenceRow,
    required this.buildAnimatedCanvasRow,
    required this.buildAllowWritingRow,
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
                child:
                    Text('No trashed playlists', style: TextStyle(color: Colors.grey[500])),
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
                    title: Text(p.title, style: const TextStyle(color: Colors.white)),
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
                          icon: Icon(Icons.delete_outline, color: Colors.red[400]),
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
              Expanded(
                child: Text(
                  'Recover a provider playlist by ID',
                  style: TextStyle(color: Colors.grey[300]),
                ),
              ),
              OutlinedButton(
                onPressed: () async {
                  final idController = TextEditingController();
                  final ok = await showDialog<bool>(
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
                    await context
                        .read<LocalPlaylistState>()
                        .unhideProviderPlaylist(providerId);
                    showSnackBar('Provider id unhidden — open provider playlist to restore');
                  }
                },
                child: const Text('Unhide'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}