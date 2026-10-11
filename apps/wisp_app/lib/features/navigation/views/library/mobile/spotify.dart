// Copyright © 2026 wizeshi

part of '../view.dart';

extension _MobileSpotifyLibraryStyle on LibraryTabViewState {
  Widget _buildMobileSpotifyLibraryContent(double padding) {
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
