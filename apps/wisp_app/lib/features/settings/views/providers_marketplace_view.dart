// Copyright © 2026 wizeshi

library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/sources/audio/audio_source_manager.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/sources/providers/provider_package_model.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/data/sources/providers/provider_dependency_validator.dart';
import 'package:wisp/shared/widgets/display/provider_icon.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert_extensions.dart';

class ProvidersMarketplaceView extends StatefulWidget {
  final List<ProviderPackage>? initialPackages;

  const ProvidersMarketplaceView({super.key, this.initialPackages});

  static Future<void> push(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProvidersMarketplaceView()));
  }

  @override
  State<ProvidersMarketplaceView> createState() =>
      _ProvidersMarketplaceViewState();
}

class _ProvidersMarketplaceViewState extends State<ProvidersMarketplaceView> {
  final ProvidersRepositoryService _repoService =
      ProvidersRepositoryService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<ProviderPackage> _packages = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  final Set<String> _busyProviderIds = {};
  bool _isUpdatingAll = false;

  @override
  void initState() {
    super.initState();
    final initialPackages = widget.initialPackages;
    if (initialPackages != null) {
      _packages = List<ProviderPackage>.from(initialPackages);
      _isLoading = false;
    } else {
      _loadCatalog();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = context.read<PreferencesProvider>();
      final list = await _repoService.fetchCatalog(preferences: prefs);
      if (!mounted) return;
      setState(() {
        _packages = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load providers: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _installOrUpdate(ProviderPackage pkg) async {
    setState(() => _busyProviderIds.add(pkg.uniqueKey));
    final success = await _repoService.installOrUpdateProvider(pkg);
    if (!mounted) return;
    setState(() => _busyProviderIds.remove(pkg.uniqueKey));

    if (success) {
      context.showSuccessAlert('${pkg.name} installed successfully!');
      _loadCatalog();
    } else {
      context.showErrorAlert('Failed to install ${pkg.name}');
    }
  }

  Future<void> _updateAll() async {
    final updates = _packages.where((p) => p.hasUpdate).toList();
    if (updates.isEmpty) return;

    setState(() {
      _isUpdatingAll = true;
      for (final p in updates) {
        _busyProviderIds.add(p.uniqueKey);
      }
    });

    int count = 0;
    for (final pkg in updates) {
      final ok = await _repoService.installOrUpdateProvider(pkg);
      if (ok) count++;
      if (mounted) {
        setState(() => _busyProviderIds.remove(pkg.uniqueKey));
      }
    }

    if (!mounted) return;
    setState(() => _isUpdatingAll = false);

    context.showSuccessAlert('Updated $count of ${updates.length} providers.');
    _loadCatalog();
  }

  Future<void> _uninstall(ProviderPackage pkg) async {
    final prefs = context.read<PreferencesProvider>();
    final activeDependents =
        await ProviderDependencyValidator.getActiveDependentsOf(
      type: pkg.type,
      id: pkg.id,
      preferences: prefs,
    );

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surfaceElevated,
        title: Text('Uninstall ${pkg.name}?'),
        content: Text(
          activeDependents.isNotEmpty
              ? 'Warning: The following active providers depend on ${pkg.name} and will stop functioning:\n\n'
                  '${activeDependents.map((d) => '• ${d.name} (${d.type})').join('\n')}\n\n'
                  'Are you sure you want to remove ${pkg.name}?'
              : 'Are you sure you want to remove ${pkg.name}?',
        ),
        actions: [
          GenericFilledButton(
            backgroundColor: Colors.red[700],
            foregroundColor: Colors.white,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Uninstall'),
          ),
          GenericTextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _busyProviderIds.add(pkg.uniqueKey));
    final success = await _repoService.uninstallProvider(pkg);
    if (!mounted) return;
    setState(() => _busyProviderIds.remove(pkg.uniqueKey));

    if (success) {
      context.showSuccessAlert('${pkg.name} uninstalled.');
      _loadCatalog();
    } else {
      context.showErrorAlert('Failed to uninstall ${pkg.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final primaryColor = theme.colorScheme.primary;
    final amberAccent = colors.isDark ? Colors.amber : Colors.amber[800]!;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final horizontalPadding = isMobile ? 16.0 : 20.0;

    final updateCount = _packages.where((pkg) => pkg.hasUpdate).length;

    final filtered = _packages.where((pkg) {
      if (_selectedFilter.startsWith('Updates') && !pkg.hasUpdate) return false;
      if (_selectedFilter == 'Metadata' && pkg.type != 'metadata') return false;
      if (_selectedFilter == 'Audio' && pkg.type != 'audio') return false;
      if (_selectedFilter == 'Lyrics' && pkg.type != 'lyrics') return false;
      if (_selectedFilter == 'Auth' && pkg.type != 'auth') return false;
      if (_selectedFilter == 'Installed' && !pkg.isInstalled) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = pkg.name.toLowerCase().contains(query);
        final matchesDesc = pkg.description.toLowerCase().contains(query);
        final matchesAuthor = pkg.author.toLowerCase().contains(query);
        return matchesName || matchesDesc || matchesAuthor;
      }
      return true;
    }).toList();

    filtered.sort(ProviderPackage.comparePackages);

    final filterTabs = <String>['All'];
    if (updateCount > 0) {
      filterTabs.add('Updates ($updateCount)');
    }
    filterTabs.addAll(['Metadata', 'Audio', 'Lyrics', 'Auth', 'Installed']);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: Text(
          'Providers Marketplace',
          style: isMobile ? const TextStyle(fontSize: 18) : null,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          GenericIconButton(
            tooltip: 'Provider Priority Order',
            icon: const Icon(Icons.low_priority),
            onPressed: () => _showPriorityOrderDialog(context),
          ),
          GenericIconButton(
            tooltip: 'Refresh catalog',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadCatalog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter header
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search providers...',
                hintStyle: TextStyle(color: colors.textMuted),
                prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: Icon(Icons.close, color: colors.textMuted, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colors.inputFill,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
          SizedBox(
            height: 44,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                8,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < filterTabs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Builder(
                      builder: (_) {
                        final filter = filterTabs[i];
                        final isSelected =
                            _selectedFilter == filter ||
                            (_selectedFilter.startsWith('Updates') &&
                                filter.startsWith('Updates'));
                        final isUpdateTab = filter.startsWith('Updates');
                        final chipColor =
                            isUpdateTab ? amberAccent : primaryColor;

                        return ChoiceChip(
                          label: Text(filter),
                          selected: isSelected,
                          selectedColor: chipColor.withValues(alpha: 0.22),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? (isUpdateTab
                                    ? amberAccent
                                    : colors.textPrimary)
                                : colors.textSecondary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          backgroundColor: colors.surface,
                          side: BorderSide(
                            color: isSelected ? chipColor : colors.borderSubtle,
                          ),
                          onSelected: (_) =>
                              setState(() => _selectedFilter = filter),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(color: colors.borderSubtle, height: 1),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        GenericFilledButton.icon(
                          onPressed: _loadCatalog,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      _selectedFilter.startsWith('Updates')
                          ? 'All installed providers are up to date.'
                          : 'No providers found.',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  )
                : WispListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      isMobile ? 12 : 20,
                      horizontalPadding,
                      MediaQuery.paddingOf(context).bottom +
                          (isMobile ? 96 : 20),
                    ),
                    itemCount:
                        filtered.length +
                        ((updateCount > 0 &&
                                !_selectedFilter.startsWith('Updates'))
                            ? 1
                            : 0),
                    separatorBuilder: (_, _) =>
                        SizedBox(height: isMobile ? 12 : 16),
                    itemBuilder: (context, index) {
                      if (updateCount > 0 &&
                          !_selectedFilter.startsWith('Updates')) {
                        if (index == 0) {
                          return _buildUpdatesBanner(
                            updateCount,
                            isMobile: isMobile,
                          );
                        }
                        return _buildProviderCard(
                          filtered[index - 1],
                          primaryColor,
                          isMobile: isMobile,
                        );
                      }
                      return _buildProviderCard(
                        filtered[index],
                        primaryColor,
                        isMobile: isMobile,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesBanner(int updateCount, {required bool isMobile}) {
    final colors = context.colors;
    final amberAccent = colors.isDark ? Colors.amber : Colors.amber[800]!;

    final infoRow = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: amberAccent.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.system_update_alt,
            color: amberAccent,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$updateCount ${updateCount == 1 ? "provider update" : "provider updates"} available',
                style: TextStyle(
                  color: amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Install updates to get the latest sources and fixes.',
                style: TextStyle(
                  color: colors.isDark ? Colors.amber[200] : Colors.amber[900],
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final updateAllButton = GenericFilledButton.icon(
      onPressed: _isUpdatingAll ? null : _updateAll,
      backgroundColor: Colors.amber[700],
      foregroundColor: Colors.black,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      icon: _isUpdatingAll
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            )
          : const Icon(Icons.download, size: 16),
      label: const Text(
        'Update All',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: amberAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: amberAccent.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoRow,
                const SizedBox(height: 12),
                updateAllButton,
              ],
            )
          : Row(
              children: [
                Expanded(child: infoRow),
                const SizedBox(width: 12),
                updateAllButton,
              ],
            ),
    );
  }

  Future<void> _toggleProviderEnabled(
    ProviderPackage pkg,
    bool val,
    PreferencesProvider prefs,
  ) async {
    if (!val) {
      final activeDependents = await ProviderDependencyValidator.getActiveDependentsOf(
        type: pkg.type,
        id: pkg.id,
        preferences: prefs,
      );
      if (activeDependents.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ctx.colors.surfaceElevated,
            title: Text('Disable ${pkg.name}?'),
            content: Text(
              'The following active providers depend on ${pkg.name} and will also be disabled:\n\n'
              '${activeDependents.map((d) => '• ${d.name} (${d.type})').join('\n')}\n\n'
              'Do you want to proceed?',
            ),
            actions: [
              GenericFilledButton(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Disable All'),
              ),
              GenericTextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        for (final dep in activeDependents) {
          await prefs.setProviderEnabled(dep.id, false, type: dep.type);
        }
      }
    }
    await prefs.setProviderEnabled(pkg.id, val, type: pkg.type);
    _loadCatalog();
  }

  Widget _buildProviderIconBox(
    BuildContext context,
    ProviderPackage pkg,
    Color primaryColor,
    Color amberAccent,
  ) {
    final colors = context.colors;
    final hasUpdate = pkg.hasUpdate;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (hasUpdate ? amberAccent : primaryColor)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: ProviderIcon(
            providerId: pkg.id,
            type: pkg.type,
            size: 24,
            fallbackIcon: pkg.type == 'lyrics'
                ? Icons.mic
                : pkg.type == 'auth'
                    ? Icons.vpn_key
                    : pkg.type == 'audio'
                        ? Icons.graphic_eq
                        : Icons.extension,
            color: hasUpdate ? amberAccent : primaryColor,
          ),
        ),
        if (hasUpdate)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 12,
              height: 12,
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
    );
  }

  Widget _buildVersionChip(BuildContext context, ProviderPackage pkg) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        pkg.isInstalled
            ? 'v${pkg.installedVersion ?? pkg.version}'
            : 'v${pkg.version}',
        style: TextStyle(fontSize: 11, color: colors.textSecondary),
      ),
    );
  }

  Widget _buildUpdateChip(ProviderPackage pkg, Color amberAccent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: amberAccent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: amberAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward, size: 10, color: amberAccent),
          const SizedBox(width: 2),
          Text(
            'v${pkg.version} available',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: amberAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepoVersionChip(BuildContext context, ProviderPackage pkg) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
      ),
      child: Text(
        'repo: v${pkg.version}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colors.isDark ? Colors.blue[200] : Colors.blue[800],
        ),
      ),
    );
  }

  Widget _buildProviderCard(
    ProviderPackage pkg,
    Color primaryColor, {
    required bool isMobile,
  }) {
    final isBusy = _busyProviderIds.contains(pkg.uniqueKey);
    final prefs = context.watch<PreferencesProvider>();
    final colors = context.colors;
    final amberAccent = colors.isDark ? Colors.amber : Colors.amber[800]!;
    final isEnabled = prefs.isProviderEnabled(pkg.id, type: pkg.type);
    final hasUpdate = pkg.hasUpdate;
    final showRepoChip =
        !hasUpdate &&
        pkg.isInstalled &&
        pkg.installedVersion != null &&
        ProviderPackage.isNewerVersion(pkg.installedVersion!, pkg.version);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        border: Border.all(
          color: hasUpdate
              ? amberAccent.withValues(alpha: 0.7)
              : colors.borderSubtle,
          width: hasUpdate ? 1.5 : 1.0,
        ),
      ),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProviderIconBox(context, pkg, primaryColor, amberAccent),
              SizedBox(width: isMobile ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isMobile) ...[
                      Text(
                        pkg.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'by ${pkg.author}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                          ),
                          _buildVersionChip(context, pkg),
                          if (hasUpdate)
                            _buildUpdateChip(pkg, amberAccent)
                          else if (showRepoChip)
                            _buildRepoVersionChip(context, pkg),
                        ],
                      ),
                    ] else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            pkg.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          _buildVersionChip(context, pkg),
                          if (hasUpdate)
                            _buildUpdateChip(pkg, amberAccent)
                          else if (showRepoChip)
                            _buildRepoVersionChip(context, pkg),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'by ${pkg.author}',
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 12),
                if (isBusy)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!pkg.isInstalled)
                  GenericFilledButton.icon(
                    onPressed: () => _installOrUpdate(pkg),
                    backgroundColor: primaryColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Install'),
                  )
                else if (hasUpdate)
                  GenericFilledButton.icon(
                    onPressed: () => _installOrUpdate(pkg),
                    backgroundColor: Colors.amber[700],
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    icon: const Icon(Icons.system_update_alt, size: 16),
                    label: const Text(
                      'Update',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: isEnabled,
                        activeThumbColor: primaryColor,
                        onChanged: (val) =>
                            _toggleProviderEnabled(pkg, val, prefs),
                      ),
                      GenericIconButton(
                        tooltip: 'Uninstall',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () => _uninstall(pkg),
                      ),
                    ],
                  ),
              ],
            ],
          ),
          SizedBox(height: isMobile ? 10 : 12),
          Text(
            pkg.description,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.35,
            ),
            maxLines: isMobile ? 3 : null,
            overflow: isMobile ? TextOverflow.ellipsis : null,
          ),
          SizedBox(height: isMobile ? 10 : 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildBadge(pkg.type.toUpperCase(), Colors.blueGrey),
              _buildBadge('Priority: ${pkg.priority}', Colors.deepPurple),
              ...pkg.supportedSyncModes.map(
                (mode) => _buildBadge(
                  mode,
                  mode == 'word'
                      ? Colors.teal
                      : mode == 'line'
                      ? Colors.indigo
                      : Colors.grey,
                ),
              ),
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: 10),
            if (isBusy)
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasUpdate ? 'Updating...' : 'Installing...',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              )
            else if (!pkg.isInstalled)
              SizedBox(
                width: double.infinity,
                child: GenericFilledButton.icon(
                  onPressed: () => _installOrUpdate(pkg),
                  backgroundColor: primaryColor,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Install'),
                ),
              )
            else if (hasUpdate)
              Row(
                children: [
                  Expanded(
                    child: GenericFilledButton.icon(
                      onPressed: () => _installOrUpdate(pkg),
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.black,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      icon: const Icon(Icons.system_update_alt, size: 16),
                      label: const Text(
                        'Update',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GenericIconButton(
                    tooltip: 'Uninstall',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () => _uninstall(pkg),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Switch.adaptive(
                    value: isEnabled,
                    activeThumbColor: primaryColor,
                    onChanged: (val) => _toggleProviderEnabled(pkg, val, prefs),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isEnabled ? 'Enabled' : 'Disabled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isEnabled
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GenericTextButton.icon(
                    onPressed: () => _uninstall(pkg),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    label: const Text(
                      'Uninstall',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String label, MaterialColor color) {
    final isDark = context.colors.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark ? color[200] : color[800],
        ),
      ),
    );
  }

  void _showPriorityOrderDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ProviderPriorityDialog(
        packages: _packages.where((p) => p.isInstalled).toList(),
      ),
    );
  }
}

class _ProviderPriorityDialog extends StatefulWidget {
  final List<ProviderPackage> packages;

  const _ProviderPriorityDialog({required this.packages});

  @override
  State<_ProviderPriorityDialog> createState() => _ProviderPriorityDialogState();
}

class _ProviderPriorityDialogState extends State<_ProviderPriorityDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      backgroundColor: colors.surfaceElevated,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 550),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Provider Priority & Fallbacks',
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GenericIconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Drag items to set priority order. The top provider is the active one; subsequent providers act as fallbacks.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: isMobile
                    ? const [
                        Tab(text: 'Metadata'),
                        Tab(text: 'Audio'),
                        Tab(text: 'Lyrics'),
                      ]
                    : const [
                        Tab(text: 'Metadata Providers'),
                        Tab(text: 'Audio Providers'),
                        Tab(text: 'Lyrics Providers'),
                      ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrderTab('metadata'),
                    _buildOrderTab('audio'),
                    _buildOrderTab('lyrics'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderTab(String type) {
    final prefs = context.watch<PreferencesProvider>();
    final customOrder = prefs.getProviderOrder(type);

    final List<_ProviderPriorityItem> items = [];
    final seenIds = <String>{};

    for (final p in widget.packages.where((p) => p.type == type)) {
      final id = p.id.toLowerCase();
      seenIds.add(id);
      items.add(_ProviderPriorityItem(
        id: id,
        name: p.name,
        type: p.type,
        priority: p.priority,
        uniqueKey: p.uniqueKey,
      ));
    }

    if (type == 'metadata') {
      try {
        final metaManager = context.watch<MetadataManager>();
        for (final provider in metaManager.allProviders) {
          final id = provider.providerId.toLowerCase();
          if (!seenIds.contains(id)) {
            seenIds.add(id);
            items.add(_ProviderPriorityItem(
              id: id,
              name: provider.displayName.isNotEmpty
                  ? provider.displayName
                  : provider.name,
              type: 'metadata',
              priority: 50,
              uniqueKey: 'metadata/$id',
            ));
          }
        }
      } catch (_) {}

      if (!seenIds.contains('youtube')) {
        seenIds.add('youtube');
        items.add(const _ProviderPriorityItem(
          id: 'youtube',
          name: 'YouTube',
          type: 'metadata',
          priority: 50,
          uniqueKey: 'metadata/youtube',
        ));
      }
    }

    if (type == 'audio') {
      try {
        final audioManager = AudioSourceManager.instance;
        for (final source in audioManager.allSources) {
          final id = source.id.toLowerCase();
          if (!seenIds.contains(id)) {
            seenIds.add(id);
            items.add(_ProviderPriorityItem(
              id: id,
              name: source.name,
              type: 'audio',
              priority: source.priority,
              uniqueKey: 'audio/$id',
            ));
          }
        }
      } catch (_) {}
    }

    if (items.isEmpty) {
      return Center(
        child: Text(
          'No installed $type providers found.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    // Sort according to customOrder, otherwise manifest priority descending
    items.sort((a, b) {
      if (customOrder.isNotEmpty) {
        final aIdx = customOrder.indexOf(a.id.toLowerCase());
        final bIdx = customOrder.indexOf(b.id.toLowerCase());
        if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
        if (aIdx != -1) return -1;
        if (bIdx != -1) return 1;
      }
      return b.priority.compareTo(a.priority);
    });

    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final list = List<_ProviderPriorityItem>.from(items);
              final moved = list.removeAt(oldIndex);
              list.insert(newIndex, moved);
              final newOrder = list.map((p) => p.id.toLowerCase()).toList();
              prefs.setProviderOrder(type, newOrder);
            },
            itemBuilder: (context, index) {
              final item = items[index];
              final isActive = index == 0;
              final colors = context.colors;
              return Container(
                key: ValueKey(item.uniqueKey),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? Colors.green.withValues(alpha: 0.6)
                        : colors.borderSubtle,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: ProviderIcon(
                    providerId: item.id,
                    type: item.type,
                    size: 22,
                    fallbackIcon: type == 'lyrics'
                        ? Icons.mic
                        : type == 'audio'
                            ? Icons.graphic_eq
                            : Icons.extension,
                  ),
                  title: Text(
                    item.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    isActive ? 'Active / Primary' : 'Fallback #$index',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? (colors.isDark
                              ? Colors.greenAccent
                              : Colors.green[700])
                          : colors.textMuted,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(Icons.drag_handle, color: colors.textMuted),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (customOrder.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: GenericTextButton.icon(
              icon: const Icon(Icons.restore, size: 14),
              label: const Text(
                'Reset to Defaults',
                style: TextStyle(fontSize: 12),
              ),
              onPressed: () => prefs.resetProviderOrder(type),
            ),
          ),
      ],
    );
  }
}

class _ProviderPriorityItem {
  final String id;
  final String name;
  final String type;
  final int priority;
  final String uniqueKey;

  const _ProviderPriorityItem({
    required this.id,
    required this.name,
    required this.type,
    required this.priority,
    required this.uniqueKey,
  });
}

