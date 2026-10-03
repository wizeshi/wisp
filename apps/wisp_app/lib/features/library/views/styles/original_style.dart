// Copyright © 2026 wizeshi

part of '../library_view.dart';

extension _OriginalLibraryStyle on LibraryTabViewState {
  Widget _buildOriginalLibraryContent(double padding) {
    // Currently redirects to Spotify library style.
    // Planned for future Material 3 Expressive / Liquid Glass implementation.
    return _buildSpotifyLibraryContent(padding);
  }
}
