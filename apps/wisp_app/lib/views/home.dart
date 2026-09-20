// Copyright © 2026 wizeshi

/// Home page with user's Spotify library
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:wisp/providers/metadata/spotify_internal.dart';
import 'package:flutter/cupertino.dart';
import 'package:wisp/ui/artwork/artwork_thumbnail.dart';
import 'package:wisp/ui/cards/album_card.dart';
import 'package:wisp/ui/cards/artist_card.dart';
import 'package:wisp/ui/cards/playlist_card.dart';
import 'package:wisp/ui/rails/card_rail.dart';
import 'package:wisp/ui/rows/album_row.dart';
import 'package:wisp/ui/rows/artist_row.dart';
import 'package:wisp/ui/rows/generic_row.dart';
import 'package:wisp/ui/rows/playlist_row.dart';
import '../models/library_folder.dart';
import '../utils/logger.dart';
import '../models/metadata_models.dart';
import '../services/metadata_cache.dart';
import '../providers/library/library_state.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/local_playlists.dart';
import '../providers/preferences/preferences_provider.dart';
import '../theme/app_theme.dart';
import '../services/app_navigation.dart';
import '../services/playback/playback_coordinator.dart';
import '../utils/liked_songs.dart';
import '../widgets/provider_disabled_state.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/entity_context_menus.dart';

class HomePage extends StatefulWidget {
  final ValueListenable<int>? refreshSignal;

  const HomePage({super.key, this.refreshSignal});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  bool _isLoading = true;
  bool _isFetchingData = false;
  List<GenericAlbum> _savedAlbums = [];
  List<GenericPlaylist> _savedPlaylists = [];
  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericSimpleArtist> _followedArtists = [];
  Map<String, List<dynamic>> _homeSections = {};

  late final SpotifyInternalProvider _spotifyProvider;
  late final LocalPlaylistState _localPlaylistState;
  bool _wasAuthenticated = false;
  VoidCallback? _localPlaylistListener;
  VoidCallback? _refreshListener;
  int _lastRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    _spotifyProvider = context.read<SpotifyInternalProvider>();
    _localPlaylistState = context.read<LocalPlaylistState>();
    _wasAuthenticated = _spotifyProvider.isAuthenticated;
    _spotifyProvider.addListener(_handleAuthChange);

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
    _spotifyProvider.removeListener(_handleAuthChange);
    if (_refreshListener != null) {
      widget.refreshSignal?.removeListener(_refreshListener!);
    }
    if (_localPlaylistListener != null) {
      _localPlaylistState.removeListener(_localPlaylistListener!);
    }
    super.dispose();
  }

  void _handleAuthChange() {
    final isAuthenticated = _spotifyProvider.isAuthenticated;
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
      final preferences = context.read<PreferencesProvider>();
      if (!preferences.metadataSpotifyEnabled) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final spotifyInternal = context.read<SpotifyInternalProvider>();
      final libraryState = context.read<LibraryState>();

      if (mounted) {
        setState(() => _isLoading = true);
      }

      // Re-check auth state from storage only when currently unauthenticated.
      if (!spotifyInternal.isAuthenticated) {
        await spotifyInternal.checkAuthState();
      }

      logger.d('[Views/Home] Loading home page data...');
      logger.d('[Views/Home] Auth Status: ');
      logger.d('\t Spotify-Internal: ${spotifyInternal.isAuthenticated}');

      if (!spotifyInternal.isAuthenticated) {
        logger.d('[Views/Home] Not authenticated, skipping data load');
        libraryState.clear();
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      logger.d('[Views/Home] Starting API calls...');

      // Fetch user profile first (doesn't need to be in Future.wait)
      await spotifyInternal.fetchUserProfile();

      // Use internal provider for liked tracks; avoid full saved-tracks fetch.
      List<PlaylistItem> cachedLiked = const [];
      if (policy == MetadataFetchPolicy.refreshAlways) {
        cachedLiked = await spotifyInternal.getUserSavedTracks(
          limit: 50,
          offset: 0,
          policy: policy,
        );
        spotifyInternal.setLikedTracksFromItems(cachedLiked);
      } else {
        cachedLiked = await spotifyInternal.getUserSavedTracks(
          limit: 50,
          offset: 0,
          policy: MetadataFetchPolicy.refreshIfExpired,
        );
        if (cachedLiked.isNotEmpty) {
          spotifyInternal.setLikedTracksFromItems(cachedLiked);
        }
      }
      final likedPlaylist = buildLikedSongsPlaylist(
        userDisplayName: _spotifyProvider.userDisplayName,
        total: spotifyInternal.likedTracksTotalCount ?? cachedLiked.length,
      );

      var userLibrary = await spotifyInternal.getUserLibrary(
        policy: MetadataFetchPolicy.refreshAlways,
      );
      final userHome = await spotifyInternal.getUserHome(policy: policy);

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
        setState(() => _isLoading = false);
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
    final spotifyEnabled = context.select<PreferencesProvider, bool>(
      (p) => p.metadataSpotifyEnabled,
    );
    if (!spotifyEnabled) {
      return const ProviderDisabledState();
    }

    final bool isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final isAuthenticated = context.select<SpotifyInternalProvider, bool>(
      (spotify) => spotify.isAuthenticated,
    );
    if (!isAuthenticated) {
      return _buildUnauthenticatedView();
    }

    if (_isLoading) {
      return _buildLoadingView();
    }

    return _buildMainContent(isDesktop);
  }

  Widget _buildUnauthenticatedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_note, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Not connected to Spotify',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
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
    if (isDesktop) {
      return RefreshIndicator(
        onRefresh: () => _loadData(policy: MetadataFetchPolicy.refreshAlways),
        child: _buildContentArea(),
      );
    }

    final style = context.select<PreferencesProvider, AppStyle>(
      (p) => p.style,
    );
    final isApple = style == AppStyle.AppleMusic;

    return RefreshIndicator(
      onRefresh: () => _loadData(policy: MetadataFetchPolicy.refreshAlways),
      child: isApple
          ? _buildMobileHomeContentApple()
          : _buildMobileHomeContentSpotify(),
    );
  }

  String _getRandomGreeting(SpotifyInternalProvider spotify) {
    final userName = spotify.userDisplayName ?? 'user';
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
      Selector<PreferencesProvider, bool>(
        selector: (context, prefs) => prefs.debugModeEnabled,
        builder: (context, debugModeEnabled, child) {
          if (!debugModeEnabled) {
            return const SizedBox.shrink();
          }
          return IconButton(
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
      IconButton(
        icon: Icon(
          useAppleIcon
              ? CupertinoIcons.person_crop_circle
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

  Widget _buildMobileHomeContentSpotify() {
    final spotify = context.read<SpotifyInternalProvider>();
    final greeting = _getRandomGreeting(spotify);
    final dynamicSections = _buildDynamicHomeSections(skipFirst: true);
    final quickTiles = _buildMobileQuickGridTiles();
    final leftQuickTiles = <Widget>[];
    final rightQuickTiles = <Widget>[];

    for (var i = 0; i < quickTiles.length; i++) {
      if (i.isEven) {
        leftQuickTiles.add(quickTiles[i]);
      } else {
        rightQuickTiles.add(quickTiles[i]);
      }
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          // Header with settings icon
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      greeting,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ..._buildMobileHeaderActions(useAppleIcon: false),
                ],
              ),
            ),
          ),

          // 2-column grid for playlists and albums
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column - mixed quick tiles
                  Expanded(child: Column(children: leftQuickTiles)),
                  const SizedBox(width: 12),
                  // Right column - mixed quick tiles
                  Expanded(child: Column(children: rightQuickTiles)),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 4)),

          ...dynamicSections.map(
            (section) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: section,
              ),
            ),
          ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildMobileHomeContentApple() {
    final dynamicSections = _buildDynamicHomeSections(skipFirst: false);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          // iOS-style Large Title Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Home',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      ..._buildMobileHeaderActions(useAppleIcon: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Divider(color: Colors.white12, height: 1),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          ...dynamicSections.map(
            (section) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: section,
              ),
            ),
          ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
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

  Widget _buildContentArea() {
    final viewWidth = MediaQuery.sizeOf(context).width;
    const minWidthForSpecialCard = 1600.0;
    final canShowSpecialCard = viewWidth >= minWidthForSpecialCard;

    final quickRows = _buildDesktopQuickRows();
    final dynamicEntries =
        ((quickRows != null)
                ? _homeSections.entries.skip(1)
                : _homeSections.entries)
            .toList(growable: false);

    final newMusicIndex = dynamicEntries.indexWhere(
      (entry) => entry.key.trim().toLowerCase() == 'new music',
    );
    final shouldShowNewMusicSpecialCard =
        canShowSpecialCard &&
        newMusicIndex >= 0 &&
        dynamicEntries[newMusicIndex].value.isNotEmpty;
    final rightSectionIndex = (newMusicIndex == 0 && dynamicEntries.length > 1)
        ? 1
        : 0;

    final firstDynamicSectionItems =
        (dynamicEntries.isNotEmpty && rightSectionIndex < dynamicEntries.length)
        ? dynamicEntries[rightSectionIndex].value
        : const <dynamic>[];
    final firstDynamicSectionWidget =
        dynamicEntries.isNotEmpty && firstDynamicSectionItems.isNotEmpty
        ? _buildSection(
            dynamicEntries[rightSectionIndex].key,
            firstDynamicSectionItems,
            showTitle: !shouldShowNewMusicSpecialCard,
          )
        : null;

    final newMusicSpecialCard = shouldShowNewMusicSpecialCard
        ? _buildHomeCard(
            dynamicEntries[newMusicIndex].value.first,
            useSpecialCardStyle: true,
          )
        : null;

    final skipDynamicIndexes = <int>{};
    if (firstDynamicSectionWidget != null &&
        dynamicEntries.isNotEmpty &&
        rightSectionIndex < dynamicEntries.length) {
      skipDynamicIndexes.add(rightSectionIndex);
    }
    if (newMusicSpecialCard != null && newMusicIndex >= 0) {
      skipDynamicIndexes.add(newMusicIndex);
    }

    final dynamicSections = _buildDynamicHomeSections(
      skipFirst: quickRows != null,
      skipEntryIndexes: skipDynamicIndexes,
      allowSpecialCardStyle: canShowSpecialCard,
    );
    return WispListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          _getRandomGreeting(context.read<SpotifyInternalProvider>()),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        ?quickRows,
        if (newMusicSpecialCard != null && firstDynamicSectionWidget != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: SizedBox(height: 230, child: newMusicSpecialCard),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: firstDynamicSectionWidget),
            ],
          )
        else if (newMusicSpecialCard != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: newMusicSpecialCard,
          )
        else
          ?firstDynamicSectionWidget,
        ...dynamicSections,
      ],
    );
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
