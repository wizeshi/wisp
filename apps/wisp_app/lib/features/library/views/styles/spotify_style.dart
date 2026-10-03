// Copyright © 2026 wizeshi

part of '../library_view.dart';

extension _SpotifyLibraryStyle on LibraryTabViewState {
  Widget _buildSpotifyLibraryContent(double padding) {
    switch (_selectedTab) {
      case LibraryView.playlists:
        return _buildPlaylistsContent(padding);
      case LibraryView.all:
        return _buildPlaylistsContent(padding);
      case LibraryView.albums:
        return _buildAlbumsContent(padding);
      case LibraryView.artists:
        return _buildArtistsContent(padding);
    }
  }
}
