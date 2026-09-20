// Copyright © 2026 wizeshi

/// Home page with user's Spotify library
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show Platform, File;
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';
import 'package:wisp/ui/cards/album_card.dart';
import 'package:wisp/ui/cards/artist_card.dart';
import 'package:wisp/ui/cards/playlist_card.dart';
import 'package:wisp/ui/rails/card_rail.dart';
import 'package:wisp/ui/rows/album_row.dart';
import 'package:wisp/ui/rows/artist_row.dart';
import 'package:wisp/ui/rows/playlist_row.dart';
import '../models/library_folder.dart';
import '../utils/logger.dart';
import '../services/wisp_audio_handler.dart';
import '../models/metadata_models.dart';
import '../services/metadata_cache.dart';
import 'list_detail.dart';
import '../providers/library/library_state.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/local_playlists.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/app_navigation.dart';
import '../services/playback/playback_coordinator.dart';
import '../utils/liked_songs.dart';
import '../widgets/liked_songs_art.dart';
import '../widgets/provider_disabled_state.dart';
import '../widgets/entity_context_menus.dart';

typedef _PlaybackHighlight = ({
  bool isPlaying,
  String? currentTrackId,
  String? currentAlbumId,
  String currentArtistIds,
  PlaybackContext? playbackContext,
});

_PlaybackHighlight _playbackHighlightOf(WispAudioHandler player) {
  final track = player.currentTrack;
  return (
    isPlaying: player.isPlaying,
    currentTrackId: track?.id,
    currentAlbumId: track?.album?.id,
    currentArtistIds: track == null || track.artists.isEmpty
        ? ''
        : track.artists.map((a) => a.id).join('\u0001'),
    playbackContext: player.playbackContext,
  );
}

bool _isLocalThumbnailPath(String path) {
  return path.startsWith('/') || path.startsWith('file://');
}

String _playlistSubtitle(GenericPlaylist playlist) {
  final author = playlist.author.displayName.trim();
  final description = playlist.description?.trim() ?? '';
  if (author.toLowerCase() == 'spotify' && description.isNotEmpty) {
    return description;
  }
  if (author.isEmpty && description.isNotEmpty) {
    return description;
  }
  return author;
}

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

  _PlaybackHighlight _watchPlaybackHighlight() {
    return context.select<WispAudioHandler, _PlaybackHighlight>(
      _playbackHighlightOf,
    );
  }

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
    if (item is GenericPlaylist) {
      return _unknownHomeTitles.contains(item.title.trim().toLowerCase());
    }
    if (item is GenericAlbum) {
      return _unknownHomeTitles.contains(item.title.trim().toLowerCase());
    }
    if (item is GenericSimpleArtist) {
      return _unknownHomeTitles.contains(item.name.trim().toLowerCase());
    }
    return false;
  }

  void _logUnknownHomeItem(dynamic item, String section) {
    String type = item.runtimeType.toString();
    String id = '';
    String title = '';
    if (item is GenericPlaylist) {
      type = 'playlist';
      id = item.id;
      title = item.title;
    } else if (item is GenericAlbum) {
      type = 'album';
      id = item.id;
      title = item.title;
    } else if (item is GenericSimpleArtist) {
      type = 'artist';
      id = item.id;
      title = item.name;
    }

    logger.w(
      '[Views/Home] Dropping unknown home card in "$section": '
      'type=$type id=$id title="$title"',
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();
    if (!preferences.metadataSpotifyEnabled) {
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

    return RefreshIndicator(
      onRefresh: () => _loadData(policy: MetadataFetchPolicy.refreshAlways),
      child: _buildMobileHomeContent(),
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

  Widget _buildMobileHomeContent() {
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
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onPressed: () {
                          AppNavigation.instance.openDebug(context);
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    onPressed: () {
                      AppNavigation.instance.openSettings();
                    },
                  ),
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

  Widget _buildMobileGridItem({
    required String imageUrl,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Widget? customArt,
  }) {
    final isLocalThumb = imageUrl.isNotEmpty && _isLocalThumbnailPath(imageUrl);
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: isDesktop ? SystemMouseCursors.click : null,
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 44,
                  height: 44,
                  color: Colors.grey[900],
                  child:
                      customArt ??
                      (imageUrl.isNotEmpty
                          ? (isLocalThumb
                                ? Image.file(
                                    File(imageUrl.replaceFirst('file://', '')),
                                    filterQuality: FilterQuality.medium,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    filterQuality: FilterQuality.medium,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                                  ))
                          : Icon(Icons.music_note, color: Colors.grey[700])),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      /* Text(
                        subtitle,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ), */
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMobileQuickGridTiles() {
    final sourceItems = <dynamic>[];

    GenericPlaylist? likedPlaylist;
    for (final playlist in _savedPlaylists) {
      if (isLikedSongsPlaylistId(playlist.id)) {
        likedPlaylist = playlist;
        break;
      }
    }
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

      final tile = _buildMobileQuickTile(item);
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

    final fallback = <Widget>[];
    for (final playlist in _savedPlaylists.take(4)) {
      fallback.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildMobileQuickTile(playlist) ?? const SizedBox.shrink(),
        ),
      );
    }
    for (final album in _savedAlbums.take(4)) {
      fallback.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildMobileQuickTile(album) ?? const SizedBox.shrink(),
        ),
      );
    }
    return fallback;
  }

  String? _mobileQuickItemKey(dynamic item) {
    if (item is GenericPlaylist) return 'playlist:${item.id}';
    if (item is GenericAlbum) return 'album:${item.id}';
    if (item is GenericSimpleArtist) return 'artist:${item.id}';
    if (item is GenericSong) return 'song:${item.id}';
    return null;
  }

  Widget? _buildMobileQuickTile(dynamic item) {
    if (item is GenericPlaylist) {
      return _buildMobileGridItem(
        imageUrl: item.thumbnailUrl,
        title: item.title,
        subtitle: _playlistSubtitle(item),
        customArt: isLikedSongsPlaylistId(item.id)
            ? const LikedSongsArt()
            : null,
        onTap: () => _openSharedList(
          SharedListType.playlist,
          item.id,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        ),
        onLongPress: () {
          EntityContextMenus.showPlaylistMenu(context, playlist: item);
        },
      );
    }

    if (item is GenericAlbum) {
      return _buildMobileGridItem(
        imageUrl: item.thumbnailUrl,
        title: item.title,
        subtitle: item.artists.map((a) => a.name).join(', '),
        onTap: () => _openSharedList(
          SharedListType.album,
          item.id,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        ),
        onLongPress: () {
          EntityContextMenus.showAlbumMenu(context, album: item);
        },
      );
    }

    if (item is GenericSimpleArtist) {
      return _buildMobileGridItem(
        imageUrl: item.thumbnailUrl,
        title: item.name,
        subtitle: 'Artist',
        onTap: () => _openArtist(item),
        onLongPress: () {
          EntityContextMenus.showArtistMenu(context, artist: item);
        },
      );
    }

    if (item is GenericSong) {
      return _buildMobileGridItem(
        imageUrl: item.thumbnailUrl,
        title: item.title,
        subtitle: item.artists.map((a) => a.name).join(', '),
        onTap: () async {
          final coordinator = context.read<PlaybackCoordinator>();
          await coordinator.setQueue([item], startIndex: 0, play: true);
        },
        onLongPress: () {
          EntityContextMenus.showTrackMenu(context, track: item);
        },
      );
    }

    return null;
  }

  void _openSharedList(
    SharedListType type,
    String id, {
    String? title,
    String? thumbnailUrl,
  }) {
    AppNavigation.instance.openSharedList(
      context,
      id: id,
      type: type,
      initialTitle: title,
      initialThumbnailUrl: thumbnailUrl,
    );
  }

  void _openArtist(GenericSimpleArtist artist) {
    AppNavigation.instance.openArtist(
      context,
      artistId: artist.id,
      initialArtist: artist,
    );
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
    return ListView(
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
    final playback = _watchPlaybackHighlight();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemsPerRow = (maxWidth / 220).floor().clamp(1, 4);
        final maxItems = min(itemsPerRow * 2, 8);
        final cards = firstSection.value
            .map<Widget?>((item) => _buildHomeQuickTile(item, playback))
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

  Widget? _buildHomeQuickTile(dynamic item, _PlaybackHighlight playback) {
    if (item is GenericPlaylist) {
      return PlaylistRow(playlist: item);
    }

    if (item is GenericAlbum) {
      return AlbumRow(album: item);
    }

    if (item is GenericSimpleArtist) {
      return ArtistRow(artist: item);
    }

    /* if (item is GenericSong) {
      final isActive = playback.currentTrackId == item.id;
      return _HomeQuickTile(
        imageUrl: item.thumbnailUrl,
        title: item.title,
        subtitle: item.artists.map((a) => a.name).join(', '),
        isActive: isActive,
        isPlaying: isPlaying,
        onTap: () async {
          final coordinator = context.read<PlaybackCoordinator>();
          await coordinator.setQueue([item], startIndex: 0, play: true);
        },
        onPlay: () async {
          final coordinator = context.read<PlaybackCoordinator>();
          await coordinator.setQueue([item], startIndex: 0, play: true);
        },
        onSecondaryTapDown: (details) {
          EntityContextMenus.showTrackMenu(
            context,
            track: item,
            globalPosition: details.globalPosition,
          );
        },
        onLongPress: () {
          EntityContextMenus.showTrackMenu(context, track: item);
        },
      );
    } */

    return null;
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
      final entry = entries[i];
      if (entry.value.isEmpty) continue;
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

  Widget? _buildHomeCard(dynamic item, {bool useSpecialCardStyle = false}) {
    if (item is GenericPlaylist) {
      return PlaylistCard(playlist: item);
    }

    if (item is GenericAlbum) {
      return AlbumCard(album: item);
    }

    if (item is GenericSimpleArtist) {
      return ArtistCard(artist: item);
    }

    return null;
  }

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
      itemWidth: 160,
      itemHeight: useSpecialCardStyle
          ? 168
          : null, // null falls back to the GenericCard default
      itemBuilder: (context, item) =>
          _buildHomeCard(item, useSpecialCardStyle: useSpecialCardStyle) ??
          const SizedBox.shrink(),
    );
  }
}
