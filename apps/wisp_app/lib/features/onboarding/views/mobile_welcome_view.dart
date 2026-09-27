// Copyright © 2026 wizeshi

library;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source_manager.dart';
import 'package:wisp/data/sources/providers/provider_package_model.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/shell/widgets/app_shell.dart';

class MobileWelcomeView extends StatefulWidget {
  final AppLinks appLinks;
  final bool isFromSettings;

  const MobileWelcomeView({
    super.key,
    required this.appLinks,
    this.isFromSettings = false,
  });

  static Future<void> push(BuildContext context, {required AppLinks appLinks}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileWelcomeView(
          appLinks: appLinks,
          isFromSettings: true,
        ),
      ),
    );
  }

  @override
  State<MobileWelcomeView> createState() => _MobileWelcomeViewState();
}

class _MobileWelcomeViewState extends State<MobileWelcomeView> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  List<ProviderPackage> _catalog = [];
  final Set<String> _selectedProviderIds = {};
  bool _isLoadingCatalog = true;
  bool _isFinalizing = false;
  String _finalizingMessage = '';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoadingCatalog = true;
    });

    try {
      final prefs = context.read<PreferencesProvider>();
      final list =
          await ProvidersRepositoryService.instance.fetchCatalog(preferences: prefs);
      if (!mounted) return;
      setState(() {
        _catalog = list;
        // Pre-select all available providers by default
        _selectedProviderIds.addAll(list.map((p) => p.id));
        _isLoadingCatalog = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCatalog = false;
      });
    }
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isFinalizing = true;
      _finalizingMessage = 'Installing selected providers...';
    });

    final prefs = context.read<PreferencesProvider>();
    final repo = ProvidersRepositoryService.instance;

    for (final pkg in _catalog) {
      final isSelected = _selectedProviderIds.contains(pkg.id);
      if (isSelected) {
        if (!mounted) return;
        setState(() {
          _finalizingMessage = 'Installing ${pkg.name}...';
        });
        await repo.installOrUpdateProvider(pkg);
        await prefs.setProviderEnabled(pkg.id, true);
      } else {
        await prefs.setProviderEnabled(pkg.id, false);
      }
    }

    if (!mounted) return;
    setState(() {
      _finalizingMessage = 'Finalizing setup...';
    });

    await LyricsSourceManager.instance.reload();
    await prefs.setFirstBootCompleted(true);

    if (!mounted) return;

    if (widget.isFromSettings) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(appLinks: widget.appLinks),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_isFinalizing) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 24),
              Text(
                _finalizingMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Getting everything ready for you',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => _goToStep(_currentStep - 1),
              )
            : widget.isFromSettings
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentStep == 0 ? primaryColor : Colors.grey[700],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentStep == 1 ? primaryColor : Colors.grey[700],
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildSpotifyLoginStep(context),
          _buildProviderSelectStep(context),
        ],
      ),
    );
  }

  Widget _buildSpotifyLoginStep(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Consumer<MetadataManager>(
      builder: (context, spotify, _) {
        final isConnected = spotify.isAuthenticated;
        final isLoading = spotify.isLoading;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 1),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 38,
                      color: primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome to Wisp',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your self-hosted music experience with synchronized lyrics, modular extensions, and offline audio caching.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[400],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isConnected ? Colors.green.withValues(alpha: 0.4) : Colors.white12,
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.library_music,
                              color: Color(0xFF1DB954),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Spotify Integration',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isConnected
                                      ? 'Connected and synchronized'
                                      : 'Import your library and playlists',
                                  style: TextStyle(
                                    color: isConnected ? Colors.green[400] : Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isConnected)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 22,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isConnected) ...[
                        OutlinedButton.icon(
                          onPressed: () => spotify.logout(),
                          icon: const Icon(Icons.logout, size: 16),
                          label: const Text('Disconnect / Switch Account'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[400],
                            side: BorderSide(color: Colors.grey[700]!),
                            minimumSize: const Size.fromHeight(42),
                          ),
                        ),
                      ] else ...[
                        FilledButton.icon(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  try {
                                    await spotify.login(context);
                                  } catch (_) {}
                                },
                          icon: isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login, size: 18),
                          label: Text(
                            isLoading ? 'Connecting...' : 'Log in to Spotify',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                if (!isConnected) ...[
                  TextButton(
                    onPressed: () => _goToStep(1),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: () => _goToStep(1),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    isConnected ? 'Continue to Providers' : 'Next',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProviderSelectStep(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_isLoadingCatalog) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 16),
            const Text(
              'Fetching available providers...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Modular Providers',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Wisp loads synced lyrics and metadata using modular community extensions. '
              'Select which ones to pre-install. You can change these anytime in Settings.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[400],
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _catalog.isEmpty
                  ? Center(
                      child: Text(
                        'No providers found.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _catalog.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final pkg = _catalog[index];
                        final isSelected = _selectedProviderIds.contains(pkg.id);

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF181818),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor.withValues(alpha: 0.5)
                                  : Colors.white12,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedProviderIds.add(pkg.id);
                                } else {
                                  _selectedProviderIds.remove(pkg.id);
                                }
                              });
                            },
                            activeColor: primaryColor,
                            checkColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            title: Row(
                              children: [
                                Text(
                                  pkg.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'v${pkg.version}',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'by ${pkg.author}',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  pkg.description,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                                if (pkg.supportedSyncModes.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: pkg.supportedSyncModes.map((cap) {
                                      final isWord = cap.contains('word');
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isWord
                                              ? primaryColor.withValues(alpha: 0.15)
                                              : Colors.white.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isWord
                                                ? primaryColor.withValues(alpha: 0.4)
                                                : Colors.white12,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          cap,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isWord
                                                ? primaryColor
                                                : Colors.grey[300],
                                            fontWeight: isWord
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _completeOnboarding,
              icon: const Icon(Icons.check, size: 18),
              label: Text(
                'Finish Setup (${_selectedProviderIds.length} Selected)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
