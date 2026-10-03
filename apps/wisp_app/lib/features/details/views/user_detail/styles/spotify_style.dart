// Copyright © 2026 wizeshi

part of '../../user_detail_view.dart';

Widget _buildSpotifyUserContent(_UserDetailViewState view, GenericUser user) {
  final children = <Widget>[];

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
        itemBuilder: (context, following) => UserCard(
          user: following,
          style: view.widget.style,
        ),
      ),
    );
  }

  return WispListView(
    key: PageStorageKey('user_spotify_${view.widget.userId}'),
    controller: view._scrollController,
    padding: EdgeInsets.fromLTRB(
      0,
      0,
      0,
      mobileBottomBarPadding(view.context, extra: 0),
    ),
    children: [
      view._buildHeroCard(user, useAppleChrome: false),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ],
  );
}
