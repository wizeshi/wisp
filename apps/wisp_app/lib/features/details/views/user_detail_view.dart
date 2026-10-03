// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/cache/metadata_diff.dart';
import 'package:wisp/data/cache/metadata_revalidator.dart';
import 'package:wisp/core/theme/cover_art_palette_provider.dart';
import 'package:wisp/shared/widgets/cards/artist_card.dart';
import 'package:wisp/shared/widgets/cards/playlist_card.dart';
import 'package:wisp/shared/widgets/cards/user_card.dart';
import 'package:wisp/shared/widgets/rails/card_rail.dart';
import 'package:wisp/shared/widgets/display/provider_disabled_state.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/layout/mobile_bottom_padding.dart';

part 'user_detail/styles/spotify_style.dart';
part 'user_detail/styles/apple_music_style.dart';
part 'user_detail/styles/original_style.dart';

class UserDetailView extends StatefulWidget {
  final String userId;
  final GenericUser? initialUser;
  final AppStyle style;

  const UserDetailView({
    super.key,
    required this.userId,
    this.initialUser,
    this.style = AppStyle.Spotify,
  });

  @override
  State<UserDetailView> createState() => _UserDetailViewState();
}

class _UserDetailViewState extends State<UserDetailView> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  final MetadataRevalidatorToken _revalidationToken =
      MetadataRevalidatorToken();
  String? _currentUserId;
  GenericUser? _user;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _loadUser();
  }

  @override
  void dispose() {
    _revalidationToken.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final metadataManager = context.read<MetadataManager>();
    if (!metadataManager.hasEnabledProviders) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    if (metadataManager.userId == null || metadataManager.userId!.isEmpty) {
      try {
        await metadataManager.fetchUserProfile();
      } catch (_) {}
    }

    await MetadataRevalidator.revalidate<GenericUser>(
      token: _revalidationToken,
      loadCache: () => metadataManager.getCachedUserProfile(widget.userId),
      fetchRemote: () async {
        final profile = await metadataManager.getUserProfile(
          widget.userId,
          policy: MetadataFetchPolicy.refreshAlways,
        );

        if (profile == null) throw Exception('User profile not found');

        List<GenericSimpleUser> followers = const [];
        List<GenericSimpleUser> following = const [];
        try {
          followers = await metadataManager.getUserFollowers(
            widget.userId,
            policy: MetadataFetchPolicy.refreshAlways,
          );
        } catch (_) {}
        try {
          following = await metadataManager.getUserFollowing(
            widget.userId,
            policy: MetadataFetchPolicy.refreshAlways,
          );
        } catch (_) {}

        final fullUser = GenericUser(
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
        await metadataManager.cacheUserProfile(fullUser);
        return fullUser;
      },
      hasChanged: (curr, fresh) => MetadataDiff.hasUserChanged(curr, fresh),
      onData: (user, {required fromCache}) {
        if (!mounted) return;
        setState(() {
          _currentUserId = metadataManager.userId;
          _user = user;
          _isLoading = false;
        });
      },
      onRefreshing: (refreshing) {
        if (mounted && _isRefreshing != refreshing) {
          setState(() => _isRefreshing = refreshing);
        }
      },
      onError: (e) {
        if (mounted && _user == null) {
          setState(() {
            _errorMessage = 'Failed to load user: $e';
          });
        }
      },
    );
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

  Future<List<Color>> _getActionsRowColor(
    CoverArtPaletteProvider paletteProvider,
    String imageUrl,
  ) async {
    final palette = await paletteProvider.paletteForImageUrl(imageUrl);
    final fakeColor = HSLColor.fromColor(
      palette?.primary ?? const Color(0xFF1E1E1E),
    );
    final color = fakeColor
        .withLightness(log(fakeColor.lightness + 1) / log(3))
        .toColor();
    final colorHSL = HSLColor.fromColor(color);
    final trueColor = colorHSL
        .withLightness(colorHSL.lightness * 0.5)
        .toColor();

    return [color, trueColor];
  }

  @override
  Widget build(BuildContext context) {
    final metadataManager = context.watch<MetadataManager>();
    if (!metadataManager.hasEnabledProviders) {
      return const ProviderDisabledState(message: 'No metadata provider is enabled.');
    }

    final user = _user;
    final title = user?.displayName ?? 'User';

    Widget body = () {
      Widget content = _isLoading && user == null
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(user);

      final wrappedContent = Stack(
        children: [
          content,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _isRefreshing && user != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

      if (_isDesktop) {
        return wrappedContent;
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
        extendBodyBehindAppBar: false,
        body: wrappedContent,
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

    switch (widget.style) {
      case AppStyle.AppleMusic:
        return _buildAppleMusicUserContent(this, effectiveUser);
      case AppStyle.Original:
        return _buildOriginalUserContent(this, effectiveUser);
      case AppStyle.Spotify:
        return _buildSpotifyUserContent(this, effectiveUser);
    }
  }



  Widget _buildHeroCard(GenericUser user, {required bool useAppleChrome}) {
    final followerLabel = '${_formatNumber(user.followerCount)} followers';
    final followingLabel = '${_formatNumber(user.followingCount)} following';

    if (!_isDesktop) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: useAppleChrome ? 28 : 28,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$followerLabel • $followingLabel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    _buildFollowButton(),
                  ],
                ),
              ),
            ),
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
                child: IntrinsicWidth(child: _buildFollowButton()),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFollowButton() {
    final tokens = WispStyleTokens.fromStyle(widget.style);
    final isFollowing = _isFollowedByCurrentUser;
    final label = isFollowing ? 'Following' : 'Follow';
    final icon = isFollowing ? tokens.personIcon : tokens.personAddIcon;

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

  String _playlistSubtitle(GenericSimplePlaylist playlist) {
    final followerCount = playlist.followerCount ?? 0;
    if (followerCount > 0) {
      return '$followerCount ${followerCount == 1 ? 'Follower' : 'Followers'}';
    }
    final ownerName = playlist.owner?.displayName;
    return ownerName == null ? 'By Spotify' : 'By $ownerName';
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

