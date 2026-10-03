// Copyright © 2026 wizeshi

library;

import 'package:app_links/app_links.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/data/sources/auth/js_auth_source.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source_manager.dart';
import 'package:wisp/data/sources/metadata/metadata_source_manager.dart';
import 'package:wisp/data/sources/providers/provider_package_model.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/shell/widgets/app_shell.dart';
import 'package:wisp/shared/widgets/display/provider_icon.dart';

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
  final Set<String> _selectedProviderKeys = {};
  bool _isLoadingCatalog = true;
  bool _isInstalling = false;
  String _installProgressMessage = '';
  bool _isFinalizing = false;
  String _finalizingMessage = '';
  final Map<String, bool> _loginInProgress = {};

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
      final list = await ProvidersRepositoryService.instance.fetchCatalog(
        preferences: prefs,
      );
      if (!mounted) return;
      final sortedList = List<ProviderPackage>.from(list)
        ..sort(ProviderPackage.comparePackages);
      setState(() {
        _catalog = sortedList;
        _selectedProviderKeys.clear();
        // Pre-select all available extensions by default
        _selectedProviderKeys.addAll(sortedList.map((p) => p.uniqueKey));
        _isLoadingCatalog = false;
      });
    } catch (e) {
      logger.d('[MobileWelcomeView] Failed to load catalog: $e');
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
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleSelection(String uniqueKey) {
    setState(() {
      if (_selectedProviderKeys.contains(uniqueKey)) {
        _selectedProviderKeys.remove(uniqueKey);
      } else {
        _selectedProviderKeys.add(uniqueKey);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedProviderKeys.addAll(_catalog.map((p) => p.uniqueKey));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedProviderKeys.clear();
    });
  }

  Future<void> _installSelectedAndProceed() async {
    if (_selectedProviderKeys.isEmpty) {
      _goToStep(1);
      return;
    }

    setState(() {
      _isInstalling = true;
      _installProgressMessage = 'Installing selected extensions...';
    });

    final prefs = context.read<PreferencesProvider>();
    final repo = ProvidersRepositoryService.instance;

    int current = 0;
    final total = _selectedProviderKeys.length;

    for (final pkg in _catalog) {
      final isSelected = _selectedProviderKeys.contains(pkg.uniqueKey);
      if (isSelected) {
        current++;
        if (mounted) {
          setState(() {
            _installProgressMessage =
                'Installing ${pkg.name} ($current/$total)...';
          });
        }
        await repo.installOrUpdateProvider(pkg);
        await prefs.setProviderEnabled(pkg.id, true, type: pkg.type);

        // Ensure dependent auth providers are enabled
        for (final dep in pkg.dependencies) {
          if (dep.startsWith('auth/')) {
            final authId = dep.substring('auth/'.length);
            await prefs.setProviderEnabled(authId, true, type: 'auth');
          }
        }
      } else {
        await prefs.setProviderEnabled(pkg.id, false, type: pkg.type);
      }
    }

    if (mounted) {
      setState(() {
        _installProgressMessage = 'Initializing services...';
      });
    }

    await AuthSourceManager.instance.reload();
    await MetadataSourceManager.instance.reload();
    await LyricsSourceManager.instance.reload();

    if (mounted) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(1);
      }
      setState(() {
        _currentStep = 1;
        _isInstalling = false;
      });
    }
  }

  Future<void> _handleLogin(JsAuthSource auth) async {
    setState(() {
      _loginInProgress[auth.id] = true;
    });
    try {
      await auth.login();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${auth.displayName}!'),
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loginInProgress[auth.id] = false;
        });
      }
    }
  }

  Future<void> _handleLogout(JsAuthSource auth) async {
    try {
      await auth.logout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logged out from ${auth.displayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e')),
        );
      }
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isFinalizing = true;
      _finalizingMessage = 'Finalizing setup...';
    });

    final prefs = context.read<PreferencesProvider>();
    await LyricsSourceManager.instance.reload();
    await MetadataSourceManager.instance.reload();
    await AuthSourceManager.instance.reload();
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

    return PopScope(
      canPop: widget.isFromSettings && _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentStep > 0) {
          _goToStep(_currentStep - 1);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: (_isFinalizing || _isInstalling)
            ? null
            : AppBar(
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
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: _currentStep == 0 ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color:
                            _currentStep == 0 ? primaryColor : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: _currentStep == 1 ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color:
                            _currentStep == 1 ? primaryColor : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                centerTitle: true,
              ),
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildProviderSelectStep(context),
                _buildAccountsLoginStep(context),
              ],
            ),
            if (_isFinalizing || _isInstalling)
              Container(
                color: const Color(0xFF121212),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: primaryColor),
                      const SizedBox(height: 24),
                      Text(
                        _isInstalling
                            ? _installProgressMessage
                            : _finalizingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isInstalling
                            ? 'Downloading and configuring extensions'
                            : 'Getting everything ready for you',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderSelectStep(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.extension_rounded,
                  size: 30,
                  color: primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Welcome to wisp',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'wisp uses modular extensions for streaming metadata, synchronized lyrics, and accounts. Select the providers you want to install.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[400],
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            if (_isLoadingCatalog)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: primaryColor),
                      const SizedBox(height: 16),
                      const Text(
                        'Discovering available extensions...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else if (_catalog.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        color: Colors.grey[600],
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No online extensions found.',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You can still stream music using the built-in YouTube engine.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _loadCatalog,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Text(
                    'EXTENSIONS (${_selectedProviderKeys.length}/${_catalog.length})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[500],
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selectedProviderKeys.length == _catalog.length
                        ? _deselectAll
                        : _selectAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      _selectedProviderKeys.length == _catalog.length
                          ? 'Deselect All'
                          : 'Select All',
                      style: TextStyle(fontSize: 12, color: primaryColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: _catalog.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final pkg = _catalog[index];
                    final isSelected =
                        _selectedProviderKeys.contains(pkg.uniqueKey);

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _toggleSelection(pkg.uniqueKey),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              ProviderIcon(
                                providerId: pkg.id,
                                type: pkg.type,
                                packagePath: pkg.path,
                                size: 30,
                                fallbackIcon: pkg.type == 'lyrics'
                                    ? Icons.mic
                                    : (pkg.type == 'auth'
                                        ? Icons.vpn_key
                                        : Icons.album),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          pkg.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Builder(
                                          builder: (context) {
                                            Color badgeColor;
                                            switch (pkg.type.toLowerCase()) {
                                              case 'metadata':
                                                badgeColor = Colors.purpleAccent;
                                                break;
                                              case 'lyrics':
                                                badgeColor = Colors.cyanAccent;
                                                break;
                                              case 'auth':
                                                badgeColor = Colors.amberAccent;
                                                break;
                                              default:
                                                badgeColor = Colors.grey[400]!;
                                            }
                                            return Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                pkg.type.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: badgeColor,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'v${pkg.version}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      pkg.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (pkg.supportedSyncModes.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: pkg.supportedSyncModes.map((
                                          cap,
                                        ) {
                                          final isWord = cap.contains('word');
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isWord
                                                  ? primaryColor.withValues(
                                                      alpha: 0.15,
                                                    )
                                                  : Colors.white.withValues(
                                                      alpha: 0.06,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              cap,
                                              style: TextStyle(
                                                fontSize: 9,
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
                              const SizedBox(width: 8),
                              Checkbox(
                                value: isSelected,
                                onChanged: (_) =>
                                    _toggleSelection(pkg.uniqueKey),
                                activeColor: primaryColor,
                                checkColor: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _installSelectedAndProceed,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                _selectedProviderKeys.isEmpty
                    ? 'Continue without Extensions'
                    : 'Install & Continue (${_selectedProviderKeys.length})',
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
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => _goToStep(1),
                child: Text(
                  'Skip extension installation',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsLoginStep(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Consumer<PreferencesProvider>(
      builder: (context, prefs, _) {
        return ListenableBuilder(
          listenable: AuthSourceManager.instance,
          builder: (context, _) {
            final authSources = AuthSourceManager.instance.sources.values
                .where((auth) => prefs.isProviderEnabled(auth.id, type: 'auth'))
                .toList();

            final anyNotConnected =
                authSources.any((auth) => !auth.isAuthenticated);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.manage_accounts_rounded,
                          size: 30,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Connect Your Accounts',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Log in to sync your library, playlists, and synchronized lyrics. You can also sign in anytime later in Settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[400],
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: authSources.isEmpty
                          ? Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF181818),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline_rounded,
                                      color: Colors.greenAccent,
                                      size: 46,
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      'No Accounts Required',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Your installed extensions stream music and lyrics anonymously without an account login.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: authSources.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final auth = authSources[index];

                                return ListenableBuilder(
                                  listenable: auth,
                                  builder: (context, _) {
                                    final isConnected = auth.isAuthenticated;
                                    final isLoggingIn =
                                        _loginInProgress[auth.id] == true;

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF181818),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isConnected
                                              ? Colors.green.withValues(
                                                  alpha: 0.4,
                                                )
                                              : Colors.white12,
                                          width: 1,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              ProviderIcon(
                                                providerId: auth.id,
                                                type: 'auth',
                                                packagePath: 'auth/${auth.id}',
                                                size: 34,
                                                fallbackIcon:
                                                    Icons.account_circle,
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          auth.displayName,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        if (isConnected) ...[
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          const Icon(
                                                            Icons.check_circle,
                                                            color: Colors.green,
                                                            size: 16,
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      isConnected
                                                          ? 'Connected and synchronized'
                                                          : 'Import playlists, library, and lyrics',
                                                      style: TextStyle(
                                                        color: isConnected
                                                            ? Colors.green[400]
                                                            : Colors.grey[400],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          if (isConnected) ...[
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _handleLogout(auth),
                                              icon: const Icon(
                                                Icons.logout,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Disconnect / Switch Account',
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.grey[400],
                                                side: BorderSide(
                                                  color: Colors.grey[700]!,
                                                ),
                                                minimumSize:
                                                    const Size.fromHeight(42),
                                              ),
                                            ),
                                          ] else ...[
                                            FilledButton.icon(
                                              onPressed: isLoggingIn
                                                  ? null
                                                  : () => _handleLogin(auth),
                                              icon: isLoggingIn
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.login,
                                                      size: 18,
                                                    ),
                                              label: Text(
                                                isLoggingIn
                                                    ? 'Connecting...'
                                                    : 'Log in to ${auth.displayName}',
                                              ),
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    auth.id == 'spotify'
                                                        ? const Color(0xFF1DB954)
                                                        : primaryColor,
                                                foregroundColor: Colors.white,
                                                minimumSize:
                                                    const Size.fromHeight(44),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _completeOnboarding,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Start Listening',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (anyNotConnected && authSources.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: _completeOnboarding,
                          child: Text(
                            'Skip for now',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
