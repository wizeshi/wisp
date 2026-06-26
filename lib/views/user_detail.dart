library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metadata_models.dart';
import '../providers/metadata/spotify_internal.dart';
import '../services/metadata_cache.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/theme/cover_art_palette_provider.dart';
import '../services/app_navigation.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/wisp_audio_handler.dart';
import '../widgets/entity_context_menus.dart';
import '../widgets/provider_disabled_state.dart';

enum UserPageStyle { spotify, apple }

class UserDetailView extends StatefulWidget {
  final String userId;
  final GenericUser? initialUser;
  final UserPageStyle style;

  const UserDetailView({
    super.key,
    required this.userId,
    this.initialUser,
    this.style = UserPageStyle.spotify,
  });

  @override
  State<UserDetailView> createState() => _UserDetailViewState();
}

class _UserDetailViewState extends State<UserDetailView> {
  bool _isLoading = true;
  String? _currentUserId;
  GenericUser? _user;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _loadUser();
  }

  Future<void> _loadUser() async {
    if (!context.read<PreferencesProvider>().metadataSpotifyEnabled) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    final spotify = context.read<SpotifyInternalProvider>();
    if (spotify.userId == null || spotify.userId!.isEmpty) {
      try {
        await spotify.fetchUserProfile();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final profile = await spotify.getUserProfile(
        widget.userId,
        policy: MetadataFetchPolicy.refreshAlways,
      );

      List<GenericSimpleUser> followers = const [];
      List<GenericSimpleUser> following = const [];
      String? partialError;

      try {
        followers = await spotify.getUserFollowers(
          widget.userId,
          policy: MetadataFetchPolicy.refreshAlways,
        );
      } catch (e) {
        partialError = 'Followers could not be loaded: $e';
      }

      try {
        following = await spotify.getUserFollowing(
          widget.userId,
          policy: MetadataFetchPolicy.refreshAlways,
        );
      } catch (e) {
        partialError = partialError == null
            ? 'Following could not be loaded: $e'
            : '$partialError\nFollowing could not be loaded: $e';
      }

      if (!mounted) return;
      setState(() {
        _currentUserId = spotify.userId;
        _errorMessage = partialError;
        _user = GenericUser(
          id: profile.id,
          source: profile.source,
          displayName: profile.displayName,
          avatarUrl: profile.avatarUrl,
          followerCount: profile.followerCount,
          followingCount: profile.followingCount,
          recentArtists: profile.recentArtists,
          publicPlaylists: profile.publicPlaylists,
          followers: followers,
          following: following,
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load user: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  bool get _isFollowedByCurrentUser {
    final currentUserId = _currentUserId;
    final user = _user;
    if (currentUserId == null || currentUserId.isEmpty || user == null) {
      return false;
    }
    return user.followers.any((follower) => follower.id == currentUserId);
  }

  String _formatNumber(int? value) {
    final number = value ?? 0;
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  Future<List<Color>> _getActionsRowColor(CoverArtPaletteProvider paletteProvider, String imageUrl) async {
    final palette = await paletteProvider.paletteForImageUrl(imageUrl);
    final fakeColor = HSLColor.fromColor(palette?.primary ?? const Color(0xFF1E1E1E));
    final color = fakeColor.withLightness(
      log(fakeColor.lightness + 1) / log(3)
    ).toColor();
    final colorHSL = HSLColor.fromColor(color);
    final trueColor = colorHSL.withLightness(
      colorHSL.lightness * 0.5
    ).toColor();

    return [color, trueColor];
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();
    if (!preferences.metadataSpotifyEnabled) {
      return const ProviderDisabledState();
    }

    final user = _user;
    final imageUrl = user?.avatarUrl ?? '';
    final title = user?.displayName ?? 'User';

    Widget body = () {
      final content = _isLoading && user == null
        ? const Center(child: CircularProgressIndicator())
        : _buildContent(user);

      if (_isDesktop) {
        return content;
      }

      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        extendBodyBehindAppBar: true,
        body: content,
      );
    }();

    if (_errorMessage != null && user == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.black, title: Text(title)),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    return body;
  }

  Widget _buildContent(GenericUser? user) {
    final effectiveUser = user;
    if (effectiveUser == null) {
      return const SizedBox.shrink();
    }

    if (widget.style == UserPageStyle.apple) {
      return _buildAppleContent(effectiveUser);
    }
    return _buildSpotifyContent(effectiveUser);
  }

  Widget _buildSpotifyContent(GenericUser user) {
    final children = <Widget>[];

    if (user.publicPlaylists.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(
        _buildHorizontalSection(
          title: 'Public Playlists',
          children: user.publicPlaylists
              .map(_buildPlaylistCard)
              .toList(growable: false),
        ),
      );
    }

    if (user.recentArtists.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(
        _buildHorizontalSection(
          title: 'Recently Played Artists',
          children: user.recentArtists
              .map(_buildArtistCard)
              .toList(growable: false),
        ),
      );
    }

    if (user.followers.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(
        _buildHorizontalSection(
          title: 'Followers',
          children: user.followers.map(_buildUserCard).toList(growable: false),
        ),
      );
    }

    if (user.following.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(
        _buildHorizontalSection(
          title: 'Following',
          children: user.following.map(_buildUserCard).toList(growable: false),
        ),
      );
    }
    
    return ListView(
      shrinkWrap: true,
      children: [
        _buildHeroCard(user, useAppleChrome: false),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: children
          )
        )
      ]
    );
  }

  Widget _buildAppleContent(GenericUser user) {
    final children = <Widget>[];
    children.add(_buildHeroCard(user, useAppleChrome: true));

    if (user.publicPlaylists.isNotEmpty) {
      children.add(const SizedBox(height: 18));
      children.add(
        _buildHorizontalSection(
          title: 'Public Playlists',
          useAppleTitleStyle: true,
          children: user.publicPlaylists
              .map(_buildPlaylistCard)
              .toList(growable: false),
        ),
      );
    }

    if (user.recentArtists.isNotEmpty) {
      children.add(const SizedBox(height: 18));
      children.add(
        _buildHorizontalSection(
          title: 'Recently Played Artists',
          useAppleTitleStyle: true,
          children: user.recentArtists
              .map(_buildArtistCard)
              .toList(growable: false),
        ),
      );
    }

    if (user.followers.isNotEmpty) {
      children.add(const SizedBox(height: 18));
      children.add(
        _buildHorizontalSection(
          title: 'Followers',
          useAppleTitleStyle: true,
          children: user.followers.map(_buildUserCard).toList(growable: false),
        ),
      );
    }

    if (user.following.isNotEmpty) {
      children.add(const SizedBox(height: 18));
      children.add(
        _buildHorizontalSection(
          title: 'Following',
          useAppleTitleStyle: true,
          children: user.following.map(_buildUserCard).toList(growable: false),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(24), children: children);
  }

  Widget _buildHeroCard(GenericUser user, {required bool useAppleChrome}) {
    final followerLabel = '${_formatNumber(user.followerCount)} followers';
    final followingLabel = '${_formatNumber(user.followingCount)} following';
    
    if (!_isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildHeaderImage(user.avatarUrl),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROFILE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: useAppleChrome ? 28 : 30,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$followerLabel • $followingLabel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: _buildFollowButton()),
          ],
        ),
      );
    }

    final paletteProvider = context.watch<CoverArtPaletteProvider>();
    return FutureBuilder<List<Color>>(
      future: _getActionsRowColor(paletteProvider, user.avatarUrl ?? ''),
      builder: (context, snapshot) {
        final headerColor = snapshot.data?[0] ?? Color(0xFF1E1E1E);
        final actionsRowColor = snapshot.data?[1] ?? const Color(0xFF1E1E1E);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: headerColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildAvatar(user.avatarUrl, size: 180),
                      const SizedBox(width: 16),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: useAppleChrome ? 36 : 38,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$followerLabel • $followingLabel',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 1],
                  colors: [actionsRowColor, Colors.transparent],
                ),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IntrinsicWidth(
                  child: _buildFollowButton(),
                ),
              ),
            )
          ]
        );
      },
    );
  }

  Widget _buildFollowButton() {
    final isFollowing = _isFollowedByCurrentUser;
    final label = isFollowing ? 'Following' : 'Follow';
    final icon = widget.style == UserPageStyle.apple
        ? (isFollowing ? CupertinoIcons.person_fill : CupertinoIcons.person_add)
        : (isFollowing ? Icons.person : Icons.person_add_alt_1);

    return OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  Widget _buildHorizontalSection({
    required String title,
    required List<Widget> children,
    bool useAppleTitleStyle = false,
  }) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return _HorizontalScrollableSection(
      title: title,
      useAppleTitleStyle: useAppleTitleStyle,
      children: children,
    );
  }

  Widget _buildPlaylistCard(GenericSimplePlaylist playlist) {
    final player = context.watch<WispAudioHandler>();
    final isActive =
        player.playbackContextType == 'playlist' &&
        player.playbackContextID == playlist.id;
    final isPlaying = player.isPlaying;

    return _buildCard(
      width: 180,
      height: 236,
      imageUrl: playlist.thumbnailUrl ?? '',
      title: playlist.title,
      subtitle: _playlistSubtitle(playlist),
      onTap: playlist.owner == null
          ? null
          : () => AppNavigation.instance.openUser(
              context,
              userId: playlist.owner!.id,
              initialUser: GenericUser(
                id: playlist.owner!.id,
                source: playlist.owner!.source,
                displayName: playlist.owner!.displayName,
                avatarUrl: playlist.owner!.avatarUrl,
                followerCount: playlist.owner!.followerCount,
                followingCount: null,
                recentArtists: const [],
                publicPlaylists: const [],
                followers: const [],
                following: const [],
              ),
              style: widget.style,
            ),
      onPlay: () => _playPlaylist(playlist),
      onSecondaryTapDown: (details) => EntityContextMenus.showPlaylistMenu(
        context,
        playlist: GenericPlaylist(
          id: playlist.id,
          source: playlist.source,
          title: playlist.title,
          thumbnailUrl: playlist.thumbnailUrl ?? '',
          author:
              playlist.owner ??
              GenericSimpleUser(
                id: '',
                source: playlist.source,
                displayName: '',
              ),
          songs: null,
          durationSecs: 0,
        ),
        globalPosition: details.globalPosition,
      ),
      isActive: isActive,
      isPlaying: isPlaying,
    );
  }

  Widget _buildArtistCard(GenericSimpleArtist artist) {
    final player = context.watch<WispAudioHandler>();
    final isActive =
        player.playbackContextType == 'artist' &&
        player.playbackContextID == artist.id;
    final isPlaying = player.isPlaying;

    return _buildCard(
      width: 180,
      height: 236,
      imageUrl: artist.thumbnailUrl,
      title: artist.name,
      subtitle: 'Artist',
      onTap: () => AppNavigation.instance.openArtist(
        context,
        artistId: artist.id,
        fallbackName: artist.name,
      ),
      onPlay: () => _playArtist(artist),
      onSecondaryTapDown: (details) => EntityContextMenus.showArtistMenu(
        context,
        artist: artist,
        globalPosition: details.globalPosition,
      ),
      isActive: isActive,
      isPlaying: isPlaying,
    );
  }

  Widget _buildUserCard(GenericSimpleUser user) {
    final uri = user.profileUrl ?? '';
    final isArtist = uri.startsWith('spotify:artist:');
    final subtitle = isArtist
        ? 'Artist'
        : user.isFollowed == true
        ? 'Follows you'
        : '${_formatNumber(user.followerCount)} followers';

    return _buildCard(
      width: 180,
      height: 236,
      imageUrl: user.avatarUrl ?? '',
      title: user.displayName,
      subtitle: subtitle,
      onTap: isArtist
          ? () => AppNavigation.instance.openArtist(
              context,
              artistId: user.id,
              fallbackName: user.displayName,
            )
          : () => AppNavigation.instance.openUser(
              context,
              userId: user.id,
              initialUser: GenericUser(
                id: user.id,
                source: user.source,
                displayName: user.displayName,
                avatarUrl: user.avatarUrl,
                followerCount: user.followerCount,
                followingCount: null,
                recentArtists: const [],
                publicPlaylists: const [],
                followers: const [],
                following: const [],
              ),
              style: widget.style,
            ),
      onPlay: null,
      onSecondaryTapDown: isArtist
          ? (details) => EntityContextMenus.showArtistMenu(
              context,
              artist: GenericSimpleArtist(
                id: user.id,
                source: user.source,
                name: user.displayName,
                thumbnailUrl: user.avatarUrl ?? '',
              ),
              globalPosition: details.globalPosition,
            )
          : null,
      isActive: false,
      isPlaying: false,
    );
  }

  Widget _buildCard({
    required double width,
    required double height,
    required String imageUrl,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required VoidCallback? onPlay,
    GestureTapDownCallback? onSecondaryTapDown,
    VoidCallback? onLongPress,
    bool isActive = false,
    bool isPlaying = false,
  }) {
    return SizedBox(
      width: width,
      child: ClipRect(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: _HoverCard(
            width: width,
            height: height,
            onTap: onTap,
            onSecondaryTapDown: onSecondaryTapDown,
            onLongPress: onLongPress,
            builder: (context, hovering) => Padding(
              padding: const EdgeInsets.fromLTRB(11.0, 11.0, 11.0, 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: width - 20,
                      height: width - 20,
                      child: _HoverCardArtwork(
                        imageUrl: imageUrl,
                        showPlayButton: hovering && onPlay != null,
                        onPlayPressed: onPlay,
                        isActive: isActive,
                        isPlaying: isPlaying,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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
          ),
        ),
      ),
    );
  }

  String _playlistSubtitle(GenericSimplePlaylist playlist) {
    final followerCount = playlist.followerCount ?? 0;
    if (followerCount > 0) {
      return '$followerCount ${followerCount == 1 ? 'Follower' : 'Followers'}';
    }
    final ownerName = playlist.owner?.displayName;
    return ownerName == null ? 'By Spotify' : 'By $ownerName';
  }

  Future<void> _playPlaylist(GenericSimplePlaylist playlist) async {
    try {
      final spotify = context.read<SpotifyInternalProvider>();
      final info = await spotify.getPlaylistInfo(playlist.id);
      final items = info.songs ?? [];
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

      await context.read<PlaybackCoordinator>().setQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'playlist',
        contextName: info.title,
        contextID: info.id,
        contextSource: info.source,
      );
    } catch (_) {}
  }

  Future<void> _playArtist(GenericSimpleArtist artist) async {
    try {
      final spotify = context.read<SpotifyInternalProvider>();
      final info = await spotify.getArtistInfo(artist.id);
      if (info.topSongs.isEmpty) return;

      await context.read<PlaybackCoordinator>().setQueue(
        info.topSongs,
        startIndex: 0,
        play: true,
        contextType: 'artist',
        contextName: info.name,
        contextID: info.id,
        contextSource: info.source,
      );
    } catch (_) {}
  }

  Widget _buildAvatar(String? imageUrl, {required double size}) {
    final placeholder = Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: Icon(
        CupertinoIcons.person_crop_circle,
        color: Colors.white.withValues(alpha: 0.55),
        size: size * 0.42,
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl == null || imageUrl.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => placeholder,
              ),
      ),
    );
  }

  Widget _buildHeaderImage(String? imageUrl) {
    final placeholder = Container(
      color: Colors.grey[900],
      child: Icon(
        CupertinoIcons.person_crop_circle,
        color: Colors.grey[600],
        size: 64,
      ),
    );

    if (imageUrl == null || imageUrl.isEmpty) {
      return placeholder;
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[800],
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, url, error) => placeholder,
    );
  }
}

class _HorizontalScrollableSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool useAppleTitleStyle;

  const _HorizontalScrollableSection({
    required this.title,
    required this.children,
    required this.useAppleTitleStyle,
  });

  @override
  State<_HorizontalScrollableSection> createState() =>
      _HorizontalScrollableSectionState();
}

class _HorizontalScrollableSectionState
    extends State<_HorizontalScrollableSection> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollState);
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollState() {
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
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final showArrows = isDesktop && _isHovered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            widget.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.useAppleTitleStyle ? 20 : 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 236,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onEnter: isDesktop
                ? (_) => setState(() => _isHovered = true)
                : null,
            onExit: isDesktop
                ? (_) => setState(() => _isHovered = false)
                : null,
            child: Stack(
              children: [
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.children.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) => widget.children[index],
                ),
                if (_canScrollRight)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF121212).withValues(alpha: 0.78),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showArrows && _canScrollLeft)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                          ),
                          onPressed: () => _scrollBy(-240),
                          splashRadius: 18,
                        ),
                      ),
                    ),
                  ),
                if (showArrows && _canScrollRight)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                          ),
                          onPressed: () => _scrollBy(240),
                          splashRadius: 18,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HoverCard extends StatefulWidget {
  final double width;
  final double height;
  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;

  const _HoverCard({
    required this.width,
    required this.height,
    required this.builder,
    required this.onTap,
    this.onSecondaryTapDown,
    this.onLongPress,
  });

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) {
        if (_isDesktop) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: widget.onTap == null ? null : SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(20),
          onSecondaryTapDown: widget.onSecondaryTapDown,
          onLongPress: widget.onLongPress,
          onTap: widget.onTap,
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: widget.builder(context, _hovering),
          ),
        ),
      ),
    );
  }

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

class _HoverCardArtwork extends StatelessWidget {
  final String imageUrl;
  final bool showPlayButton;
  final VoidCallback? onPlayPressed;
  final bool isActive;
  final bool isPlaying;

  const _HoverCardArtwork({
    required this.imageUrl,
    required this.showPlayButton,
    required this.onPlayPressed,
    this.isActive = false,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: Icon(
        CupertinoIcons.person_crop_circle,
        color: Colors.white.withValues(alpha: 0.55),
        size: 42,
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: imageUrl.isEmpty
              ? placeholder
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => placeholder,
                ),
        ),
        Builder(
          builder: (context) {
            if (onPlayPressed == null) return const SizedBox.shrink();
            final isDesktop =
                Platform.isLinux || Platform.isMacOS || Platform.isWindows;
            final icon = isActive && isPlaying ? Icons.pause : Icons.play_arrow;
            final visible = isDesktop && (showPlayButton || isActive);
            return Positioned(
              right: 10,
              bottom: 10,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    shape: const CircleBorder(),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 22,
                      icon: Icon(
                        icon,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      onPressed: () {
                        final player = context.read<WispAudioHandler>();
                        final coordinator = context.read<PlaybackCoordinator>();
                        if (isActive) {
                          if (player.isPlaying) {
                            unawaited(coordinator.pause());
                          } else if (!player.isLoading && !player.isBuffering) {
                            unawaited(coordinator.play());
                          }
                          return;
                        }
                        onPlayPressed!();
                      },
                      splashRadius: 22,
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
}
