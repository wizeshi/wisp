// Copyright © 2026 wizeshi

library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/sources/providers/provider_package_model.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/display/provider_icon.dart';

class ProvidersMarketplaceView extends StatefulWidget {
  const ProvidersMarketplaceView({super.key});

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
    _loadCatalog();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${pkg.name} installed successfully!')),
      );
      _loadCatalog();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to install ${pkg.name}')));
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated $count of ${updates.length} providers.')),
    );
    _loadCatalog();
  }

  Future<void> _uninstall(ProviderPackage pkg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: Text('Uninstall ${pkg.name}?'),
        content: Text('Are you sure you want to remove ${pkg.name}?.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Uninstall'),
          ),
          TextButton(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${pkg.name} uninstalled.')));
      _loadCatalog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to uninstall ${pkg.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final updateCount = _packages.where((pkg) => pkg.hasUpdate).length;

    final filtered = _packages.where((pkg) {
      if (_selectedFilter.startsWith('Updates') && !pkg.hasUpdate) return false;
      if (_selectedFilter == 'Metadata' && pkg.type != 'metadata') return false;
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
    filterTabs.addAll(['Metadata', 'Lyrics', 'Auth', 'Installed']);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Providers Marketplace'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Provider Priority Order',
            icon: const Icon(Icons.low_priority),
            onPressed: () => _showPriorityOrderDialog(context),
          ),
          IconButton(
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
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 8.0,
            ),
            child: Column(
              children: [
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search providers...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: filterTabs.map((filter) {
                    final isSelected =
                        _selectedFilter == filter ||
                        (_selectedFilter.startsWith('Updates') &&
                            filter.startsWith('Updates'));
                    final isUpdateTab = filter.startsWith('Updates');
                    final chipColor = isUpdateTab ? Colors.amber : primaryColor;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: isSelected,
                        selectedColor: chipColor.withValues(alpha: 0.3),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? (isUpdateTab ? Colors.amber : Colors.white)
                              : Colors.grey[400],
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                        backgroundColor: const Color(0xFF1E1E1E),
                        side: BorderSide(
                          color: isSelected ? chipColor : Colors.transparent,
                        ),
                        onSelected: (_) =>
                            setState(() => _selectedFilter = filter),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF282828), height: 1),

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
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
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
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount:
                        filtered.length +
                        ((updateCount > 0 &&
                                !_selectedFilter.startsWith('Updates'))
                            ? 1
                            : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      if (updateCount > 0 &&
                          !_selectedFilter.startsWith('Updates')) {
                        if (index == 0) {
                          return _buildUpdatesBanner(updateCount);
                        }
                        return _buildProviderCard(
                          filtered[index - 1],
                          primaryColor,
                        );
                      }
                      return _buildProviderCard(filtered[index], primaryColor);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesBanner(int updateCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.system_update_alt,
              color: Colors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$updateCount ${updateCount == 1 ? "provider update" : "provider updates"} available',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Install updates to get the latest lyrics sources and fixes.',
                  style: TextStyle(color: Colors.amber[200], fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _isUpdatingAll ? null : _updateAll,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber[700],
              foregroundColor: Colors.black,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(ProviderPackage pkg, Color primaryColor) {
    final isBusy = _busyProviderIds.contains(pkg.uniqueKey);
    final prefs = context.watch<PreferencesProvider>();
    final isEnabled = prefs.isProviderEnabled(pkg.id);
    final hasUpdate = pkg.hasUpdate;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUpdate
              ? Colors.amber.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.06),
          width: hasUpdate ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (hasUpdate ? Colors.amber : primaryColor)
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
                              : Icons.extension,
                      color: hasUpdate ? Colors.amber : primaryColor,
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
                          color: Colors.amber,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E1E1E),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pkg.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pkg.isInstalled
                                ? 'v${pkg.installedVersion ?? pkg.version}'
                                : 'v${pkg.version}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                        if (hasUpdate) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.5),
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
                                const SizedBox(width: 2),
                                Text(
                                  'v${pkg.version} available',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (pkg.isInstalled &&
                            pkg.installedVersion != null &&
                            ProviderPackage.isNewerVersion(
                              pkg.installedVersion!,
                              pkg.version,
                            )) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              'repo: v${pkg.version}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[200],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'by ${pkg.author}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              // Action Button
              if (isBusy)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!pkg.isInstalled)
                FilledButton.icon(
                  onPressed: () => _installOrUpdate(pkg),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Install'),
                )
              else if (hasUpdate)
                FilledButton.icon(
                  onPressed: () => _installOrUpdate(pkg),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
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
                      onChanged: (val) async {
                        if (pkg.type == 'metadata' && pkg.id == 'spotify') {
                          await prefs.setMetadataSpotifyEnabled(val);
                        } else if (pkg.type == 'lyrics' && pkg.id == 'spotify') {
                          await prefs.setLyricsSpotifyEnabled(val);
                        } else {
                          await prefs.setProviderEnabled(pkg.id, val);
                        }
                        _loadCatalog();
                      },
                    ),
                    IconButton(
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
          ),
          const SizedBox(height: 12),
          Text(
            pkg.description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[300],
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  Widget _buildBadge(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color[200],
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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 550),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Provider Priority & Fallbacks',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Drag items to set priority order. The top provider is the active one; subsequent providers act as fallbacks.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: const [
                  Tab(text: 'Metadata Providers'),
                  Tab(text: 'Lyrics Providers'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrderTab('metadata'),
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

    final installedForType = widget.packages.where((p) => p.type == type).toList();
    if (installedForType.isEmpty) {
      return Center(
        child: Text('No installed $type providers found.', style: const TextStyle(color: Colors.grey)),
      );
    }

    // Sort according to customOrder, otherwise manifest priority descending
    installedForType.sort((a, b) {
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
            itemCount: installedForType.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final list = List<ProviderPackage>.from(installedForType);
              final moved = list.removeAt(oldIndex);
              list.insert(newIndex, moved);
              final newOrder = list.map((p) => p.id.toLowerCase()).toList();
              prefs.setProviderOrder(type, newOrder);
            },
            itemBuilder: (context, index) {
              final pkg = installedForType[index];
              final isActive = index == 0;
              return Container(
                key: ValueKey(pkg.uniqueKey),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF282828),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive ? Colors.green.withValues(alpha: 0.6) : Colors.white10,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: ProviderIcon(
                    providerId: pkg.id,
                    type: pkg.type,
                    size: 22,
                    fallbackIcon: type == 'lyrics' ? Icons.mic : Icons.extension,
                  ),
                  title: Text(pkg.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    isActive ? 'Active / Primary' : 'Fallback #$index',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive ? Colors.greenAccent : Colors.grey,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.drag_handle, color: Colors.grey),
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
            child: TextButton.icon(
              icon: const Icon(Icons.restore, size: 14),
              label: const Text('Reset to Defaults', style: TextStyle(fontSize: 12)),
              onPressed: () => prefs.resetProviderOrder(type),
            ),
          ),
      ],
    );
  }
}

