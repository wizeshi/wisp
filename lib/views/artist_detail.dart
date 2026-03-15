/// Artist detail view
library;

import 'dart:ui';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';

import '../models/metadata_models.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../providers/library/library_state.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/metadata_cache.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/library_item_context_menu.dart';
import '../widgets/hover_underline.dart';
import '../widgets/navigation.dart';
import '../widgets/like_button.dart';
import '../widgets/provider_disabled_state.dart';
import 'list_detail.dart';
import '../providers/navigation_state.dart';

class ArtistDetailView extends StatefulWidget {
  final String artistId;
  final GenericSimpleArtist? initialArtist;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView initialLibraryView;
  final int initialNavIndex;

  const ArtistDetailView({
    super.key,
    required this.artistId,
    this.initialArtist,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.initialLibraryView,
    required this.initialNavIndex,
  });

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  bool _isLoading = true;
  GenericArtist? _artist;
  String? _hoveredTrackId;
  NavigationState get _navState => context.read<NavigationState>();
  LibraryView get _currentLibraryView => _navState.selectedLibraryView;
  int get _currentNavIndex => _navState.selectedNavIndex;

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    if (!context.read<PreferencesProvider>().metadataSpotifyEnabled) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    final spotify = context.read<SpotifyInternalProvider>();
    setState(() => _isLoading = true);
    try {
      /* final cachedArtist = await spotify.getCachedArtistInfo(widget.artistId);
      if (cachedArtist != null && mounted) {
        setState(() {
          _artist = cachedArtist;
          _isLoading = false;
        });
      } */

      final artist = await spotify.getArtistInfo(
        widget.artistId,
        policy: MetadataFetchPolicy.refreshAlways,
      );
      if (mounted) {
        setState(() => _artist = artist);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load artist: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  String _formatNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  Future<void> _playTopTracks(int index) async {
    final player = context.read<global_audio_player.WispAudioHandler>();
    final tracks = _artist?.topSongs ?? [];
    if (tracks.isEmpty) return;
    await player.setQueue(
      tracks,
      startIndex: index,
      play: true,
      contextType: 'artist',
      contextName: _artist?.name ?? '',
      contextID: _artist?.id ?? '',
      contextSource: _artist?.source ?? SongSource.spotify,
    );
  }

  bool _isCurrentArtistPlaying(global_audio_player.WispAudioHandler player) {
    final contextType = 'artist';
    final contextName = _artist?.name ?? '';
    return player.playbackContextType == contextType &&
        player.playbackContextName == contextName &&
        player.currentTrack != null;
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();
    if (!preferences.metadataSpotifyEnabled) {
      return const ProviderDisabledState();
    }

    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final imageUrl =
        _artist?.thumbnailUrl ?? widget.initialArtist?.thumbnailUrl ?? '';
    final name = _artist?.name ?? widget.initialArtist?.name ?? 'Artist';
    final followers = _artist?.monthlyListeners ?? 0;

    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _buildArtistContent(imageUrl, name, followers, isDesktop);

    if (isDesktop) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: content,
    );
  }

  Widget _buildArtistContent(
    String imageUrl,
    String name,
    int followers,
    bool isDesktop,
  ) {
    final isMobile = !isDesktop;
    final padding = isMobile ? 20.0 : 24.0;

    if (isMobile) {
      // Mobile layout: single scroll area with sticky action bar
      return Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: _buildMobileHeader(name, imageUrl, followers, _artist?.monthlyListeners),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyActionBarDelegate(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: padding / 2,
                        vertical: padding / 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        border: Border(
                          top: BorderSide(color: Colors.white10),
                          bottom: BorderSide(color: Colors.white10),
                        ),
                      ),
                      child: _buildMobileActionsRow(),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.zero,
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 8),
                      _buildTopTracksSection(),
                      const SizedBox(height: 24),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        child: _buildAlbumsGrid(isDesktop),
                      ),
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Opacity(
                opacity: 0.35,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      Container(color: Colors.grey[900]),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.9),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.all(padding),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildHeader(name, imageUrl, followers, _artist?.monthlyListeners),
                    const SizedBox(height: 16),
                    _buildActionsRow(),
                  ],)
              ),
              const SizedBox(height: 24),
              _buildTopTracksSection(),
              const SizedBox(height: 24),
              _buildAlbumsGrid(isDesktop),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileHeader(String name, String imageUrl, int followers, int? monthlyListeners) {
    return Column(
      children: [
        // Avatar - 70% width as per old design
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.7,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.grey[900],
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[800],
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Icon(
                            Icons.person,
                            color: Colors.grey[600],
                            size: 64,
                          ),
                        )
                      : Icon(Icons.person, color: Colors.grey[600], size: 64),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Artist info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              (monthlyListeners != null && monthlyListeners > 0) ? Text(
                '${_formatNumber(monthlyListeners)} monthly listeners',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ) : Text(
                '${_formatNumber(followers)} followers',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileActionsRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          // Left side: Follow + More
          Consumer<LibraryState>(
            builder: (context, library, child) {
              final isFollowed = library.isArtistFollowed(widget.artistId);
              return OutlinedButton(
                onPressed: () => _toggleFollowArtist(isFollowed),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey[700]! ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(isFollowed ? 'Following' : 'Follow'),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            color: Colors.white,
            onPressed: _showArtistOptions,
          ),
          const Spacer(),
          // Right side: Play button
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.play_arrow, size: 32),
              color: colorScheme.onPrimary,
              onPressed: () {
                // Play top songs
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String name, String imageUrl, int followers, int? monthlyListeners) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipOval(
            child: Container(
              width: 140,
              height: 140,
              color: Colors.grey[900],
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover)
                  : Icon(Icons.person, color: Colors.grey[600], size: 48),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ARTIST',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                (monthlyListeners != null && monthlyListeners > 0) ? Text(
                  '${_formatNumber(monthlyListeners)} monthly listeners',
                  style: TextStyle(color: Colors.grey[300], fontSize: 14),
                ) : Text(
                  '${_formatNumber(followers)} followers',
                  style: TextStyle(color: Colors.grey[300], fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      );
  }

  Widget _buildActionsRow() {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          alignment: Alignment.bottomLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FilledButton(
                      onPressed: () {
                        if (!_isLoading) {
                          if (_isCurrentArtistPlaying(player)) {
                            player.togglePlayPause();
                          } else {
                            _playTopTracks(0);
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        enabledMouseCursor: SystemMouseCursors.click,
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Icon(
                        _isCurrentArtistPlaying(player) && player.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        size: 24,
                      )
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: player.toggleShuffle,
                  icon: Icon(
                    Icons.shuffle,
                    color: player.shuffleEnabled
                        ? colorScheme.primary
                        : Colors.grey[300],
                  ),
                ),
                IconButton(
                  onPressed: player.toggleRepeat,
                  icon: Icon(
                    player.repeatMode == global_audio_player.RepeatMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: player.repeatMode == global_audio_player.RepeatMode.off
                        ? Colors.grey[300]
                        : colorScheme.primary,
                  ),
                ),
                IconButton(
                  onPressed: _showArtistOptions,
                  icon: const Icon(Icons.more_horiz, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showArtistOptions() {
    final name = _artist?.name ?? widget.initialArtist?.name ?? 'Artist';
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white),
              title: const Text(
                'Copy artist name',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: name));
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Artist name copied')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Share not implemented yet')),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFollowArtist(bool isFollowed) async {
    final spotifyInternal = context.read<SpotifyInternalProvider>();
    if (!spotifyInternal.isAuthenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Spotify (Internal) is not connected.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final artistId = widget.artistId;
    final artist = _artist;
    final fallback = widget.initialArtist;
    final simpleArtist = artist != null
        ? GenericSimpleArtist(
            id: artist.id,
            source: SongSource.spotifyInternal,
            name: artist.name,
            thumbnailUrl: artist.thumbnailUrl,
          )
        : fallback != null
            ? GenericSimpleArtist(
                id: fallback.id,
                source: SongSource.spotifyInternal,
                name: fallback.name,
                thumbnailUrl: fallback.thumbnailUrl,
              )
            : null;

    try {
      if (isFollowed) {
        await spotifyInternal.unfollowArtist(artistId);
        context.read<LibraryState>().removeArtist(artistId);
      } else {
        await spotifyInternal.followArtist(artistId);
        if (simpleArtist != null) {
          context.read<LibraryState>().addArtist(simpleArtist);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFollowed ? 'Artist unfollowed' : 'Artist followed',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update follow: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildTopTracksSection() {
    final tracks = _artist?.topSongs ?? [];
    final player = context.watch<global_audio_player.WispAudioHandler>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Top Tracks',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (tracks.isEmpty)
          Text('No tracks available', style: TextStyle(color: Colors.grey[400]))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              final isEven = index % 2 == 0;
              final isCurrentTrack = player.currentTrack?.id == track.id;
              final album = track.album;
              final isHovering = _hoveredTrackId == track.id;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: isDesktop
                    ? (details) {
                        TrackContextMenu.show(
                          context: context,
                          track: track,
                          position: details.globalPosition,
                          playlists: widget.playlists,
                          albums: widget.albums,
                          artists: widget.artists,
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
                          playlists: widget.playlists,
                          albums: widget.albums,
                          artists: widget.artists,
                          currentLibraryView: _currentLibraryView,
                          currentNavIndex: _currentNavIndex,
                        );
                      },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    if (!isDesktop) return;
                    setState(() => _hoveredTrackId = track.id);
                  },
                  onExit: (_) {
                    if (!isDesktop) return;
                    setState(() => _hoveredTrackId = null);
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () => _playTopTracks(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isEven
                              ? Colors.transparent
                              : Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            if (isDesktop) ...[
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(color: Colors.grey[400]),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 40,
                                height: 40,
                                color: Colors.grey[900],
                                child: track.thumbnailUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: track.thumbnailUrl,
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(
                                        Icons.music_note,
                                        color: Colors.grey[700],
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  (isDesktop &&
                                          album != null &&
                                          album.id.isNotEmpty)
                                      ? HoverUnderline(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              PageRouteBuilder(
                                                transitionDuration: Duration.zero,
                                                reverseTransitionDuration:
                                                    Duration.zero,
                                                pageBuilder:
                                                    (
                                                      context,
                                                      animation,
                                                      secondaryAnimation,
                                                    ) => SharedListDetailView(
                                                      id: album.id,
                                                      type: SharedListType.album,
                                                      initialTitle: album.title,
                                                      initialThumbnailUrl:
                                                          album.thumbnailUrl,
                                                      playlists: widget.playlists,
                                                      albums: widget.albums,
                                                      artists: widget.artists,
                                                      initialLibraryView:
                                                          _currentLibraryView,
                                                      initialNavIndex:
                                                          _currentNavIndex,
                                                    ),
                                              ),
                                            );
                                          },
                                          builder: (isHovering) => Text(
                                            track.title,
                                            style: TextStyle(
                                              color: isCurrentTrack
                                                  ? colorScheme.primary
                                                  : Colors.white,
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
                                            color: isCurrentTrack
                                                ? colorScheme.primary
                                                : Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artists.map((a) => a.name).join(', '),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
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
                              const SizedBox(width: 8),
                            ],
                            SizedBox(
                              width: 80,
                              child: Text(
                                _formatDuration(track.durationSecs),
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(width: isDesktop ? 16 : 12),
                            Icon(
                              Icons.graphic_eq,
                              color: colorScheme.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAlbumsGrid(bool isDesktop) {
    final albums = _artist?.albums ?? [];
    final columns = isDesktop ? 5 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Albums',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (albums.isEmpty)
          Text('No albums available', style: TextStyle(color: Colors.grey[400]))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.885,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return GestureDetector(
                onSecondaryTapDown: isDesktop
                    ? (details) {
                        LibraryItemContextMenu.show(
                          context: context,
                          item: album,
                          position: details.globalPosition,
                          playlists: widget.playlists,
                          albums: widget.albums,
                          artists: widget.artists,
                          currentLibraryView: _currentLibraryView,
                          currentNavIndex: _currentNavIndex,
                        );
                      }
                    : null,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  SharedListDetailView(
                                    id: album.id,
                                    type: SharedListType.album,
                                    initialTitle: album.title,
                                    initialThumbnailUrl: album.thumbnailUrl,
                                    playlists: widget.playlists,
                                    albums: widget.albums,
                                    artists: widget.artists,
                                    initialLibraryView: _currentLibraryView,
                                    initialNavIndex: _currentNavIndex,
                                  ),
                        ),
                      );
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: double.infinity,
                                  color: Colors.grey[900],
                                  child: album.thumbnailUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: album.thumbnailUrl,
                                          fit: BoxFit.cover,
                                        )
                                      : Icon(
                                          Icons.album,
                                          color: Colors.grey[700],
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    album.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${album.releaseDate.year}',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ]
                            )
                          ],
                        ),
                      ),
                    ) 
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _StickyActionBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyActionBarDelegate({required this.child});

  @override
  double get minExtent => 72.0;

  @override
  double get maxExtent => 72.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyActionBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}
