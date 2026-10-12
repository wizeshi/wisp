// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/system/connectivity_service.dart';
import 'package:wisp/shared/widgets/display/provider_disabled_state.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert_extensions.dart';

import 'home_view_data.dart';
import 'desktop/spotify.dart';
import 'desktop/apple_music.dart';
import 'desktop/original.dart';
import 'mobile/spotify.dart';
import 'mobile/apple_music.dart';
import 'mobile/original.dart';

class HomePage extends StatefulWidget {
  final ValueListenable<int>? refreshSignal;

  const HomePage({super.key, this.refreshSignal});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isFetchingData = false;
  final ScrollController _scrollController = ScrollController();
  List<GenericAlbum> _savedAlbums = [];
  List<GenericPlaylist> _savedPlaylists = [];
  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericSimpleArtist> _followedArtists = [];
  Map<String, List<dynamic>> _homeSections = {};

  late final MetadataManager _metadataManager;
  late final LocalPlaylistState _localPlaylistState;
  bool _wasAuthenticated = false;
  VoidCallback? _localPlaylistListener;
  VoidCallback? _refreshListener;
  int _lastRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    _metadataManager = context.read<MetadataManager>();
    _localPlaylistState = context.read<LocalPlaylistState>();
    _wasAuthenticated = _metadataManager.isAuthenticated;
    _metadataManager.addListener(_handleAuthChange);

    _localPlaylistListener = () {
      if (!mounted) return;
      setState(() {
        _savedPlaylists = _mergeLocalPlaylists(
          _remotePlaylists,
          _localPlaylistState.genericPlaylists,
          _localPlaylistState.hiddenProviderPlaylistIds,
        );
      });
    };
    _localPlaylistState.addListener(_localPlaylistListener!);

    final refreshSignal = widget.refreshSignal;
    if (refreshSignal != null) {
      _lastRefreshTick = refreshSignal.value;
      _refreshListener = () {
        if (!mounted) return;
        if (refreshSignal.value == _lastRefreshTick) return;
        _lastRefreshTick = refreshSignal.value;
        refresh();
      };
      refreshSignal.addListener(_refreshListener!);
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _metadataManager.removeListener(_handleAuthChange);
    if (_refreshListener != null) {
      widget.refreshSignal?.removeListener(_refreshListener!);
    }
    if (_localPlaylistListener != null) {
      _localPlaylistState.removeListener(_localPlaylistListener!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handleAuthChange() {
    final isAuthenticated = _metadataManager.isAuthenticated;
    if (isAuthenticated && !_wasAuthenticated) {
      _wasAuthenticated = true;
      _loadData();
    } else if (!isAuthenticated && _wasAuthenticated) {
      _wasAuthenticated = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadData({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (_isFetchingData) return;
    _isFetchingData = true;

    try {
      final metadataManager = context.read<MetadataManager>();
      if (!metadataManager.hasEnabledProviders ||
          !metadataManager.hasCapability(MetadataCapability.home)) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }
      final libraryState = context.read<LibraryState>();
      final hasData = _savedAlbums.isNotEmpty ||
          _savedPlaylists.isNotEmpty ||
          _homeSections.isNotEmpty;

      if (mounted) {
        if (!hasData) {
          setState(() => _isLoading = true);
        } else {
          setState(() => _isRefreshing = true);
        }
      }

      if (!metadataManager.isAuthenticated) {
        await metadataManager.checkAuthState();
      }

      if (!metadataManager.isAuthenticated) {
        libraryState.clear();
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (_savedAlbums.isEmpty &&
          _savedPlaylists.isEmpty &&
          _homeSections.isEmpty) {
        try {
          final cachedLib = await metadataManager.getUserLibrary(
            policy: MetadataFetchPolicy.cacheFirst,
          );
          final cachedHome = await metadataManager.getUserHome(
            policy: MetadataFetchPolicy.cacheFirst,
          );
          if (cachedLib != null || cachedHome != null) {
            final lib = cachedLib ??
                const GenericLibrary(
                  saved_albums: [],
                  saved_playlists: [],
                  saved_artists: [],
                );
            final home = cachedHome ?? const GenericHome(sections: {});
            final initialLikedPlaylist = buildLikedSongsPlaylist(
              userDisplayName: metadataManager.userDisplayName,
              total: metadataManager.likedTracksTotalCount,
            );
            final intPlaylists = lib.saved_playlists;
            final plWithLiked = [
              initialLikedPlaylist,
              ...intPlaylists.where((p) => p.id != likedSongsPlaylistId),
            ];
            if (!mounted) return;
            final localState = context.read<LocalPlaylistState>();
            final merged = _mergeLocalPlaylists(
              plWithLiked,
              localState.genericPlaylists,
              localState.hiddenProviderPlaylistIds,
            );
            setState(() {
              _savedAlbums = lib.saved_albums;
              _savedPlaylists = merged;
              _followedArtists = lib.saved_artists
                  .map(
                    (a) => GenericSimpleArtist(
                      id: a.id,
                      source: a.source,
                      name: a.name,
                      thumbnailUrl: a.thumbnailUrl,
                    ),
                  )
                  .toList();
              _homeSections = _sanitizeHomeSections(home.sections);
              _isLoading = false;
            });
          }
        } catch (_) {}
      }

      final isOnline = await ConnectivityService.instance.checkOnline();
      if (!isOnline) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isRefreshing = false;
          });
        }
        return;
      }

      await metadataManager.fetchUserProfile();

      List<PlaylistItem> cachedLiked = const [];
      if (policy == MetadataFetchPolicy.refreshAlways) {
        cachedLiked = await metadataManager.getUserSavedTracks(
          limit: 50,
          offset: 0,
          policy: policy,
        );
        metadataManager.setLikedTracksFromItems(cachedLiked);
      } else {
        cachedLiked = await metadataManager.getUserSavedTracks(
          limit: 50,
          offset: 0,
          policy: MetadataFetchPolicy.refreshIfExpired,
        );
        if (cachedLiked.isNotEmpty) {
          metadataManager.setLikedTracksFromItems(cachedLiked);
        }
      }
      final likedPlaylist = buildLikedSongsPlaylist(
        userDisplayName: _metadataManager.userDisplayName,
        total: metadataManager.likedTracksTotalCount ?? cachedLiked.length,
      );

      final userLibrary = await metadataManager.getUserLibrary(
            policy: MetadataFetchPolicy.refreshAlways,
          ) ??
          const GenericLibrary(
            saved_albums: [],
            saved_playlists: [],
            saved_artists: [],
          );
      final userHome = await metadataManager.getUserHome(
            policy: MetadataFetchPolicy.refreshAlways,
          ) ??
          const GenericHome(sections: {});

      try {
        if (mounted) {
          final folderState = context.read<LibraryFolderState>();
          final all = userLibrary.all_organized;
          if (all != null && all.isNotEmpty) {
            final remoteFolders = <PlaylistFolder>[];
            for (final e in all) {
              if (e is Map<String, dynamic>) {
                final t = e['__typename'] as String? ?? e['type'] as String?;
                if (t == 'Folder' || t == 'folder') {
                  final uri = e['uri'] as String? ?? e['id'] as String? ?? '';
                  final id = uri.isNotEmpty ? uri : (e['id'] as String? ?? '');
                  final name = e['name'] as String? ?? '';
                  remoteFolders.add(
                    PlaylistFolder(
                      id: id,
                      title: name,
                      createdAt: DateTime.now(),
                    ),
                  );
                }
              }
            }
            if (remoteFolders.isNotEmpty) {
              await folderState.importRemoteFolders(remoteFolders);
            }
          }

          if (userLibrary.folderAssignments != null) {
            await folderState.batchAssignPlaylistsToFolders(
              userLibrary.folderAssignments!,
            );
          }
        }
      } catch (e) {
        logger.w('[Views/Home] Failed to process remote folders: $e');
      }

      final internalPlaylists = userLibrary.saved_playlists;
      final playlistsWithLiked = [
        likedPlaylist,
        ...internalPlaylists.where((p) => p.id != likedSongsPlaylistId),
      ];
      if (!mounted) return;
      final localState = context.read<LocalPlaylistState>();
      final localPlaylists = localState.genericPlaylists;
      _remotePlaylists = playlistsWithLiked;
      final mergedPlaylists = _mergeLocalPlaylists(
        _remotePlaylists,
        localPlaylists,
        localState.hiddenProviderPlaylistIds,
      );

      final allWithLiked = [
        likedPlaylist,
        ...userLibrary.all_organized?.where((item) => true) ?? [],
      ];

      if (mounted) {
        setState(() {
          _savedAlbums = userLibrary.saved_albums;
          _savedPlaylists = mergedPlaylists;
          _followedArtists = userLibrary.saved_artists
              .map(
                (a) => GenericSimpleArtist(
                  id: a.id,
                  source: a.source,
                  name: a.name,
                  thumbnailUrl: a.thumbnailUrl,
                ),
              )
              .toList();
          _homeSections = _sanitizeHomeSections(userHome.sections);
          _isLoading = false;
          _isRefreshing = false;
        });
      }

      libraryState.setLibrary(
        playlists: _savedPlaylists,
        albums: _savedAlbums,
        artists: _followedArtists,
        allOrganized: allWithLiked,
      );
      if (mounted) {
        context.read<LibraryFolderState>().syncPlaylists(
              libraryState.playlists,
            );
      }
    } catch (e) {
      logger.e('[Views/Home] Failed to load data', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        context.showErrorAlert('Failed to load data: $e');
      }
    } finally {
      _isFetchingData = false;
    }
  }

  Future<void> refresh({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshAlways,
  }) {
    return _loadData(policy: policy);
  }

  List<GenericPlaylist> _mergeLocalPlaylists(
    List<GenericPlaylist> remote,
    List<GenericPlaylist> local,
    Set<String> hiddenProviderIds,
  ) {
    if (local.isEmpty) {
      if (hiddenProviderIds.isEmpty) return remote;
      return remote
          .where((playlist) => !hiddenProviderIds.contains(playlist.id))
          .toList();
    }
    final localById = {for (final p in local) p.id: p};
    final merged = <GenericPlaylist>[];
    final seen = <String>{};

    for (final playlist in remote) {
      if (hiddenProviderIds.contains(playlist.id)) {
        continue;
      }
      merged.add(localById[playlist.id] ?? playlist);
      seen.add(playlist.id);
    }

    for (final playlist in local) {
      if (!seen.contains(playlist.id)) {
        merged.add(playlist);
      }
    }

    return merged;
  }

  static const Set<String> _unknownHomeTitles = {
    'unknown playlist',
    'unknown artist',
    'unknown album',
  };

  Map<String, List<dynamic>> _sanitizeHomeSections(
    Map<String, List<dynamic>> sections,
  ) {
    final sanitized = <String, List<dynamic>>{};
    sections.forEach((key, items) {
      final filtered = <dynamic>[];
      for (final item in items) {
        if (_isUnknownHomeItem(item)) continue;
        filtered.add(item);
      }
      if (filtered.isNotEmpty) {
        sanitized[key] = filtered;
      }
    });
    return sanitized;
  }

  bool _isUnknownHomeItem(dynamic item) {
    final title = switch (item) {
      GenericPlaylist(:final title) => title,
      GenericAlbum(:final title) => title,
      GenericSimpleArtist(:final name) => name,
      _ => null,
    };
    return title != null &&
        _unknownHomeTitles.contains(title.trim().toLowerCase());
  }

  String _getRandomGreeting() {
    final userName = _metadataManager.userDisplayName ?? 'user';
    final hour = DateTime.now().hour;
    String timeOfDay;
    if (hour >= 5 && hour < 12) {
      timeOfDay = 'morning';
    } else if (hour >= 12 && hour < 18) {
      timeOfDay = 'afternoon';
    } else if (hour >= 18 && hour < 22) {
      timeOfDay = 'evening';
    } else {
      timeOfDay = 'night';
    }

    final greetings = [
      'Good $timeOfDay, $userName',
      'Heya, $userName!',
      'Great to see you again!',
      'Welcome back!',
      'Missed you!',
    ];

    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final random = Random(seed);
    return greetings[random.nextInt(greetings.length)];
  }

  @override
  Widget build(BuildContext context) {
    final hasEnabledProviders = context.select<MetadataManager, bool>(
      (m) => m.hasEnabledProviders,
    );
    if (!hasEnabledProviders) {
      return const ProviderDisabledState(
        message: 'No metadata provider is enabled.',
      );
    }

    final supportsHome = context.select<MetadataManager, bool>(
      (m) => m.hasCapability(MetadataCapability.home),
    );
    if (!supportsHome) {
      return _buildUnsupportedHomeView();
    }

    final bool isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final isAuthenticated = context.select<MetadataManager, bool>(
      (metadata) => metadata.isAuthenticated,
    );
    if (!isAuthenticated) {
      return _buildUnauthenticatedView();
    }

    final hasData = _savedAlbums.isNotEmpty ||
        _savedPlaylists.isNotEmpty ||
        _homeSections.isNotEmpty;

    if (_isLoading && !hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = HomeViewData(
      isLoading: _isLoading,
      isRefreshing: _isRefreshing,
      savedAlbums: _savedAlbums,
      savedPlaylists: _savedPlaylists,
      followedArtists: _followedArtists,
      homeSections: _homeSections,
      greeting: _getRandomGreeting(),
      scrollController: _scrollController,
      hasEnabledProviders: hasEnabledProviders,
      supportsHome: supportsHome,
      isAuthenticated: isAuthenticated,
      activeProviderName:
          context.read<MetadataManager>().activeCatalogProvider?.displayName ??
              'music service',
    );

    final actions = HomeViewActions(
      onRefresh: () => refresh(),
      onPlaylistTap: (p) => NavigationService.instance.pushList(
        id: p.id,
        type: 'playlist',
        source: p.source,
      ),
      onAlbumTap: (a) => NavigationService.instance.pushList(
        id: a.id,
        type: 'album',
        source: a.source,
      ),
      onArtistTap: (a) => NavigationService.instance.pushArtist(
        id: a.id,
        source: a.source,
      ),
      onItemTap: (item) {
        if (item is GenericPlaylist) {
          NavigationService.instance.pushList(
            id: item.id,
            type: 'playlist',
            source: item.source,
          );
        } else if (item is GenericAlbum) {
          NavigationService.instance.pushList(
            id: item.id,
            type: 'album',
            source: item.source,
          );
        } else if (item is GenericSimpleArtist) {
          NavigationService.instance.pushArtist(
            id: item.id,
            source: item.source,
          );
        }
      },
      onPlaySong: (song) async {
        final coordinator = context.read<PlaybackCoordinator>();
        await coordinator.setQueue([song], startIndex: 0, play: true);
      },
      onShowTrackMenu: (song) {
        EntityContextMenus.showTrackMenu(context, track: song);
      },
      onOpenSearch: () => NavigationService.instance.goSearch(),
      onOpenSettings: () => NavigationService.instance.pushSettings(),
      onOpenDJ: () => NavigationService.instance.pushDJ(),
      onOpenDebug: () => NavigationService.instance.pushDebug(),
    );

    final style = context.select<PreferencesProvider, AppStyle>(
      (p) => p.style,
    );

    final content = RefreshIndicator(
      onRefresh: () => refresh(),
      child: isDesktop
          ? switch (style) {
              AppStyle.AppleMusic =>
                DesktopAppleMusicHome(data: data, actions: actions),
              AppStyle.Original =>
                DesktopOriginalHome(data: data, actions: actions),
              AppStyle.Spotify =>
                DesktopSpotifyHome(data: data, actions: actions),
            }
          : switch (style) {
              AppStyle.AppleMusic =>
                MobileAppleMusicHome(data: data, actions: actions),
              AppStyle.Original =>
                MobileOriginalHome(data: data, actions: actions),
              AppStyle.Spotify =>
                MobileSpotifyHome(data: data, actions: actions),
            },
    );

    return Stack(
      children: [
        content,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _isRefreshing ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnsupportedHomeView() {
    final activeProvider =
        context.read<MetadataManager>().activeCatalogProvider;
    final providerName = activeProvider?.displayName ?? 'The active provider';
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.music_note_rounded,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Home feed not supported',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$providerName does not support a personalized home feed. You can still search for and play tracks, or switch your primary metadata provider in Settings.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                GenericFilledButton.icon(
                  onPressed: () => NavigationService.instance.goSearch(),
                  icon: const Icon(Symbols.search_rounded),
                  label: const Text('Go to Search'),
                ),
                GenericOutlinedButton.icon(
                  onPressed: () => NavigationService.instance.pushSettings(),
                  icon: const Icon(Symbols.settings_rounded),
                  label: const Text('Open Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnauthenticatedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_note, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Not connected to ${context.read<MetadataManager>().activeCatalogProvider?.displayName ?? 'music service'}',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          GenericElevatedButton.icon(
            onPressed: () => NavigationService.instance.pushSettings(),
            icon: const Icon(Icons.settings),
            label: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }
}

