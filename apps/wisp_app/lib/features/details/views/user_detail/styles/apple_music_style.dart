// Copyright © 2026 wizeshi

part of '../../user_detail_view.dart';

Widget _buildAppleMusicUserContent(_UserDetailViewState view, GenericUser user) {
  final children = <Widget>[];
  children.add(view._buildHeroCard(user, useAppleChrome: true));

  if (user.publicPlaylists.isNotEmpty) {
    children.add(
      CardRail<GenericSimplePlaylist>(
        title: 'Public Playlists',
        items: user.publicPlaylists,
        itemWidth: 180,
        itemBuilder: (context, playlist) => PlaylistCard(
          playlist: playlist.toPlaylist(),
          subtitle: view._playlistSubtitle(playlist),
        ),
      ),
    );
  }

  if (user.recentArtists.isNotEmpty) {
    children.add(
      CardRail<GenericSimpleArtist>(
        title: 'Recently Played Artists',
        items: user.recentArtists,
        itemWidth: 180,
        itemBuilder: (context, artist) => ArtistCard(
          artist: artist,
        ),
      ),
    );
  }

  if (user.followers.isNotEmpty) {
    children.add(
      CardRail<GenericSimpleUser>(
        title: 'Followers',
        items: user.followers,
        itemWidth: 180,
        itemBuilder: (context, follower) => UserCard(
          user: follower,
          style: view.widget.style,
        ),
      ),
    );
  }

  if (user.following.isNotEmpty) {
    children.add(
      CardRail<GenericSimpleUser>(
        title: 'Following',
        items: user.following,
        itemWidth: 180,
        itemBuilder: (context, follower) => UserCard(
          user: follower,
          style: view.widget.style,
        ),
      ),
    );
  }

  return WispListView(
    key: PageStorageKey('user_apple_${view.widget.userId}'),
    controller: view._scrollController,
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      mobileBottomBarPadding(view.context, extra: 24),
    ),
    children: children,
  );
}
