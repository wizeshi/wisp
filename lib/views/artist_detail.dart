/// Artist detail view
library;

import 'dart:ui';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';

import '../models/metadata_models.dart';
import '../providers/connect/connect_session_provider.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../providers/library/library_state.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/metadata_cache.dart';
import '../widgets/hover_underline.dart';
import '../widgets/navigation.dart';
import '../widgets/like_button.dart';
import '../widgets/adaptive_context_menu.dart';
import '../widgets/entity_context_menus.dart';
import '../services/app_navigation.dart';
import '../widgets/provider_disabled_state.dart';
import 'list_detail.dart';

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
  final PageController _appleTopSongsPageController = PageController(
    viewportFraction: 0.9,
  );

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  @override
  void dispose() {
    _appleTopSongsPageController.dispose();
    super.dispose();
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
    final connect = context.read<ConnectSessionProvider>();
    final tracks = _artist?.topSongs ?? [];
    if (tracks.isEmpty) return;
    await connect.requestSetQueue(
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
        : _buildArtistContent(
            imageUrl,
            name,
            followers,
            isDesktop,
            preferences.style,
          );

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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
    String style,
  ) {
    final isMobile = !isDesktop;

    if (isMobile) {
      if (style == 'Apple Music') {
        return _buildMobileArtistContentApple(
          imageUrl: imageUrl,
          name: name,
          followers: followers,
        );
      }

      return _buildMobileArtistContentDefault(
        imageUrl: imageUrl,
        name: name,
        followers: followers,
      );
    }

    if (style == 'Apple Music') {
      return _buildDesktopArtistContentApple(
        imageUrl: imageUrl,
        name: name,
        followers: followers,
      );
    }

    return _buildDesktopArtistContentSpotify(
      imageUrl: imageUrl,
      name: name,
      followers: followers,
    );
  }

  Widget _buildMobileArtistContentDefault({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
    const padding = 20.0;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(padding),
                  child: _buildMobileHeader(
                    name,
                    imageUrl,
                    followers,
                    _artist?.monthlyListeners,
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyActionBarDelegate(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: padding / 2,
                      vertical: padding / 2,
                    ),
                    color: const Color(0xFF121212),
                    child: _buildMobileActionsRow(useAppleIcons: false),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildTopTracksSection(),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      child: SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: padding),
                      child: _buildAlbumsGrid(false),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileArtistContentApple({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildMobileAppleHero(
            imageUrl: imageUrl,
            name: name,
            followers: followers,
            monthlyListeners: _artist?.monthlyListeners,
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyActionBarDelegate(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF121212),
              child: _buildMobileActionsRow(useAppleIcons: true),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 26),
            child: Column(
              children: [
                _buildMobileAppleTopSongsGrid(),
                const SizedBox(height: 20),
                _buildMobileAppleAlbumsRow(),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildMobileAboutSection(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileAppleHero({
    required String imageUrl,
    required String name,
    required int followers,
    required int? monthlyListeners,
  }) {
    final subtitle = (monthlyListeners != null && monthlyListeners > 0)
        ? '${_formatNumber(monthlyListeners)} monthly listeners'
        : '${_formatNumber(followers)} followers';

    return SizedBox(
      height: 430,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[900],
              ),
            )
          else
            Container(color: Colors.grey[900]),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black,
                ],
                stops: const [0, 0.72, 1],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      height: 1.04,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[300], fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopArtistContentSpotify({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
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
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.9),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildSpotifyHeader(
                      name,
                      imageUrl,
                      followers,
                      _artist?.monthlyListeners,
                    ),
                    const SizedBox(height: 16),
                    _buildActionsRow(useAppleIcons: false),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildTopTracksSection(),
              const SizedBox(height: 24),
              _buildSpotifyAlbumsGridDesktop(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpotifyHeader(
    String name,
    String imageUrl,
    int followers,
    int? monthlyListeners,
  ) {
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
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              (monthlyListeners != null && monthlyListeners > 0)
                  ? Text(
                      '${_formatNumber(monthlyListeners)} monthly listeners',
                      style: TextStyle(color: Colors.grey[300], fontSize: 14),
                    )
                  : Text(
                      '${_formatNumber(followers)} followers',
                      style: TextStyle(color: Colors.grey[300], fontSize: 14),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopArtistContentApple({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
    final hasTopSongs = (_artist?.topSongs ?? []).isNotEmpty;
    final hasAlbums = (_artist?.albums ?? []).isNotEmpty;

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
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.9),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildDesktopHero(
                    name,
                    imageUrl,
                    followers,
                    _artist?.monthlyListeners,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasTopSongs) ...[
                        _buildDesktopTopSongsSection(),
                        const SizedBox(height: 36),
                      ],
                      if (hasAlbums) ...[
                        _buildAlbumsGrid(true),
                        const SizedBox(height: 36),
                      ],
                      _buildAboutSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHero(
    String name,
    String imageUrl,
    int followers,
    int? monthlyListeners,
  ) {
    final subtitle = (monthlyListeners != null && monthlyListeners > 0)
        ? '${_formatNumber(monthlyListeners)} monthly listeners'
        : '${_formatNumber(followers)} followers';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 360,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    Container(color: Colors.grey[900]),
              )
            else
              Container(color: Colors.grey[900]),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                  stops: const [0, 0.62, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[300], fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  _buildActionsRow(useAppleIcons: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTopSongsSection() {
    final tracks = _artist?.topSongs ?? [];
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    const tracksPerColumn = 3;
    final displayTracks = tracks.take(9).toList();
    final columns = <List<GenericSong>>[];
    for (var i = 0; i < displayTracks.length; i += tracksPerColumn) {
      columns.add(
        displayTracks.skip(i).take(tracksPerColumn).toList(growable: false),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Top Songs'),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var columnIndex = 0; columnIndex < columns.length; columnIndex++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: columnIndex == columns.length - 1 ? 0 : 18,
                  ),
                  child: Column(
                    children: [
                      for (
                        var trackIndex = 0;
                        trackIndex < columns[columnIndex].length;
                        trackIndex++
                      )
                        _buildDesktopTopSongRow(
                          track: columns[columnIndex][trackIndex],
                          index: (columnIndex * tracksPerColumn) + trackIndex,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopTopSongRow({required GenericSong track, required int index}) {
    final player = context.watch<global_audio_player.WispAudioHandler>();
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrentTrack = player.currentTrack?.id == track.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredTrackId = track.id),
        onExit: (_) => setState(() => _hoveredTrackId = null),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            onTap: () => _playTopTracks(index),
            onSecondaryTapDown: (details) {
              EntityContextMenus.showTrackMenu(
                context,
                track: track,
                globalPosition: details.globalPosition,
              );
            },
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: track.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: track.thumbnailUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey[850],
                              child: Icon(
                                CupertinoIcons.music_note,
                                color: Colors.grey[700],
                                size: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrentTrack
                                ? colorScheme.primary
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${track.album?.title ?? ''}${track.album?.releaseDate != null ? ' · ${track.album!.releaseDate.year}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _hoveredTrackId == track.id ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: IgnorePointer(
                      ignoring: _hoveredTrackId != track.id,
                      child: LikeButton(
                        track: track,
                        iconSize: 15,
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Builder(
                      builder: (buttonContext) => IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        iconSize: 18,
                        splashRadius: 16,
                        onPressed: () {
                          final overlay = Overlay.of(
                            context,
                            rootOverlay: true,
                          ).context.findRenderObject() as RenderBox;
                          final button =
                              buttonContext.findRenderObject() as RenderBox?;
                          Rect? anchorRect;
                          if (button != null) {
                            anchorRect = Rect.fromPoints(
                              button.localToGlobal(
                                Offset.zero,
                                ancestor: overlay,
                              ),
                              button.localToGlobal(
                                button.size.bottomRight(Offset.zero),
                                ancestor: overlay,
                              ),
                            );
                          }
                          EntityContextMenus.showTrackMenu(
                            context,
                            track: track,
                            anchorRect: anchorRect,
                          );
                        },
                        icon: Icon(
                          CupertinoIcons.ellipsis,
                          color: Colors.grey[500],
                        ),
                      ),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 31,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }

  Widget _buildMobileHeader(
    String name,
    String imageUrl,
    int followers,
    int? monthlyListeners,
  ) {
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
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              (monthlyListeners != null && monthlyListeners > 0)
                  ? Text(
                      '${_formatNumber(monthlyListeners)} monthly listeners',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    )
                  : Text(
                      '${_formatNumber(followers)} followers',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileActionsRow({required bool useAppleIcons}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        return SizedBox(
          height: 56,
          child: Row(
            children: [
              Consumer<LibraryState>(
                builder: (context, library, child) {
                  final isFollowed = library.isArtistFollowed(widget.artistId);
                  return OutlinedButton(
                    onPressed: () => _toggleFollowArtist(isFollowed),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[700]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: Text(isFollowed ? 'Following' : 'Follow'),
                  );
                },
              ),
              const SizedBox(width: 4),
              Builder(
                builder: (buttonContext) {
                  return IconButton(
                    icon: Icon(
                      useAppleIcons
                          ? CupertinoIcons.ellipsis_circle
                          : Icons.more_horiz,
                    ),
                    color: Colors.white,
                    onPressed: () => _showArtistOptions(buttonContext),
                  );
                },
              ),
              const Spacer(),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isCurrentArtistPlaying(player) && player.isPlaying
                        ? (useAppleIcons
                            ? CupertinoIcons.pause_fill
                            : Icons.pause)
                        : (useAppleIcons
                            ? CupertinoIcons.play_fill
                            : Icons.play_arrow),
                    size: 30,
                  ),
                  color: colorScheme.onPrimary,
                  onPressed: () {
                    if (_isLoading) return;
                    if (_isCurrentArtistPlaying(player)) {
                      player.togglePlayPause();
                    } else {
                      _playTopTracks(0);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileAboutSection() {
    final description = _artist?.description?.trim() ?? '';
    final displayDescription = description.isEmpty
        ? 'No description available for this artist yet.'
        : description;
    final listeners = _artist?.monthlyListeners;
    final followers = _artist?.followers ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayDescription,
            style: TextStyle(
              color: Colors.grey[200],
              fontSize: 16,
              height: 1.38,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              if (listeners != null && listeners > 0)
                _buildAboutStat('MONTHLY LISTENERS', _formatNumber(listeners)),
              _buildAboutStat('FOLLOWERS', _formatNumber(followers)),
              _buildAboutStat('ALBUMS', '${_artist?.albums.length ?? 0}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileAppleTopSongsGrid() {
    final tracks = _artist?.topSongs ?? [];
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayTracks = tracks.take(9).toList(growable: false);
    const rowsPerColumn = 3;
    final columns = <List<GenericSong>>[];
    for (var i = 0; i < displayTracks.length; i += rowsPerColumn) {
      columns.add(
        displayTracks.skip(i).take(rowsPerColumn).toList(growable: false),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Top Songs',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: PageView.builder(
            controller: _appleTopSongsPageController,
            itemCount: columns.length,
            padEnds: true,
            itemBuilder: (context, columnIndex) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    for (
                      var rowIndex = 0;
                      rowIndex < columns[columnIndex].length;
                      rowIndex++
                    )
                      Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              rowIndex == columns[columnIndex].length - 1
                              ? 0
                              : 6,
                        ),
                        child: _buildMobileAppleTopSongRow(
                          track: columns[columnIndex][rowIndex],
                          index: (columnIndex * rowsPerColumn) + rowIndex,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileAppleTopSongRow({
    required GenericSong track,
    required int index,
  }) {
    final player = context.watch<global_audio_player.WispAudioHandler>();
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrentTrack = player.currentTrack?.id == track.id;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _playTopTracks(index),
      onLongPress: () => EntityContextMenus.showTrackMenu(context, track: track),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 36,
                height: 36,
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
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (track.explicit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'E',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrentTrack
                                ? colorScheme.primary
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artists.map((artist) => artist.name).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () => EntityContextMenus.showTrackMenu(context, track: track),
              icon: Icon(CupertinoIcons.ellipsis, color: Colors.grey[400], size: 18),
              visualDensity: VisualDensity.compact,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAppleAlbumsRow() {
    final albums = _artist?.albums ?? [];
    if (albums.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Albums',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final album = albums[index];
              return GestureDetector(
                onTap: () {
                  AppNavigation.instance.openSharedList(
                    context,
                    id: album.id,
                    type: SharedListType.album,
                    initialTitle: album.title,
                    initialThumbnailUrl: album.thumbnailUrl,
                  );
                },
                onLongPress: () {
                  EntityContextMenus.showAlbumMenu(
                    context,
                    album: GenericAlbum(
                      id: album.id,
                      source: SongSource.spotifyInternal,
                      title: album.title,
                      thumbnailUrl: album.thumbnailUrl,
                      artists: [
                        GenericSimpleArtist(
                          id: widget.artistId,
                          source: SongSource.spotifyInternal,
                          name: _artist?.name ?? widget.initialArtist?.name ?? 'Artist',
                          thumbnailUrl:
                              _artist?.thumbnailUrl ?? widget.initialArtist?.thumbnailUrl ?? '',
                        ),
                      ],
                      label: '',
                      releaseDate: album.releaseDate,
                      explicit: false,
                      durationSecs: 0,
                    ),
                  );
                },
                child: SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 150,
                          height: 150,
                          color: Colors.grey[900],
                          child: album.thumbnailUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: album.thumbnailUrl,
                                  fit: BoxFit.cover,
                                )
                              : Icon(Icons.album, color: Colors.grey[700]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${album.releaseDate.year}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionsRow({required bool useAppleIcons}) {
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
                            ? (useAppleIcons
                                ? CupertinoIcons.pause_fill
                                : Icons.pause)
                            : (useAppleIcons
                                ? CupertinoIcons.play_fill
                                : Icons.play_arrow),
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: player.toggleShuffle,
                  icon: Icon(
                    useAppleIcons ? CupertinoIcons.shuffle : Icons.shuffle,
                    color: player.shuffleEnabled
                        ? colorScheme.primary
                        : Colors.grey[300],
                  ),
                ),
                IconButton(
                  onPressed: player.toggleRepeat,
                  icon: Icon(
                    player.repeatMode == global_audio_player.RepeatMode.one
                        ? (useAppleIcons
                            ? CupertinoIcons.repeat_1
                            : Icons.repeat_one)
                        : (useAppleIcons
                            ? CupertinoIcons.repeat
                            : Icons.repeat),
                    color:
                        player.repeatMode == global_audio_player.RepeatMode.off
                        ? Colors.grey[300]
                        : colorScheme.primary,
                  ),
                ),
                Builder(
                  builder: (buttonContext) {
                    return IconButton(
                      onPressed: () => _showArtistOptions(buttonContext),
                      icon: Icon(
                        useAppleIcons ? CupertinoIcons.ellipsis : Icons.more_horiz,
                        color: Colors.grey,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpotifyAlbumsGridDesktop() {
    final albums = _artist?.albums ?? [];

    if (albums.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Albums',
          style: TextStyle(
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
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.885,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return GestureDetector(
                onSecondaryTapDown: (details) {
                  EntityContextMenus.showAlbumMenu(
                    context,
                    album: GenericAlbum(
                      id: album.id,
                      source: SongSource.spotifyInternal,
                      title: album.title,
                      thumbnailUrl: album.thumbnailUrl,
                      artists: [
                        GenericSimpleArtist(
                          id: widget.artistId,
                          source: SongSource.spotifyInternal,
                          name:
                              _artist?.name ?? widget.initialArtist?.name ?? 'Artist',
                          thumbnailUrl:
                              _artist?.thumbnailUrl ?? widget.initialArtist?.thumbnailUrl ?? '',
                        ),
                      ],
                      label: '',
                      releaseDate: album.releaseDate,
                      explicit: false,
                      durationSecs: 0,
                    ),
                    globalPosition: details.globalPosition,
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      AppNavigation.instance.openSharedList(
                        context,
                        id: album.id,
                        type: SharedListType.album,
                        initialTitle: album.title,
                        initialThumbnailUrl: album.thumbnailUrl,
                      );
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
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
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${album.releaseDate.year}',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
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

  Future<void> _showArtistOptions([BuildContext? anchorContext]) async {
    final libraryState = context.read<LibraryState>();
    final isFollowed = libraryState.isArtistFollowed(widget.artistId);

    Rect? anchorRect;
    if (anchorContext != null) {
      final overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox;
      final button = anchorContext.findRenderObject() as RenderBox?;
      if (button != null) {
        anchorRect = Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
        );
      }
    }

    await showAdaptiveContextMenu(
      context: context,
      anchorRect: anchorRect,
      actions: [
        ContextMenuAction(
          id: 'follow-toggle',
          label: isFollowed ? 'Unfollow' : 'Follow',
          icon: isFollowed ? Icons.person_remove : Icons.person_add,
          onSelected: (_) => _toggleFollowArtist(isFollowed),
        ),
        ContextMenuAction(
          id: 'download-metadata',
          label: 'Download Metadata',
          icon: Icons.download_outlined,
          onSelected: (_) async {
            await _loadArtist();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Artist metadata refreshed')),
            );
          },
        ),
        ContextMenuAction(
          id: 'share',
          label: 'Share',
          icon: Icons.share,
          onSelected: (_) async {
            final source = _artist?.source ?? widget.initialArtist?.source ?? SongSource.spotifyInternal;
            await EntityContextMenus.copySpotifyShareUrl(
              context,
              source: source,
              type: 'artist',
              id: widget.artistId,
            );
          },
        ),
      ],
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
        if (!mounted) return;
        context.read<LibraryState>().removeArtist(artistId);
      } else {
        await spotifyInternal.followArtist(artistId);
        if (!mounted) return;
        if (simpleArtist != null) {
          context.read<LibraryState>().addArtist(simpleArtist);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFollowed ? 'Artist unfollowed' : 'Artist followed'),
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

    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Top Songs',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
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
                              : Colors.black.withValues(alpha: 0.15),
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
                                            AppNavigation.instance
                                                .openSharedList(
                                                  context,
                                                  id: album.id,
                                                  type: SharedListType.album,
                                                  initialTitle: album.title,
                                                  initialThumbnailUrl:
                                                      album.thumbnailUrl,
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

    if (albums.isEmpty) {
      return const SizedBox.shrink();
    }

    final columns = isDesktop ? 6 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        (isDesktop ? _buildSectionTitle('Albums') : Text(
          'Albums',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        )),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: isDesktop ? 16 : 16,
              mainAxisSpacing: isDesktop ? 20 : 16,
              childAspectRatio: isDesktop ? 0.76 : 0.885,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return GestureDetector(
                onSecondaryTapDown: isDesktop
                    ? (details) {
                        EntityContextMenus.showAlbumMenu(
                          context,
                          album: GenericAlbum(
                            id: album.id,
                            source: SongSource.spotifyInternal,
                            title: album.title,
                            thumbnailUrl: album.thumbnailUrl,
                            artists: [
                              GenericSimpleArtist(
                                id: widget.artistId,
                                source: SongSource.spotifyInternal,
                                name: _artist?.name ?? widget.initialArtist?.name ?? 'Artist',
                                thumbnailUrl: _artist?.thumbnailUrl ?? widget.initialArtist?.thumbnailUrl ?? '',
                              ),
                            ],
                            label: '',
                            releaseDate: album.releaseDate,
                            explicit: false,
                            durationSecs: 0,
                          ),
                          globalPosition: details.globalPosition,
                        );
                      }
                    : null,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      AppNavigation.instance.openSharedList(
                        context,
                        id: album.id,
                        type: SharedListType.album,
                        initialTitle: album.title,
                        initialThumbnailUrl: album.thumbnailUrl,
                      );
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
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
                            Text(
                              album.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${album.releaseDate.year}',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
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

  Widget _buildAboutSection() {
    final description = _artist?.description?.trim() ?? '';
    final displayDescription = description.isEmpty
        ? 'No description available for this artist yet.'
        : description;

    final artistName = _artist?.name ?? widget.initialArtist?.name ?? 'Artist';
    final listeners = _artist?.monthlyListeners;
    final followers = _artist?.followers ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About $artistName',
            style: const TextStyle(
              fontSize: 31,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  displayDescription,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 15,
                    height: 1.45,
                  ),
                  softWrap: true,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (listeners != null && listeners > 0)
                      _buildAboutStat(
                        'MONTHLY LISTENERS',
                        _formatNumber(listeners),
                      ),
                    _buildAboutStat('FOLLOWERS', _formatNumber(followers)),
                    _buildAboutStat('ALBUMS', '${_artist?.albums.length ?? 0}'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAboutStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
