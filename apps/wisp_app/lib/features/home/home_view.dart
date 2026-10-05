// Copyright © 2026 wizeshi

/// Home page with user's Spotify library
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/cards/album_card.dart';
import 'package:wisp/shared/widgets/cards/artist_card.dart';
import 'package:wisp/shared/widgets/cards/playlist_card.dart';
import 'package:wisp/shared/widgets/rails/card_rail.dart';
import 'package:wisp/shared/widgets/rows/album_row.dart';
import 'package:wisp/shared/widgets/rows/artist_row.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';
import 'package:wisp/shared/widgets/rows/playlist_row.dart';
import 'package:wisp/shared/widgets/layout/mobile_bottom_padding.dart';
import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/services/system/connectivity_service.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/shared/widgets/display/provider_disabled_state.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';

part 'desktop/spotify_style.dart';
part 'desktop/apple_music_style.dart';
part 'desktop/original_style.dart';
part 'mobile/spotify_style.dart';
part 'mobile/apple_music_style.dart';
part 'mobile/original_style.dart';

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

    // Delay loading to allow provider to initialize
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
      if (!metadataManager.hasEnabledProviders) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }
      if (!metadataManager.hasCapability(MetadataCapability.home)) {
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

      // Re-check auth state from storage only when currently unauthenticated.
      if (!metadataManager.isAuthenticated) {
        await metadataManager.checkAuthState();
      }

      logger.d('[Views/Home] Loading home page data...');
      logger.d('[Views/Home] Auth Status: ');
      logger.d('\t Metadata provider: ${metadataManager.isAuthenticated}');

      if (!metadataManager.isAuthenticated) {
        logger.d('[Views/Home] Not authenticated, skipping data load');
        libraryState.clear();
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1. Immediately display cached library and home feed if current state is empty
      if (_savedAlbums.isEmpty && _savedPlaylists.isEmpty && _homeSections.isEmpty) {
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

      // 2. Check network connectivity before starting remote network calls
      final isOnline = await ConnectivityService.instance.checkOnline();
      if (!isOnline) {
        logger.d('[Views/Home] Offline: keeping cached home data');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isRefreshing = false;
          });
        }
        return;
      }

      logger.d('[Views/Home] Starting API calls...');

      // Fetch user profile first (doesn't need to be in Future.wait)
      await metadataManager.fetchUserProfile();

      // Use active provider for liked tracks; avoid full saved-tracks fetch.
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
      ) ?? const GenericLibrary(
        saved_albums: [],
        saved_playlists: [],
        saved_artists: [],
      );
      final userHome = await metadataManager.getUserHome(
        policy: MetadataFetchPolicy.refreshAlways,
      ) ?? const GenericHome(sections: {});

      // Import remote folders
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

      logger.d('[Views/Home] API calls completed');
      logger.d('\t Albums: ${userLibrary.saved_albums.length}');
      logger.d('\t Playlists: ${playlistsWithLiked.length}');
      logger.d('\t Followed artists: ${userLibrary.saved_artists.length}');

      if (mounted) {
        setState(() {
          // Use internal provider results for saved albums and followed artists
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

      logger.d('[Views/Home] Library state updated successfully');
    } catch (e) {
      logger.e('[Views/Home] Failed to load data', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
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
        if (_isUnknownHomeItem(item)) {
          _logUnknownHomeItem(item, key);
          continue;
        }
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
    return title != null && _unknownHomeTitles.contains(title.trim().toLowerCase());
  }

  void _logUnknownHomeItem(dynamic item, String section) {
    final (type, id, title) = switch (item) {
      GenericPlaylist p => ('playlist', p.id, p.title),
      GenericAlbum a => ('album', a.id, a.title),
      GenericSimpleArtist a => ('artist', a.id, a.name),
      _ => (item.runtimeType.toString(), '', ''),
    };

    logger.w(
      '[Views/Home] Dropping unknown home card in "$section": '
      'type=$type id=$id title="$title"',
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasEnabledProviders = context.select<MetadataManager, bool>(
      (m) => m.hasEnabledProviders,
    );
    if (!hasEnabledProviders) {
      return const ProviderDisabledState(message: 'No metadata provider is enabled.');
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
      return _buildLoadingView();
    }

    final content = _buildMainContent(isDesktop);

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
    final activeProvider = context.read<MetadataManager>().activeCatalogProvider;
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
                  onPressed: () => AppNavigation.instance.pushTab(1),
                  icon: const Icon(Symbols.search_rounded),
                  label: const Text('Go to Search'),
                ),
                GenericOutlinedButton.icon(
                  onPressed: () => AppNavigation.instance.openSettings(),
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
            onPressed: () {
              AppNavigation.instance.openSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(child: CircularProgressIndicator());
  }

  Widget _buildMainContent(bool isDesktop) {
    final style = context.select<PreferencesProvider, AppStyle>(
      (p) => p.style,
    );

    if (isDesktop) {
      return RefreshIndicator(
        onRefresh: () => _loadData(policy: MetadataFetchPolicy.refreshAlways),
        child: switch (style) {
          AppStyle.AppleMusic => _buildDesktopHomeContentApple(),
          AppStyle.Original => _buildDesktopHomeContentOriginal(),
          AppStyle.Spotify => _buildDesktopHomeContentSpotify(),
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(policy: MetadataFetchPolicy.refreshAlways),
      child: switch (style) {
        AppStyle.AppleMusic => _buildMobileHomeContentApple(),
        AppStyle.Original => _buildMobileHomeContentOriginal(),
        AppStyle.Spotify => _buildMobileHomeContentSpotify(),
      },
    );
  }

  String _getRandomGreeting(MetadataManager metadata) {
    final userName = metadata.userDisplayName ?? 'user';
    final hour = DateTime.now().hour;

    // Determine time of day
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

    // Use a consistent random seed based on the day to keep the greeting stable during the day
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final random = Random(
      seed,
    ); // TODO: ASK TO CHANGE TO PURELY RANDOM EACH TIME

    return greetings[random.nextInt(greetings.length)];
  }

  List<Widget> _buildMobileHeaderActions({bool useAppleIcon = false}) {
    return [
      GenericIconButton(
        icon: const Icon(
          Symbols.headphones,
          color: Colors.white,
          size: 24,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: () => AppNavigation.instance.navigateToDJView(context),
      ),
      Selector<PreferencesProvider, bool>(
        selector: (context, prefs) => prefs.debugModeEnabled,
        builder: (context, debugModeEnabled, child) {
          if (!debugModeEnabled) {
            return const SizedBox.shrink();
          }
          return GenericIconButton(
            icon: const Icon(
              Icons.bug_report_outlined,
              color: Colors.white,
              size: 24,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => AppNavigation.instance.openDebug(context),
          );
        },
      ),
      GenericIconButton(
        icon: Icon(
          useAppleIcon
              ? CupertinoIcons.settings
              : Icons.settings_outlined,
          color: Colors.white,
          size: useAppleIcon ? 26 : 24,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: () => AppNavigation.instance.openSettings(),
      ),
    ];
  }

  List<Widget> _buildMobileQuickGridTiles() {
    final sourceItems = <dynamic>[];

    final likedPlaylist = _savedPlaylists.cast<GenericPlaylist?>().firstWhere(
      (p) => isLikedSongsPlaylistId(p?.id),
      orElse: () => null,
    );
    if (likedPlaylist != null) {
      sourceItems.add(likedPlaylist);
    }

    if (_homeSections.isNotEmpty) {
      sourceItems.addAll(_homeSections.entries.first.value);
    }

    final seen = <String>{};
    final tiles = <Widget>[];
    for (final item in sourceItems) {
      final key = _mobileQuickItemKey(item);
      if (key == null || seen.contains(key)) continue;
      seen.add(key);

      final tile = _buildQuickTile(item, isMobile: true);
      if (tile != null) {
        tiles.add(
          Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
        );
      }
      if (tiles.length >= 8) break;
    }

    if (tiles.isNotEmpty) {
      return tiles;
    }

    return [
      for (final playlist in _savedPlaylists.take(4))
        if (_buildQuickTile(playlist, isMobile: true) case final tile?)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
      for (final album in _savedAlbums.take(4))
        if (_buildQuickTile(album, isMobile: true) case final tile?)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
    ];
  }

  String? _mobileQuickItemKey(dynamic item) => switch (item) {
    GenericPlaylist(:final id) => 'playlist:$id',
    GenericAlbum(:final id) => 'album:$id',
    GenericSimpleArtist(:final id) => 'artist:$id',
    GenericSong(:final id) => 'song:$id',
    _ => null,
  };

  Widget? _buildQuickTile(dynamic item, {bool isMobile = false}) {
    const tileBg = Color(0x0DFFFFFF);
    final height = isMobile ? 56.0 : 48.0;
    final playPosition =
        isMobile ? GenericRowPlayPosition.none : GenericRowPlayPosition.end;

    return switch (item) {
      GenericPlaylist playlist => PlaylistRow(
        playlist: playlist,
        height: height,
        backgroundColor: tileBg,
        showSubtitle: !isMobile,
        playPosition: playPosition,
      ),
      GenericAlbum album => AlbumRow(
        album: album,
        height: height,
        backgroundColor: tileBg,
        showSubtitle: !isMobile,
        playPosition: playPosition,
      ),
      GenericSimpleArtist artist => ArtistRow(
        artist: artist,
        height: height,
        backgroundColor: tileBg,
        showSubtitle: !isMobile,
        playPosition: playPosition,
      ),
      GenericSong song => GenericRow(
        title: song.title,
        height: height,
        showSubtitle: !isMobile,
        backgroundColor: tileBg,
        playPosition: playPosition,
        artwork: ArtworkThumbnail(
          source: ArtworkSource.fromUrl(song.thumbnailUrl),
          size: ArtworkSize.large,
          fallbackIcon: Icons.music_note,
          semanticLabel: 'Artwork for ${song.title}',
        ),
        onTap: () async {
          final coordinator = context.read<PlaybackCoordinator>();
          await coordinator.setQueue([song], startIndex: 0, play: true);
        },
        onLongPress: () {
          EntityContextMenus.showTrackMenu(context, track: song);
        },
      ),
      _ => null,
    };
  }

  Widget? _buildDesktopQuickRows() {
    if (_homeSections.isEmpty) return null;
    final firstSection = _homeSections.entries.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemsPerRow = (maxWidth / 220).floor().clamp(1, 4);
        final maxItems = min(itemsPerRow * 2, 8);
        final cards = firstSection.value
            .map<Widget?>((item) => _buildQuickTile(item, isMobile: false))
            .whereType<Widget>()
            .take(maxItems)
            .toList();
        if (cards.isEmpty) return const SizedBox.shrink();

        final rowCount = ((cards.length + itemsPerRow - 1) / itemsPerRow)
            .floor();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int row = 0; row < rowCount; row++)
              Padding(
                padding: EdgeInsets.only(bottom: row == rowCount - 1 ? 24 : 16),
                child: Row(
                  children: List.generate(itemsPerRow, (col) {
                    final index = row * itemsPerRow + col;
                    final item = index < cards.length
                        ? cards[index]
                        : const SizedBox.shrink();
                    if (col == itemsPerRow - 1) {
                      return Expanded(child: item);
                    }
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: item,
                      ),
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildDynamicHomeSections({
    bool skipFirst = false,
    Set<int> skipEntryIndexes = const <int>{},
    bool allowSpecialCardStyle = true,
  }) {
    if (_homeSections.isEmpty) return const [];
    final widgets = <Widget>[];

    var entries =
        (skipFirst ? _homeSections.entries.skip(1) : _homeSections.entries)
            .toList(growable: false);
    for (var i = 0; i < entries.length; i++) {
      if (skipEntryIndexes.contains(i)) continue;
      MapEntry<String, List<dynamic>> entry = entries[i];
      if (entry.value.isEmpty) continue;
      // The first section is called "Section 1", so we'll rename it to "Recents" for clarity.
      if (!skipFirst && i == 0) {
        entry = MapEntry('Recents', entry.value);
      }
      final useSpecialCardStyle =
          allowSpecialCardStyle &&
          i == 0 &&
          entry.key.trim().toLowerCase() == 'new music';
      widgets.add(
        _buildSection(
          entry.key,
          entry.value, // raw items now, not pre-built widgets
          showTitle: !useSpecialCardStyle,
          expandCardsToRowWidth: useSpecialCardStyle,
          useSpecialCardStyle: useSpecialCardStyle,
        ),
      );
    }

    return widgets;
  }

  Widget? _buildHomeCard(dynamic item, {bool useSpecialCardStyle = false}) =>
      switch (item) {
        GenericPlaylist playlist => PlaylistCard(playlist: playlist),
        GenericAlbum album => AlbumCard(album: album),
        GenericSimpleArtist artist => ArtistCard(artist: artist),
        _ => null,
      };

  Widget _buildSection(
    String title,
    List<dynamic> items, {
    bool showTitle = true,
    bool expandCardsToRowWidth = false,
    bool useSpecialCardStyle = false,
  }) {
    return CardRail<dynamic>(
      title: title,
      items: items,
      showTitle: showTitle,
      expandItemsToRailWidth: expandCardsToRowWidth,
      itemWidth: 200,
      itemHeight: useSpecialCardStyle
          ? 168
          : null, // null falls back to the GenericCard default
      itemBuilder: (context, item) =>
          _buildHomeCard(item, useSpecialCardStyle: useSpecialCardStyle) ??
          const SizedBox.shrink(),
    );
  }
}
