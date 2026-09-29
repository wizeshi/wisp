// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/details/views/user_detail_view.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'generic_card.dart';

String userSubtitle(GenericSimpleUser user) {
  final uri = user.profileUrl ?? '';
  final isArtist = uri.startsWith('spotify:artist:');
  if (isArtist) {
    return 'Artist';
  }
  if (user.isFollowed == true) {
    return 'Follows you';
  }
  final count = user.followerCount;
  if (count != null && count > 0) {
    final formatted = _formatCount(count);
    return '$formatted ${count == 1 ? 'follower' : 'followers'}';
  }
  return 'User';
}

String _formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toString();
}

class UserCard extends StatelessWidget {
  final GenericSimpleUser user;
  final double? width;
  final String? subtitle;
  final UserPageStyle style;

  const UserCard({
    super.key,
    required this.user,
    this.width,
    this.subtitle,
    this.style = UserPageStyle.spotify,
  });

  factory UserCard.fromUser({
    Key? key,
    required GenericUser user,
    double? width,
    String? subtitle,
    UserPageStyle style = UserPageStyle.spotify,
  }) {
    return UserCard(
      key: key,
      user: GenericSimpleUser(
        id: user.id,
        source: user.source,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        followerCount: user.followerCount,
      ),
      width: width,
      subtitle: subtitle,
      style: style,
    );
  }

  bool get _isArtist {
    final uri = user.profileUrl ?? '';
    return uri.startsWith('spotify:artist:');
  }

  void _onTap(BuildContext context) {
    if (_isArtist) {
      AppNavigation.instance.openArtist(
        context,
        artistId: user.id,
        fallbackName: user.displayName,
      );
    } else {
      AppNavigation.instance.openUser(
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
        style: style,
      );
    }
  }

  void _showContextMenu(BuildContext context, {Offset? position}) {
    if (_isArtist) {
      EntityContextMenus.showArtistMenu(
        context,
        artist: GenericSimpleArtist(
          id: user.id,
          source: user.source,
          name: user.displayName,
          thumbnailUrl: user.avatarUrl ?? '',
        ),
        globalPosition: position,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GenericCard(
      title: user.displayName,
      subtitle: subtitle ?? userSubtitle(user),
      artwork: ArtworkThumbnail(
        source: ArtworkSource.fromUrl(user.avatarUrl),
        size: ArtworkSize.large,
        shape: ArtworkShape.circle,
        fallbackIcon: Icons.person,
        semanticLabel: 'Photo of ${user.displayName}',
      ),
      onTap: () => _onTap(context),
      onSecondaryTapDown: _isArtist
          ? (details) => _showContextMenu(context, position: details.globalPosition)
          : null,
      onLongPress: _isArtist ? () => _showContextMenu(context) : null,
      width: width,
    );
  }
}

