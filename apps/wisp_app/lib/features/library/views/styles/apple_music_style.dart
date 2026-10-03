// Copyright © 2026 wizeshi

part of '../library_view.dart';

extension _AppleMusicLibraryStyle on LibraryTabViewState {
  Widget _buildAppleMusicLibraryContent(double padding) {
    // Currently redirects to Spotify library style as Apple Music library layout is not yet differentiated.
    return _buildSpotifyLibraryContent(padding);
  }
}
