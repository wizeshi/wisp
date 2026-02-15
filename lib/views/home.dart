/// Home page with user's Spotify library
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show Platform, File;
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../providers/metadata/spotify.dart';
import '../utils/logger.dart';
import '../providers/audio/player.dart';
import '../models/metadata_models.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/library_item_context_menu.dart';
import '../widgets/hover_underline.dart';
import '../widgets/navigation.dart';
import '../widgets/like_button.dart';
import 'list_detail.dart';
import 'artist_detail.dart';
import '../providers/library/library_state.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/local_playlists.dart';
import '../providers/navigation_state.dart';
import '../services/tab_routes.dart';
import '../utils/liked_songs.dart';
import '../widgets/liked_songs_art.dart';

bool _isLocalThumbnailPath(String path) {
  return path.startsWith('/') || path.startsWith('file://');
}

Widget _buildPlaylistArtForCard(GenericPlaylist playlist) {
  if (isLikedSongsPlaylistId(playlist.id)) {
    return const LikedSongsArt();
  }
  final url = playlist.thumbnailUrl;
  if (url.isEmpty) {
    return const Center(
      child: Icon(
        Icons.playlist_play,
        size: 48,
        color: Colors.grey,
      ),
    );
  }
  if (_isLocalThumbnailPath(url)) {
    final path = url.replaceFirst('file://', '');
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, url, error) => const Icon(
        Icons.playlist_play,
        size: 48,
        color: Colors.grey,
      ),
    );
  }
  return CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    placeholder: (context, url) => Container(color: Colors.grey[800]),
    errorWidget: (context, url, error) => const Icon(
      Icons.playlist_play,
      size: 48,
      color: Colors.grey,
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  bool _isLoading = true;
  List<GenericSong> _topTracks = [];
  List<GenericSimpleArtist> _topArtists = [];
  List<GenericAlbum> _savedAlbums = [];
  List<GenericPlaylist> _savedPlaylists = [];
  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericSimpleArtist> _followedArtists = [];
  String? _hoveredTrackId;

  late final SpotifyProvider _spotifyProvider;
  bool _wasAuthenticated = false;
  VoidCallback? _localPlaylistListener;

  NavigationState get _navState => context.read<NavigationState>();
  LibraryView get _currentLibraryView => _navState.selectedLibraryView;
  int get _currentNavIndex => _navState.selectedNavIndex;

  @override
  void initState() {
    super.initState();
    _spotifyProvider = context.read<SpotifyProvider>();
    _wasAuthenticated = _spotifyProvider.isAuthenticated;
    _spotifyProvider.addListener(_handleAuthChange);

    final localState = context.read<LocalPlaylistState>();
    _localPlaylistListener = () {
      if (!mounted) return;
      final localState = context.read<LocalPlaylistState>();
      setState(() {
        _savedPlaylists = _mergeLocalPlaylists(
          _remotePlaylists,
          localState.genericPlaylists,
          localState.hiddenProviderPlaylistIds,
        );
      });
    };
    localState.addListener(_localPlaylistListener!);

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
    if (_localPlaylistListener != null) {
      context
          .read<LocalPlaylistState>()
          .removeListener(_localPlaylistListener!);
    }
    super.dispose();
  }

  bool _isTextInputFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;
    return context.widget is EditableText;
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

  Future<void> _loadData() async {
    final spotify = context.read<SpotifyProvider>();
    final libraryState = context.read<LibraryState>();

    setState(() => _isLoading = true);

    // Re-check auth state from storage
    await spotify.checkAuthState();

    logger.d('Loading home page data...');
    logger.d('Is authenticated: ${spotify.isAuthenticated}');

    if (!spotify.isAuthenticated) {
      logger.d('Not authenticated, skipping data load');
      libraryState.clear();
      setState(() => _isLoading = false);
      return;
    }

    try {
      logger.d('Starting API calls...');

      // Fetch user profile first (doesn't need to be in Future.wait)
      await spotify.fetchUserProfile();

      final results = await Future.wait([
        spotify.getUserTopTracks(limit: 10),
        spotify.getUserTopArtists(limit: 10),
        spotify.getUserAlbums(limit: 20),
        spotify.getUserFollowedArtists(limit: 20),
      ]);

      final playlists = await _fetchAllPlaylists(spotify);
      final cachedLiked = await spotify.getCachedSavedTracksAll();
      if (cachedLiked != null) {
        spotify.setLikedTracksFromItems(cachedLiked);
      } else {
        unawaited(spotify.refreshSavedTracksAll());
      }
      final likedPlaylist = buildLikedSongsPlaylist(
        userDisplayName: spotify.userDisplayName,
        total: cachedLiked?.length,
      );
      final playlistsWithLiked = [
        likedPlaylist,
        ...playlists.where((p) => p.id != likedSongsPlaylistId),
      ];
      final localState = context.read<LocalPlaylistState>();
      final localPlaylists = localState.genericPlaylists;
      _remotePlaylists = playlistsWithLiked;
      final mergedPlaylists = _mergeLocalPlaylists(
        _remotePlaylists,
        localPlaylists,
        localState.hiddenProviderPlaylistIds,
      );

      logger.d('API calls completed');
      logger.d('Top tracks: ${results[0].length}');
      logger.d('Top artists: ${results[1].length}');
      logger.d('Albums: ${results[2].length}');
      logger.d('Playlists: ${playlists.length}');
      logger.d('Followed artists: ${results[3].length}');

      setState(() {
        _topTracks = results[0] as List<GenericSong>;
        _topArtists = results[1] as List<GenericSimpleArtist>;
        _savedAlbums = results[2] as List<GenericAlbum>;
        _savedPlaylists = mergedPlaylists;
        _followedArtists = results[3] as List<GenericSimpleArtist>;
        _isLoading = false;
      });

      libraryState.setLibrary(
        playlists: _savedPlaylists,
        albums: _savedAlbums,
        artists: _followedArtists,
      );
      context
          .read<LibraryFolderState>()
          .syncPlaylists(libraryState.playlists);

      logger.d('State updated successfully');
    } catch (e) {
      logger.e('Failed to load data', error: e);
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
      }
    }
  }

  Future<List<GenericPlaylist>> _fetchAllPlaylists(
    SpotifyProvider spotify,
  ) async {
    const limit = 50;
    var offset = 0;
    final all = <GenericPlaylist>[];
    while (true) {
      final batch = await spotify.getUserPlaylists(
        limit: limit,
        offset: offset,
      );
      all.addAll(batch);
      if (batch.length < limit) {
        break;
      }
      offset += batch.length;
    }
    return all;
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
    final bool isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              if (_isTextInputFocused()) return null;
              final player = context.read<AudioPlayerProvider>();
              if (player.isPlaying) {
                player.pause();
              } else if (player.currentTrack != null ||
                  player.queue.isNotEmpty) {
                player.play();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Consumer<SpotifyProvider>(
            builder: (context, spotify, child) {
              if (!spotify.isAuthenticated) {
                return _buildUnauthenticatedView();
              }

              if (_isLoading) {
                return _buildLoadingView();
              }

              return _buildMainContent(isDesktop);
            },
          ),
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
          const Text(
            'Not connected to Spotify',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed(TabRoutes.settings);
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
      return RefreshIndicator(onRefresh: _loadData, child: _buildContentArea());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _buildMobileHomeContent(),
    );
  }

  String _getRandomGreeting(SpotifyProvider spotify) {
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
    final spotify = context.read<SpotifyProvider>();
    final greeting = _getRandomGreeting(spotify);

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
                      Navigator.of(context).pushNamed(TabRoutes.settings);
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
                  // Left column - Playlists
                  Expanded(
                    child: Column(
                      children: _savedPlaylists.take(4).map((playlist) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildMobileGridItem(
                            imageUrl: playlist.thumbnailUrl,
                            title: playlist.title,
                            subtitle: playlist.author.displayName,
                            customArt: isLikedSongsPlaylistId(playlist.id)
                                ? const LikedSongsArt()
                                : null,
                            onTap: () => _openSharedList(
                              SharedListType.playlist,
                              playlist.id,
                              title: playlist.title,
                              thumbnailUrl: playlist.thumbnailUrl,
                            ),
                            onLongPress: () {
                              final navState = context.read<NavigationState>();
                              LibraryItemContextMenu.show(
                                context: context,
                                item: playlist,
                                playlists: _savedPlaylists,
                                albums: _savedAlbums,
                                artists: _followedArtists,
                                currentLibraryView:
                                    navState.selectedLibraryView,
                                currentNavIndex: navState.selectedNavIndex,
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right column - Albums
                  Expanded(
                    child: Column(
                      children: _savedAlbums.take(4).map((album) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildMobileGridItem(
                            imageUrl: album.thumbnailUrl,
                            title: album.title,
                            subtitle: album.artists
                                .map((a) => a.name)
                                .join(', '),
                            onTap: () => _openSharedList(
                              SharedListType.album,
                              album.id,
                              title: album.title,
                              thumbnailUrl: album.thumbnailUrl,
                            ),
                            onLongPress: () {
                              final navState = context.read<NavigationState>();
                              LibraryItemContextMenu.show(
                                context: context,
                                item: album,
                                playlists: _savedPlaylists,
                                albums: _savedAlbums,
                                artists: _followedArtists,
                                currentLibraryView:
                                    navState.selectedLibraryView,
                                currentNavIndex: navState.selectedNavIndex,
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // "this past month" section
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
                            final player = context.read<AudioPlayerProvider>();
                            player.clearQueue();
                            await player.playTrack(track);
                          },
                          onLongPress: () {
                            final navState = context.read<NavigationState>();
                            TrackContextMenu.show(
                              context: context,
                              track: track,
                              playlists: _savedPlaylists,
                              albums: _savedAlbums,
                              artists: _followedArtists,
                              currentLibraryView: navState.selectedLibraryView,
                              currentNavIndex: navState.selectedNavIndex,
                            );
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
                              LibraryItemContextMenu.show(
                                context: context,
                                item: artist,
                                playlists: _savedPlaylists,
                                albums: _savedAlbums,
                                artists: _followedArtists,
                                currentLibraryView:
                                    navState.selectedLibraryView,
                                currentNavIndex: navState.selectedNavIndex,
                              );
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
                  child: customArt ??
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
            ],
          ),
        ),
      ),
    );
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
                  child: customArt ??
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
      ),
    );
  }

  void _openSharedList(
    SharedListType type,
    String id, {
    String? title,
    String? thumbnailUrl,
  }) {
    final navState = context.read<NavigationState>();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            SharedListDetailView(
              id: id,
              type: type,
              initialTitle: title,
              initialThumbnailUrl: thumbnailUrl,
              playlists: _savedPlaylists,
              albums: _savedAlbums,
              artists: _followedArtists,
              initialLibraryView: navState.selectedLibraryView,
              initialNavIndex: navState.selectedNavIndex,
            ),
      ),
    );
  }

  void _openArtist(GenericSimpleArtist artist) {
    final navState = context.read<NavigationState>();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArtistDetailView(
              artistId: artist.id,
              initialArtist: artist,
              playlists: _savedPlaylists,
              albums: _savedAlbums,
              artists: _followedArtists,
              initialLibraryView: navState.selectedLibraryView,
              initialNavIndex: navState.selectedNavIndex,
            ),
      ),
    );
  }

  Widget _buildContentArea() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Horizontal scrolling sections
        if (_savedPlaylists.isNotEmpty)
          _buildSection(
            'Playlists',
            _savedPlaylists
                .map(
                  (playlist) => _PlaylistCard(
                    playlist: playlist,
                    onTap: () => _openSharedList(
                      SharedListType.playlist,
                      playlist.id,
                      title: playlist.title,
                      thumbnailUrl: playlist.thumbnailUrl,
                    ),
                    playlists: _savedPlaylists,
                    albums: _savedAlbums,
                    artists: _followedArtists,
                    currentLibraryView: _currentLibraryView,
                    currentNavIndex: _currentNavIndex,
                  ),
                )
                .toList(),
          ),
        if (_savedAlbums.isNotEmpty)
          _buildSection(
            'Albums',
            _savedAlbums
                .map(
                  (album) => _AlbumCard(
                    album: album,
                    onTap: () => _openSharedList(
                      SharedListType.album,
                      album.id,
                      title: album.title,
                      thumbnailUrl: album.thumbnailUrl,
                    ),
                    playlists: _savedPlaylists,
                    albums: _savedAlbums,
                    artists: _followedArtists,
                    currentLibraryView: _currentLibraryView,
                    currentNavIndex: _currentNavIndex,
                  ),
                )
                .toList(),
          ),
        if (_followedArtists.isNotEmpty)
          _buildSection(
            'Following',
            _followedArtists
                .map(
                  (artist) => _ArtistCard(
                    artist: artist,
                    onTap: () => _openArtist(artist),
                    playlists: _savedPlaylists,
                    albums: _savedAlbums,
                    artists: _followedArtists,
                    currentLibraryView: _currentLibraryView,
                    currentNavIndex: _currentNavIndex,
                  ),
                )
                .toList(),
          ),

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
    final player = context.watch<AudioPlayerProvider>();
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
                TrackContextMenu.show(
                  context: context,
                  track: track,
                  position: details.globalPosition,
                  playlists: _savedPlaylists,
                  albums: _savedAlbums,
                  artists: _followedArtists,
                  currentLibraryView: _currentLibraryView,
                  currentNavIndex: _currentNavIndex,
                );
              }
            : null,
        onLongPress: isDesktop
            ? null
            : () {
                TrackContextMenu.show(
                  context: context,
                  track: track,
                  playlists: _savedPlaylists,
                  albums: _savedAlbums,
                  artists: _followedArtists,
                  currentLibraryView: _currentLibraryView,
                  currentNavIndex: _currentNavIndex,
                );
              },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () async {
              final player = context.read<AudioPlayerProvider>();

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
                            errorWidget: (context, url, error) =>
                                Icon(Icons.music_note, color: Colors.grey[700]),
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
                                  LibraryItemContextMenu.show(
                                    context: context,
                                    item: primaryArtist,
                                    position: details.globalPosition,
                                    playlists: _savedPlaylists,
                                    albums: _savedAlbums,
                                    artists: _followedArtists,
                                    currentLibraryView: _currentLibraryView,
                                    currentNavIndex: _currentNavIndex,
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
                            LibraryItemContextMenu.show(
                              context: context,
                              item: album,
                              position: details.globalPosition,
                              playlists: _savedPlaylists,
                              albums: _savedAlbums,
                              artists: _followedArtists,
                              currentLibraryView: _currentLibraryView,
                              currentNavIndex: _currentNavIndex,
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
                    LibraryItemContextMenu.show(
                      context: context,
                      item: artist,
                      position: details.globalPosition,
                      playlists: _savedPlaylists,
                      albums: _savedAlbums,
                      artists: _followedArtists,
                      currentLibraryView: _currentLibraryView,
                      currentNavIndex: _currentNavIndex,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    LibraryItemContextMenu.show(
                      context: context,
                      item: artist,
                      playlists: _savedPlaylists,
                      albums: _savedAlbums,
                      artists: _followedArtists,
                      currentLibraryView: _currentLibraryView,
                      currentNavIndex: _currentNavIndex,
                    );
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

  Widget _buildSection(String title, List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) => cards[index],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final GenericSimpleArtist artist;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _ArtistCard({
    required this.artist,
    required this.onTap,
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
          child: GestureDetector(
            onSecondaryTapDown: isDesktop
                ? (details) {
                    LibraryItemContextMenu.show(
                      context: context,
                      item: artist,
                      position: details.globalPosition,
                      playlists: playlists,
                      albums: albums,
                      artists: artists,
                      currentLibraryView: currentLibraryView,
                      currentNavIndex: currentNavIndex,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    LibraryItemContextMenu.show(
                      context: context,
                      item: artist,
                      playlists: playlists,
                      albums: albums,
                      artists: artists,
                      currentLibraryView: currentLibraryView,
                      currentNavIndex: currentNavIndex,
                    );
                  },
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                onTap();
              },
              borderRadius: BorderRadius.circular(8),
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
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                      Icons.person,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                              )
                            : const Center(
                                child: Icon(
                                  Icons.person,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: 9),
                    Text(
                      artist.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Artist',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
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
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _AlbumCard({
    required this.album,
    required this.onTap,
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
          child: GestureDetector(
            onSecondaryTapDown: isDesktop
                ? (details) {
                    LibraryItemContextMenu.show(
                      context: context,
                      item: album,
                      position: details.globalPosition,
                      playlists: playlists,
                      albums: albums,
                      artists: artists,
                      currentLibraryView: currentLibraryView,
                      currentNavIndex: currentNavIndex,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    LibraryItemContextMenu.show(
                      context: context,
                      item: album,
                      playlists: playlists,
                      albums: albums,
                      artists: artists,
                      currentLibraryView: currentLibraryView,
                      currentNavIndex: currentNavIndex,
                    );
                  },
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                onTap();
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(11.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: double.infinity,
                        height: 148,
                        color: Colors.grey[900],
                        child: album.thumbnailUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: album.thumbnailUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    Container(color: Colors.grey[800]),
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                      Icons.album,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                              )
                            : const Center(
                                child: Icon(
                                  Icons.album,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: 9),
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
                    SizedBox(height: 2),
                    Text(
                      album.artists.map((a) => a.name).join(', '),
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
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
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
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
          child: GestureDetector(
            onSecondaryTapDown: isDesktop
                ? (details) {
                    LibraryItemContextMenu.show(
                      context: context,
                      item: playlist,
                      position: details.globalPosition,
                      playlists: playlists,
                      albums: albums,
                      artists: artists,
                      currentLibraryView: currentLibraryView,
                      currentNavIndex: currentNavIndex,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    LibraryItemContextMenu.show(
                      context: context,
                      item: playlist,
                      playlists: playlists,
                      albums: albums,
                      artists: artists,
                      currentLibraryView: currentLibraryView,
                      currentNavIndex: currentNavIndex,
                    );
                  },
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                onTap();
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(11.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: double.infinity,
                        height: 148,
                        color: Colors.grey[900],
                        child: _buildPlaylistArtForCard(playlist),
                      ),
                    ),
                    SizedBox(height: 9),
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
                    SizedBox(height: 2),
                    Text(
                      '${playlist.total ?? 0} tracks',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
