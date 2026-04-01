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
import '../models/library_folder.dart';
import '../utils/logger.dart';
import '../services/wisp_audio_handler.dart';
import '../models/metadata_models.dart';
import '../services/metadata_cache.dart';
import '../widgets/hover_underline.dart';
import '../widgets/navigation.dart';
import '../widgets/like_button.dart';
import 'list_detail.dart';
import '../providers/library/library_state.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/local_playlists.dart';
import '../providers/connect/connect_session_provider.dart';
import '../providers/navigation_state.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/app_navigation.dart';
import '../utils/liked_songs.dart';
import '../widgets/liked_songs_art.dart';
import '../widgets/provider_disabled_state.dart';
import '../widgets/entity_context_menus.dart';

bool _isLocalThumbnailPath(String path) {
  return path.startsWith('/') || path.startsWith('file://');
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
  List<GenericSong> _topTracks = [];
  List<GenericSimpleArtist> _topArtists = [];
  List<GenericAlbum> _savedAlbums = [];
  List<GenericPlaylist> _savedPlaylists = [];
  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericSimpleArtist> _followedArtists = [];
  Map<String, List<dynamic>> _homeSections = {};
  String? _hoveredTrackId;

  late final SpotifyInternalProvider _spotifyProvider;
  late final LocalPlaylistState _localPlaylistState;
  bool _wasAuthenticated = false;
  VoidCallback? _localPlaylistListener;
  VoidCallback? _refreshListener;
  int _lastRefreshTick = 0;

  NavigationState get _navState => context.read<NavigationState>();
  LibraryView get _currentLibraryView => _navState.selectedLibraryView;
  int get _currentNavIndex => _navState.selectedNavIndex;

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

      var userLibrary = await spotifyInternal.getUserLibrary();
      final userHome = await spotifyInternal.getUserHome(policy: policy);

      // Import remote folders
      try {
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
      } catch (e) {
        logger.w('[Views/Home] Failed to process remote folders: $e');
      }

      final internalPlaylists = userLibrary.saved_playlists;
      final playlistsWithLiked = [
        likedPlaylist,
        ...internalPlaylists.where((p) => p.id != likedSongsPlaylistId),
      ];
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
          _homeSections = userHome.sections;
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

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();
    if (!preferences.metadataSpotifyEnabled) {
      return const ProviderDisabledState();
    }

    final bool isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return Consumer<SpotifyInternalProvider>(
      builder: (context, spotify, child) {
        if (!spotify.isAuthenticated) {
          return _buildUnauthenticatedView();
        }

        if (_isLoading) {
          return _buildLoadingView();
        }

        return _buildMainContent(isDesktop);
      },
    );
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

          ...dynamicSections.map(
            (section) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: section,
              ),
            ),
          ),

          // "this past month" section
          if (_topTracks.isNotEmpty || _topArtists.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Text(
                  'this past month',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          // Top Tracks horizontal scroll
          if (_topTracks.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'your top tracks',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _topTracks.take(5).length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final track = _topTracks[index];
                        return _buildMobileHorizontalCard(
                          imageUrl: track.thumbnailUrl,
                          title: track.title,
                          subtitle: track.artists.map((a) => a.name).join(', '),
                          onTap: () async {
                            final player = context.read<WispAudioHandler>();
                            player.clearQueue();
                            await player.playTrack(track);
                          },
                          onLongPress: () {
                            final navState = context.read<NavigationState>();
                            
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Top Artists horizontal scroll
          if (_topArtists.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        'your top artists',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 220,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _topArtists.take(5).length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          final artist = _topArtists[index];
                          return _buildMobileHorizontalCard(
                            imageUrl: artist.thumbnailUrl,
                            title: artist.name,
                            subtitle: 'Artist',
                            onTap: () => _openArtist(artist),
                            onLongPress: () {
                              final navState = context.read<NavigationState>();
                              
                            },
                          );
                        },
                      ),
                    ),
                  ],
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 40,
                  height: 40,
                  color: Colors.grey[900],
                  child:
                      customArt ??
                      (imageUrl.isNotEmpty
                          ? (isLocalThumb
                                ? Image.file(
                                    File(imageUrl.replaceFirst('file://', '')),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: imageUrl,
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
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
        subtitle: item.author.displayName,
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
          final player = context.read<WispAudioHandler>();
          player.clearQueue();
          await player.playTrack(item);
        },
        onLongPress: () {
          EntityContextMenus.showTrackMenu(context, track: item);
        },
      );
    }

    return null;
  }

  Widget _buildMobileHorizontalCard({
    required String imageUrl,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Widget? customArt,
  }) {
    final isLocalThumb = imageUrl.isNotEmpty && _isLocalThumbnailPath(imageUrl);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 144,
                  height: 144,
                  color: Colors.grey[900],
                  child:
                      customArt ??
                      (imageUrl.isNotEmpty
                          ? (isLocalThumb
                                ? Image.file(
                                    File(imageUrl.replaceFirst('file://', '')),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                      size: 48,
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                      size: 48,
                                    ),
                                  ))
                          : Icon(
                              Icons.music_note,
                              color: Colors.grey[700],
                              size: 48,
                            )),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
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
    const minWidthForSpecialCard = 1200.0;
    final canShowSpecialCard = viewWidth >= minWidthForSpecialCard;

    final quickRows = _buildDesktopQuickRows();
    final dynamicEntries = ((quickRows != null)
            ? _homeSections.entries.skip(1)
            : _homeSections.entries)
        .toList(growable: false);

    final newMusicIndex = dynamicEntries.indexWhere(
      (entry) => entry.key.trim().toLowerCase() == 'new music',
    );
    final rightSectionIndex =
      (newMusicIndex == 0 && dynamicEntries.length > 1) ? 1 : 0;

    final firstDynamicSectionCards =
      (dynamicEntries.isNotEmpty && rightSectionIndex < dynamicEntries.length)
      ? dynamicEntries[rightSectionIndex].value
              .map<Widget?>((item) => _buildHomeCard(item))
              .whereType<Widget>()
              .toList()
        : const <Widget>[];
    final firstDynamicSectionWidget =
        dynamicEntries.isNotEmpty && firstDynamicSectionCards.isNotEmpty
      ? _buildSection(
        dynamicEntries[rightSectionIndex].key,
        firstDynamicSectionCards,
        showTitle: false,
        )
        : null;

    final newMusicSpecialCard =
      canShowSpecialCard &&
        newMusicIndex >= 0 && dynamicEntries[newMusicIndex].value.isNotEmpty
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
        if (quickRows != null) quickRows,
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
        else if (firstDynamicSectionWidget != null)
          firstDynamicSectionWidget,
        ...dynamicSections,

        // Top Tracks as a table/list
        if (_topTracks.isNotEmpty) ...[
          Text(
            'Your Top Tracks',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          SizedBox(height: 300, child: _buildTopTracksTable()),
          SizedBox(height: 32),
        ],

        // Top Artists as a table
        if (_topArtists.isNotEmpty) ...[
          Text(
            'Your Top Artists',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          SizedBox(height: 300, child: _buildTopArtistsTable()),
          SizedBox(height: 32),
        ],
      ],
    );
  }

  Widget? _buildDesktopQuickRows() {
    if (_homeSections.isEmpty) return null;
    final firstSection = _homeSections.entries.first;
    final player = context.watch<WispAudioHandler>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemsPerRow = (maxWidth / 220).floor().clamp(1, 5);
        final maxItems = min(itemsPerRow * 2, 8);
        final cards = firstSection.value
            .map<Widget?>((item) => _buildHomeQuickTile(item, player))
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

  bool _isActivePlaylist(WispAudioHandler player, GenericPlaylist item) {
    if (player.playbackContextType != 'playlist') return false;
    if (player.playbackContextID == item.id) return true;
    final contextName = player.playbackContextName?.trim();
    return contextName != null &&
        contextName.isNotEmpty &&
        contextName == item.title.trim();
  }

  bool _isActiveAlbum(WispAudioHandler player, GenericAlbum item) {
    if (player.playbackContextType == 'album') {
      if (player.playbackContextID == item.id) return true;
      final contextName = player.playbackContextName?.trim();
      return contextName != null &&
          contextName.isNotEmpty &&
          contextName == item.title.trim();
    }
    return player.currentTrack?.album?.id == item.id;
  }

  bool _isActiveArtist(WispAudioHandler player, GenericSimpleArtist item) {
    if (player.playbackContextType == 'artist') {
      if (player.playbackContextID == item.id) return true;
      final contextName = player.playbackContextName?.trim();
      return contextName != null &&
          contextName.isNotEmpty &&
          contextName == item.name.trim();
    }
    final currentTrack = player.currentTrack;
    if (currentTrack == null) return false;
    return currentTrack.artists.any((a) => a.id == item.id);
  }

  Widget? _buildHomeQuickTile(dynamic item, WispAudioHandler player) {
    final isPlaying = player.isPlaying;
    if (item is GenericPlaylist) {
      final isActive = _isActivePlaylist(player, item);
      return _HomeQuickTile(
        imageUrl: item.thumbnailUrl,
        title: item.title,
        subtitle: item.author.displayName,
        isActive: isActive,
        isPlaying: isPlaying,
        showPlayingWaveform: true,
        customArt: isLikedSongsPlaylistId(item.id)
            ? const LikedSongsArt()
            : null,
        onTap: () => _openSharedList(
          SharedListType.playlist,
          item.id,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        ),
        onPlay: () => _playPlaylist(item.id, contextNameOverride: item.title),
        onSecondaryTapDown: (details) {
          EntityContextMenus.showPlaylistMenu(
            context,
            playlist: item,
            globalPosition: details.globalPosition,
          );
        },
        onLongPress: () {
          EntityContextMenus.showPlaylistMenu(context, playlist: item);
        },
      );
    }

    if (item is GenericAlbum) {
      final isActive = _isActiveAlbum(player, item);
      return _HomeQuickTile(
        imageUrl: item.thumbnailUrl,
        title: item.title,
        subtitle: item.artists.map((a) => a.name).join(', '),
        isActive: isActive,
        isPlaying: isPlaying,
        onTap: () => _openSharedList(
          SharedListType.album,
          item.id,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        ),
        onPlay: () => _playAlbum(item.id),
        onSecondaryTapDown: (details) {
          EntityContextMenus.showAlbumMenu(
            context,
            album: item,
            globalPosition: details.globalPosition,
          );
        },
        onLongPress: () {
          EntityContextMenus.showAlbumMenu(context, album: item);
        },
      );
    }

    if (item is GenericSimpleArtist) {
      final isActive = _isActiveArtist(player, item);
      return _HomeQuickTile(
        imageUrl: item.thumbnailUrl,
        title: item.name,
        subtitle: 'Artist',
        isActive: isActive,
        isPlaying: isPlaying,
        onTap: () => _openArtist(item),
        onPlay: () => _playArtist(item.id),
        onSecondaryTapDown: (details) {
          EntityContextMenus.showArtistMenu(
            context,
            artist: item,
            globalPosition: details.globalPosition,
          );
        },
        onLongPress: () {
          EntityContextMenus.showArtistMenu(context, artist: item);
        },
      );
    }

    if (item is GenericSong) {
      final isActive = player.currentTrack?.id == item.id;
      return _HomeQuickTile(
        imageUrl: item.thumbnailUrl,
        title: item.title,
        subtitle: item.artists.map((a) => a.name).join(', '),
        isActive: isActive,
        isPlaying: isPlaying,
        onTap: () async {
          final player = context.read<WispAudioHandler>();
          player.clearQueue();
          await player.playTrack(item);
        },
        onPlay: () async {
          final player = context.read<WispAudioHandler>();
          player.clearQueue();
          await player.playTrack(item);
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
    }

    return null;
  }

  List<Widget> _buildDynamicHomeSections({
    bool skipFirst = false,
    Set<int> skipEntryIndexes = const <int>{},
    bool allowSpecialCardStyle = true,
  }) {
    if (_homeSections.isEmpty) return const [];
    final widgets = <Widget>[];

    var entries = (skipFirst
        ? _homeSections.entries.skip(1)
        : _homeSections.entries)
        .toList(growable: false);
    for (var i = 0; i < entries.length; i++) {
      if (skipEntryIndexes.contains(i)) continue;
      final entry = entries[i];
      final useSpecialCardStyle =
          allowSpecialCardStyle &&
          i == 0 &&
          entry.key.trim().toLowerCase() == 'new music';
      final cards = entry.value
          .map<Widget?>(
            (item) => _buildHomeCard(
              item,
              useSpecialCardStyle: useSpecialCardStyle,
            ),
          )
          .whereType<Widget>()
          .toList();
      if (cards.isEmpty) continue;
      widgets.add(
        _buildSection(
          entry.key,
          cards,
          showTitle: !useSpecialCardStyle,
          expandCardsToRowWidth: useSpecialCardStyle,
        ),
      );
    }

    return widgets;
  }

  Widget? _buildHomeCard(dynamic item, {bool useSpecialCardStyle = false}) {
    final player = context.watch<WispAudioHandler>();
    final isPlaying = player.isPlaying;
    if (item is GenericPlaylist) {
      final isActive = _isActivePlaylist(player, item);
      if (useSpecialCardStyle) {
        return _SpecialCard(
          title: item.title,
          subtitle: item.author.displayName,
          id: item.id,
          thumbnailUrl: item.thumbnailUrl,
          onTap: () => _openSharedList(
            SharedListType.playlist,
            item.id,
            title: item.title,
            thumbnailUrl: item.thumbnailUrl,
          ),
          onPlay: () => _playPlaylist(item.id, contextNameOverride: item.title),
          isActive: isActive,
          isPlaying: isPlaying,
          currentLibraryView: _currentLibraryView,
          currentNavIndex: _currentNavIndex,
        );
      }
      return _PlaylistCard(
        playlist: item,
        onTap: () => _openSharedList(
          SharedListType.playlist,
          item.id,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        ),
        onPlay: () => _playPlaylist(item.id, contextNameOverride: item.title),
        isActive: isActive,
        isPlaying: isPlaying,
        playlists: _savedPlaylists,
        albums: _savedAlbums,
        artists: _followedArtists,
        currentLibraryView: _currentLibraryView,
        currentNavIndex: _currentNavIndex,
      );
    }

    if (item is GenericAlbum) {
      final isActive = _isActiveAlbum(player, item);
      if (useSpecialCardStyle) {
        final subtitle = item.artists.map((a) => a.name).join(', ');
        return _SpecialCard(
          title: item.title,
          subtitle: subtitle,
          id: item.id,
          thumbnailUrl: item.thumbnailUrl,
          onTap: () => _openSharedList(
            SharedListType.album,
            item.id,
            title: item.title,
            thumbnailUrl: item.thumbnailUrl,
          ),
          onPlay: () => _playAlbum(item.id),
          isActive: isActive,
          isPlaying: isPlaying,
          currentLibraryView: _currentLibraryView,
          currentNavIndex: _currentNavIndex,
        );
      }
      return _AlbumCard(
        album: item,
        onTap: () => _openSharedList(
          SharedListType.album,
          item.id,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        ),
        onPlay: () => _playAlbum(item.id),
        isActive: isActive,
        isPlaying: isPlaying,
        playlists: _savedPlaylists,
        albums: _savedAlbums,
        artists: _followedArtists,
        currentLibraryView: _currentLibraryView,
        currentNavIndex: _currentNavIndex,
      );
    }

    if (item is GenericSimpleArtist) {
      final isActive = _isActiveArtist(player, item);
      if (useSpecialCardStyle) {
        return _SpecialCard(
          title: item.name,
          subtitle: 'Artist',
          id: item.id,
          thumbnailUrl: item.thumbnailUrl,
          onTap: () => _openArtist(item),
          onPlay: () => _playArtist(item.id),
          isActive: isActive,
          isPlaying: isPlaying,
          currentLibraryView: _currentLibraryView,
          currentNavIndex: _currentNavIndex,
        );
      }
      return _ArtistCard(
        artist: item,
        onTap: () => _openArtist(item),
        onPlay: () => _playArtist(item.id),
        isActive: isActive,
        isPlaying: isPlaying,
        playlists: _savedPlaylists,
        albums: _savedAlbums,
        artists: _followedArtists,
        currentLibraryView: _currentLibraryView,
        currentNavIndex: _currentNavIndex,
      );
    }

    return null;
  }

  Widget _buildTopTracksTable() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF181818).withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _topTracks.length,
        itemBuilder: (context, index) {
          final track = _topTracks[index];
          final isEven = index % 2 == 0;
          return _buildTrackRow(track, index, isEven);
        },
      ),
    );
  }

  Widget _buildTrackRow(GenericSong track, int index, bool isEven) {
    final player = context.watch<WispAudioHandler>();
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final album = track.album;
    final primaryArtist = track.artists.isNotEmpty ? track.artists.first : null;
    final isHovering = _hoveredTrackId == track.id;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!isDesktop) return;
        setState(() => _hoveredTrackId = track.id);
      },
      onExit: (_) {
        if (!isDesktop) return;
        setState(() => _hoveredTrackId = null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: isDesktop
            ? (details) {
                EntityContextMenus.showTrackMenu(
                  context,
                  track: track,
                  globalPosition: details.globalPosition,
                );
              }
            : null,
        onLongPress: isDesktop
            ? null
            : () {
                EntityContextMenus.showTrackMenu(context, track: track);
              },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () async {
              final player = context.read<WispAudioHandler>();

              // Clear queue and play just this track
              player.clearQueue();

              try {
                await player.playTrack(track);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to play track: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isEven
                    ? Colors.transparent
                    : Colors.black.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  // Number
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    ),
                  ),
                  // Album art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey[900],
                      child: track.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: track.thumbnailUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[800]),
                              errorWidget: (context, url, error) => Icon(
                                Icons.music_note,
                                color: Colors.grey[700],
                              ),
                            )
                          : Icon(Icons.music_note, color: Colors.grey[700]),
                    ),
                  ),
                  SizedBox(width: 16),
                  // Track info
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        (isDesktop && album != null && album.id.isNotEmpty)
                            ? HoverUnderline(
                                onTap: () {
                                  _openSharedList(
                                    SharedListType.album,
                                    album.id,
                                    title: album.title,
                                    thumbnailUrl: album.thumbnailUrl,
                                  );
                                },
                                builder: (isHovering) => Text(
                                  track.title,
                                  style: TextStyle(
                                    color: player.currentTrack?.id == track.id
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    decoration: isHovering
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : Text(
                                track.title,
                                style: TextStyle(
                                  color: player.currentTrack?.id == track.id
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        if (track.artists.isNotEmpty) ...[
                          SizedBox(height: 2),
                          (isDesktop && primaryArtist != null)
                              ? HoverUnderline(
                                  onTap: () => _openArtist(primaryArtist),
                                  onSecondaryTapDown: (details) {
                                    EntityContextMenus.showTrackMenu(
                                      context,
                                      track: track,
                                      globalPosition: details.globalPosition,
                                    );
                                  },
                                  builder: (isHovering) => Text(
                                    track.artists.map((a) => a.name).join(', '),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                      decoration: isHovering
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : Text(
                                  track.artists.map((a) => a.name).join(', '),
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ],
                      ],
                    ),
                  ),
                  // Album name
                  Expanded(
                    flex: 2,
                    child: (isDesktop && album != null && album.id.isNotEmpty)
                        ? HoverUnderline(
                            onTap: () {
                              _openSharedList(
                                SharedListType.album,
                                album.id,
                                title: album.title,
                                thumbnailUrl: album.thumbnailUrl,
                              );
                            },
                            onSecondaryTapDown: (details) {
                              EntityContextMenus.showTrackMenu(
                                context,
                                track: track,
                                globalPosition: details.globalPosition,
                              );
                            },
                            builder: (isHovering) => Text(
                              album.title,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                                decoration: isHovering
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : Text(
                            track.album?.title ?? '',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  SizedBox(width: 16),
                  if (isDesktop) ...[
                    AnimatedOpacity(
                      opacity: isHovering ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: IgnorePointer(
                        ignoring: !isHovering,
                        child: LikeButton(
                          track: track,
                          iconSize: 16,
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                  // Duration
                  SizedBox(
                    width: 50,
                    child: Text(
                      _formatDuration(track.durationSecs * 1000),
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(width: isDesktop ? 16 : 12),
                  // Spotify icon
                  Icon(
                    Icons.graphic_eq,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopArtistsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF181818).withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _topArtists.length,
        itemBuilder: (context, index) {
          final artist = _topArtists[index];
          final isEven = index % 2 == 0;
          final isDesktop =
              Platform.isLinux || Platform.isMacOS || Platform.isWindows;
          return GestureDetector(
            onSecondaryTapDown: isDesktop
                ? (details) {
                    EntityContextMenus.showArtistMenu(
                      context,
                      artist: artist,
                      globalPosition: details.globalPosition,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    EntityContextMenus.showArtistMenu(context, artist: artist);
                  },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () {
                  _openArtist(artist);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isEven
                        ? Colors.transparent
                        : Colors.black.withOpacity(0.1),
                  ),
                  child: Row(
                    children: [
                      // Number
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                      ),
                      // Artist image
                      ClipOval(
                        child: Container(
                          width: 40,
                          height: 40,
                          color: Colors.grey[900],
                          child: artist.thumbnailUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: artist.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: Colors.grey[800]),
                                  errorWidget: (context, url, error) => Icon(
                                    Icons.person,
                                    color: Colors.grey[700],
                                  ),
                                )
                              : Icon(Icons.person, color: Colors.grey[700]),
                        ),
                      ),
                      SizedBox(width: 16),
                      // Artist name
                      Expanded(
                        child: Text(
                          artist.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 16),
                      // Artist label
                      Text(
                        'Artist',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                      SizedBox(width: 8),
                      // Spotify icon
                      Icon(
                        Icons.graphic_eq,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return '--:--';
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildSection(
    String title,
    List<Widget> cards, {
    bool showTitle = true,
    bool expandCardsToRowWidth = false,
  }) {
    return _ScrollableCardSection(
      title: title,
      cards: cards,
      showTitle: showTitle,
      expandCardsToRowWidth: expandCardsToRowWidth,
    );
  }

  Future<void> _playAlbum(String albumId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final connect = context.read<ConnectSessionProvider>();
    try {
      final album = await spotify.getAlbumInfo(albumId);
      final tracks = album.songs ?? [];
      if (tracks.isEmpty) return;
      await connect.requestSetQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'album',
        contextName: album.title,
        contextID: album.id,
        contextSource: album.source,
      );
    } catch (_) {}
  }

  Future<void> _playPlaylist(
    String playlistId, {
    String? contextNameOverride,
  }) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final connect = context.read<ConnectSessionProvider>();
    try {
      final playlist = await spotify.getPlaylistInfo(playlistId);
      final items = playlist.songs ?? [];
      if (items.isEmpty) return;
      final tracks = items
          .map(
            (item) => GenericSong(
              id: item.id,
              source: item.source,
              title: item.title,
              artists: item.artists,
              thumbnailUrl: item.thumbnailUrl,
              explicit: item.explicit,
              album: item.album,
              durationSecs: item.durationSecs,
            ),
          )
          .toList();
      await connect.requestSetQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'playlist',
        contextName:
            (contextNameOverride != null && contextNameOverride.isNotEmpty)
            ? contextNameOverride
            : playlist.title,
        contextID: playlist.id,
        contextSource: playlist.source,
      );
      context.read<LibraryFolderState>().markPlaylistPlayed(playlistId);
    } catch (_) {}
  }

  Future<void> _playArtist(String artistId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final connect = context.read<ConnectSessionProvider>();
    try {
      final artist = await spotify.getArtistInfo(artistId);
      final tracks = artist.topSongs;
      if (tracks.isEmpty) return;
      await connect.requestSetQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'artist',
        contextName: artist.name,
        contextID: artist.id,
        contextSource: artist.source,
      );
    } catch (_) {}
  }
}

class _ArtistCard extends StatelessWidget {
  final GenericSimpleArtist artist;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final bool isActive;
  final bool isPlaying;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _ArtistCard({
    required this.artist,
    required this.onTap,
    required this.onPlay,
    required this.isActive,
    required this.isPlaying,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.currentLibraryView,
    this.currentNavIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return SizedBox(
      width: 180,
      child: ClipRect(
        child: Material(
          color: Color(0xFF181818),
          borderRadius: BorderRadius.circular(8),
          child: _HoverPlayCard(
            onTap: onTap,
            onPlay: onPlay,
            isActive: isActive,
            isPlaying: isPlaying,
            onSecondaryTapDown: isDesktop
                ? (details) {
                    EntityContextMenus.showArtistMenu(
                      context,
                      artist: artist,
                      globalPosition: details.globalPosition,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    EntityContextMenus.showArtistMenu(context, artist: artist);
                  },
            child: Padding(
              padding: const EdgeInsets.all(11.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipOval(
                    child: Container(
                      width: 120,
                      height: 120,
                      color: Colors.grey[900],
                      child: artist.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: artist.thumbnailUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[800]),
                              errorWidget: (context, url, error) => const Icon(
                                Icons.person,
                                size: 48,
                                color: Colors.grey,
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 48,
                              color: Colors.grey,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    artist.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Artist',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final GenericAlbum album;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final bool isActive;
  final bool isPlaying;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _AlbumCard({
    required this.album,
    required this.onTap,
    required this.onPlay,
    required this.isActive,
    required this.isPlaying,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.currentLibraryView,
    this.currentNavIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return SizedBox(
      width: 180,
      child: ClipRect(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: _HoverPlayCard(
            onTap: onTap,
            onPlay: onPlay,
            isActive: isActive,
            isPlaying: isPlaying,
            onSecondaryTapDown: isDesktop
                ? (details) {
                    EntityContextMenus.showAlbumMenu(
                      context,
                      album: album,
                      globalPosition: details.globalPosition,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    EntityContextMenus.showAlbumMenu(context, album: album);
                  },
            child: Padding(
              padding: const EdgeInsets.all(11.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 150,
                      height: 150,
                      color: Colors.transparent,
                      child: album.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: album.thumbnailUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[800]),
                              errorWidget: (context, url, error) => const Icon(
                                Icons.album,
                                size: 48,
                                color: Colors.grey,
                              ),
                            )
                          : const Icon(
                              Icons.album,
                              size: 48,
                              color: Colors.grey,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    album.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    album.artists.map((a) => a.name).join(', '),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final GenericPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final bool isActive;
  final bool isPlaying;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onPlay,
    required this.isActive,
    required this.isPlaying,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.currentLibraryView,
    this.currentNavIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final isLiked = isLikedSongsPlaylistId(playlist.id);
    return SizedBox(
      width: 180,
      child: ClipRect(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: _HoverPlayCard(
            onTap: onTap,
            onPlay: onPlay,
            isActive: isActive,
            isPlaying: isPlaying,
            onSecondaryTapDown: isDesktop
                ? (details) {
                    EntityContextMenus.showPlaylistMenu(
                      context,
                      playlist: playlist,
                      globalPosition: details.globalPosition,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    EntityContextMenus.showPlaylistMenu(
                      context,
                      playlist: playlist,
                    );
                  },
            child: Padding(
              padding: const EdgeInsets.all(11.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 150,
                      height: 150,
                      color: Colors.transparent,
                      child: isLiked
                          ? const LikedSongsArt()
                          : (playlist.thumbnailUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: playlist.thumbnailUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                    errorWidget: (context, url, error) =>
                                        const Icon(
                                          Icons.playlist_play,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                  )
                                : const Icon(
                                    Icons.playlist_play,
                                    size: 48,
                                    color: Colors.grey,
                                  )),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    playlist.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    playlist.author.displayName,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecialCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String id;
  final String thumbnailUrl;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final bool isActive;
  final bool isPlaying;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _SpecialCard({
    required this.title,
    required this.subtitle,
    required this.id,
    required this.thumbnailUrl,
    required this.onTap,
    required this.onPlay,
    required this.isActive,
    required this.isPlaying,
    this.currentLibraryView,
    this.currentNavIndex,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackColor = const Color(0xFF181818);

    Widget buildCard(Color backgroundColor) {
      return SizedBox(
        width: double.infinity,
        child: ClipRect(
          child: Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            child: _HoverPlayCard(
              onTap: onTap,
              onPlay: onPlay,
              isActive: isActive,
              isPlaying: isPlaying,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "New Release",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 120,
                            height: 120,
                            child: thumbnailUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: thumbnailUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                    errorWidget: (context, url, error) =>
                                        const Icon(
                                          Icons.music_note,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                  )
                                : const Icon(
                                    Icons.music_note,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 24,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.grey[200],
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ]
                    ),
                    const SizedBox(height: 9),
                    Text(
                      "Listen to this brand new release from $subtitle",
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (thumbnailUrl.isEmpty) {
      return buildCard(fallbackColor);
    }

    return FutureBuilder<ColorScheme>(
      future: ColorScheme.fromImageProvider(
        provider: CachedNetworkImageProvider(thumbnailUrl),
      ),
      builder: (context, snapshot) {
        final sourceColor = snapshot.data?.primary ?? fallbackColor;
        final backgroundColor = HSLColor.fromColor(
          sourceColor,
        ).withLightness(0.5).withSaturation(0.65).toColor();
        return buildCard(backgroundColor);
      },
    );
  }
}

class _HomeQuickTile extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final bool isActive;
  final bool isPlaying;
  final bool showPlayingWaveform;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;
  final Widget? customArt;

  const _HomeQuickTile({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onPlay,
    required this.isActive,
    required this.isPlaying,
    this.showPlayingWaveform = false,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.customArt,
  });

  @override
  State<_HomeQuickTile> createState() => _HomeQuickTileState();
}

class _HomeQuickTileState extends State<_HomeQuickTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final isLocalThumb =
        widget.imageUrl.isNotEmpty && _isLocalThumbnailPath(widget.imageUrl);

    return MouseRegion(
      cursor: isDesktop ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onSecondaryTapDown: widget.onSecondaryTapDown,
          onLongPress: widget.onLongPress,
          behavior: HitTestBehavior.opaque,
          child: InkWell(
            mouseCursor: isDesktop ? SystemMouseCursors.click : null,
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.025),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey[900],
                      child:
                          widget.customArt ??
                          (widget.imageUrl.isNotEmpty
                              ? (isLocalThumb
                                    ? Image.file(
                                        File(
                                          widget.imageUrl.replaceFirst(
                                            'file://',
                                            '',
                                          ),
                                        ),
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, url, error) =>
                                            Icon(
                                              Icons.music_note,
                                              color: Colors.grey[700],
                                            ),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: widget.imageUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Container(color: Colors.grey[800]),
                                        errorWidget: (context, url, error) =>
                                            Icon(
                                              Icons.music_note,
                                              color: Colors.grey[700],
                                            ),
                                      ))
                              : Icon(
                                  Icons.music_note,
                                  color: Colors.grey[700],
                                )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedOpacity(
                          opacity: widget.showPlayingWaveform &&
                                  widget.isActive &&
                                  widget.isPlaying
                              ? 1
                              : 0,
                          duration: const Duration(milliseconds: 120),
                          child: _AnimatedQuickWaveform(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: _isHovering ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: IgnorePointer(
                            ignoring: !_isHovering,
                            child: IconButton(
                              icon: Icon(
                                widget.isActive && widget.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                final player = context.read<WispAudioHandler>();
                                if (widget.isActive) {
                                  if (player.isPlaying) {
                                    player.pause();
                                  } else {
                                    player.play();
                                  }
                                  return;
                                }
                                widget.onPlay();
                              },
                              splashRadius: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedQuickWaveform extends StatefulWidget {
  final Color color;

  const _AnimatedQuickWaveform({required this.color});

  @override
  State<_AnimatedQuickWaveform> createState() => _AnimatedQuickWaveformState();
}

class _AnimatedQuickWaveformState extends State<_AnimatedQuickWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * pi;
        double barHeight(double phase) {
          final value = (sin(t + phase) + 1) / 2;
          return 4 + value * 10;
        }

        return SizedBox(
          width: 16,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _waveBar(widget.color, barHeight(0.0)),
              const SizedBox(width: 2),
              _waveBar(widget.color, barHeight(1.4)),
              const SizedBox(width: 2),
              _waveBar(widget.color, barHeight(2.8)),
            ],
          ),
        );
      },
    );
  }

  Widget _waveBar(Color color, double height) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _HoverPlayCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final bool isActive;
  final bool isPlaying;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;

  const _HoverPlayCard({
    required this.child,
    required this.onTap,
    required this.onPlay,
    required this.isActive,
    required this.isPlaying,
    this.onSecondaryTapDown,
    this.onLongPress,
  });

  @override
  State<_HoverPlayCard> createState() => _HoverPlayCardState();
}

class _HoverPlayCardState extends State<_HoverPlayCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return MouseRegion(
      cursor: isDesktop ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onSecondaryTapDown: widget.onSecondaryTapDown,
        onLongPress: widget.onLongPress,
        child: InkWell(
          mouseCursor: isDesktop ? SystemMouseCursors.click : null,
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                widget.child,
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: AnimatedOpacity(
                    opacity: _isHovering ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: IgnorePointer(
                      ignoring: !_isHovering,
                      child: Material(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                        child: IconButton(
                          icon: Icon(
                            widget.isActive && widget.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            final player = context.read<WispAudioHandler>();
                            if (widget.isActive) {
                              if (player.isPlaying) {
                                player.pause();
                              } else {
                                player.play();
                              }
                              return;
                            }
                            widget.onPlay();
                          },
                          splashRadius: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollableCardSection extends StatefulWidget {
  final String title;
  final List<Widget> cards;
  final bool showTitle;
  final bool expandCardsToRowWidth;

  const _ScrollableCardSection({
    required this.title,
    required this.cards,
    this.showTitle = true,
    this.expandCardsToRowWidth = false,
  });

  @override
  State<_ScrollableCardSection> createState() => _ScrollableCardSectionState();
}

class _ScrollableCardSectionState extends State<_ScrollableCardSection> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final maxExtent = _controller.position.maxScrollExtent;
    final offset = _controller.offset;
    final canLeft = offset > 4;
    final canRight = offset < (maxExtent - 4);
    if (canLeft == _canScrollLeft && canRight == _canScrollRight) return;
    setState(() {
      _canScrollLeft = canLeft;
      _canScrollRight = canRight;
    });
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle)
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        SizedBox(height: widget.showTitle ? 16 : 0),
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: widget.expandCardsToRowWidth ? 170 : 230,
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: widget.cards.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final card = widget.cards[index];
                      if (!widget.expandCardsToRowWidth) {
                        return card;
                      }
                      return SizedBox(width: constraints.maxWidth, child: card);
                    },
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _canScrollLeft ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: IgnorePointer(
                        ignoring: !_canScrollLeft,
                        child: Center(
                          child: _ScrollArrowButton(
                            icon: Icons.chevron_left,
                            onPressed: () => _scrollBy(-240),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _canScrollRight ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: IgnorePointer(
                        ignoring: !_canScrollRight,
                        child: Center(
                          child: _ScrollArrowButton(
                            icon: Icons.chevron_right,
                            onPressed: () => _scrollBy(240),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ScrollArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ScrollArrowButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.5),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        splashRadius: 18,
      ),
    );
  }
}
