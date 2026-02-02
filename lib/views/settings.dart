/// Settings page with Spotify authentication
library;

import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import '../providers/metadata/spotify.dart';
import '../services/credentials.dart';
import '../services/cache_manager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _credentialsService = CredentialsService();
  bool _hasCredentials = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final credentials = await _credentialsService.getSpotifyCredentials();
    if (credentials != null && mounted) {
      setState(() {
        _clientIdController.text = credentials.clientId;
        _clientSecretController.text = credentials.clientSecret;
        _hasCredentials = true;
      });
    }
  }

  Future<void> _saveCredentials() async {
    if (_clientIdController.text.isEmpty ||
        _clientSecretController.text.isEmpty) {
      _showSnackBar('Please enter both Client ID and Client Secret');
      return;
    }

    try {
      await _credentialsService.saveSpotifyCredentials(
        SpotifyCredentials(
          clientId: _clientIdController.text.trim(),
          clientSecret: _clientSecretController.text.trim(),
        ),
      );
      setState(() {
        _hasCredentials = true;
      });
      _showSnackBar('Credentials saved successfully');
    } catch (e) {
      _showSnackBar('Failed to save credentials: $e');
    }
  }

  Future<void> _handleLogin() async {
    final provider = context.read<SpotifyProvider>();
    try {
      await provider.login();
      if (mounted) {
        _showSnackBar('Successfully authenticated with Spotify!');
      }
    } on SpotifyCredentialsException catch (e) {
      _showSnackBar(e.message);
    } on SpotifyAuthException catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar('Login failed: $e');
    }
  }

  Future<void> _handleLogout() async {
    final provider = context.read<SpotifyProvider>();
    await provider.logout();
    if (mounted) {
      _showSnackBar('Logged out successfully');
    }
  }

  // Spotify lyrics cookie (sp_dc) is disabled for now.

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;

    if (isDesktop) {
      return SettingsContent(
        buildProviderCard: _buildProviderCard,
        buildCacheSettingsCard: _buildCacheSettingsCard,
        buildPreferenceRow: _buildPreferenceRow,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SettingsContent(
        buildProviderCard: _buildProviderCard,
        buildCacheSettingsCard: _buildCacheSettingsCard,
        buildPreferenceRow: _buildPreferenceRow,
      ),
    );
  }

  Widget _buildCacheSettingsCard(BuildContext context) {
    return ListenableBuilder(
      listenable: AudioCacheManager.instance,
      builder: (context, _) {
        final cacheManager = AudioCacheManager.instance;

        return Container(
          decoration: BoxDecoration(
            color: Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.all(20),
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
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Audio Cache',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${cacheManager.currentCacheSizeMB} MB / ${cacheManager.maxCacheSizeMB} MB used • ${cacheManager.cachedTrackCount} tracks',
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
              SizedBox(height: 20),

              // Cache size slider
              _buildSliderSetting(
                'Maximum Cache Size',
                '${cacheManager.maxCacheSizeMB} MB',
                cacheManager.maxCacheSizeMB.toDouble(),
                100,
                2048,
                (value) {
                  cacheManager.setMaxCacheSize(value.toInt() * 1024 * 1024);
                },
                divisions: 19,
              ),

              SizedBox(height: 16),

              // Pre-download count slider
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

              SizedBox(height: 16),

              // Concurrent downloads slider
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

              // Toggle settings
              _buildToggleSetting(
                'Auto-cache while playing',
                'Download tracks as you play them',
                cacheManager.autoCacheEnabled,
                (value) {
                  cacheManager.setAutoCacheEnabled(value);
                },
              ),

              SizedBox(height: 12),

              _buildToggleSetting(
                'WiFi-only downloads',
                'Only download when connected to WiFi',
                cacheManager.wifiOnlyDownloads,
                (value) {
                  cacheManager.setWifiOnlyDownloads(value);
                },
              ),

              SizedBox(height: 12),

              _buildToggleSetting(
                'Network-only mode',
                'Only play cached tracks (offline mode)',
                cacheManager.networkOnlyMode,
                (value) {
                  cacheManager.setNetworkOnlyMode(value);
                },
              ),

              Divider(color: Colors.grey[800], height: 32),

              // Cache management buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final count = await cacheManager.pruneExpiredCache();
                        if (context.mounted) {
                          _showSnackBar('Removed $count expired tracks');
                        }
                      },
                      icon: Icon(Icons.auto_delete_outlined, size: 18),
                      label: Text('Remove Expired'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[400],
                        side: BorderSide(color: Colors.grey[700]!),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showClearCacheDialog(context),
                      icon: Icon(Icons.delete_outline, size: 18),
                      label: Text('Clear All'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[400],
                        side: BorderSide(color: Colors.red[700]!),
                        padding: EdgeInsets.symmetric(vertical: 12),
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
            Text(label, style: TextStyle(color: Colors.white, fontSize: 14)),
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
        SizedBox(height: 8),
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
              Text(label, style: TextStyle(color: Colors.white, fontSize: 14)),
              SizedBox(height: 2),
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

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF282828),
        title: Text('Clear Cache', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will delete all cached audio files. You\'ll need to re-download tracks for offline playback.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await AudioCacheManager.instance.clearCache();
              if (mounted) {
                _showSnackBar('Cache cleared');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: Text('Clear'),
          ),
        ],
      ),
    );
  }

  // Spotify lyrics cookie UI removed for now.

  Widget _buildProviderCard(
    BuildContext context,
    SpotifyProvider provider,
    String name,
    IconData icon,
    Color accentColor,
  ) {
    final isConnected = provider.isAuthenticated;

    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isConnected ? Colors.green : Colors.red,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        isConnected ? 'Logged In' : 'Not Logged In',
                        style: TextStyle(
                          color: isConnected ? Colors.green : Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isConnected) ...[
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: Colors.grey[400]),
                      onPressed: () => _showCredentialsDialog(context),
                      tooltip: 'Edit credentials',
                    ),
                    IconButton(
                      icon: Icon(Icons.logout, color: Colors.grey[400]),
                      onPressed: _handleLogout,
                      tooltip: 'Logout',
                    ),
                  ] else ...[
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: Colors.grey[400]),
                      onPressed: () => _showCredentialsDialog(context),
                      tooltip: 'Edit credentials',
                    ),
                    IconButton(
                      icon: Icon(Icons.login, color: accentColor),
                      onPressed: _hasCredentials
                          ? _handleLogin
                          : () => _showCredentialsDialog(context),
                      tooltip: 'Login',
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (!isConnected && !_hasCredentials) ...[
            SizedBox(height: 12),
            Text(
              'Add your Spotify API credentials to get started',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreferenceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white, fontSize: 14)),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
          ],
        ),
      ],
    );
  }

  void _showCredentialsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF282828),
        title: Text(
          'Spotify Credentials',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _clientIdController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Client ID',
                labelStyle: TextStyle(color: Colors.grey[400]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _clientSecretController,
              style: TextStyle(color: Colors.white),
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Client Secret',
                labelStyle: TextStyle(color: Colors.grey[400]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () {
              _saveCredentials();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}

class SettingsContent extends StatelessWidget {
  final Widget Function(BuildContext, SpotifyProvider, String, IconData, Color)
  buildProviderCard;
  final Widget Function(BuildContext) buildCacheSettingsCard;
  final Widget Function(String, String) buildPreferenceRow;

  const SettingsContent({
    super.key,
    required this.buildProviderCard,
    required this.buildCacheSettingsCard,
    required this.buildPreferenceRow,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SpotifyProvider>(
      builder: (context, spotifyProvider, child) {
        return ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // Providers section
            Text(
              'PROVIDERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 16),

            // Spotify provider card
            buildProviderCard(
              context,
              spotifyProvider,
              'Spotify',
              Icons.graphic_eq,
              Theme.of(context).colorScheme.primary,
            ),

            SizedBox(height: 16),

            SizedBox(height: 32),

            // Cache section
            Text(
              'CACHE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 16),

            // Cache settings card
            buildCacheSettingsCard(context),
          ],
        );
      },
    );
  }
}
