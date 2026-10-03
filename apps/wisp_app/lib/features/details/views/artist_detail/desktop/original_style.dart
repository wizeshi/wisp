// Copyright © 2026 wizeshi

part of '../../artist_detail_view.dart';

extension _DesktopOriginalStyle on _ArtistDetailViewState {
  Widget _buildDesktopArtistContentOriginal({
    required String imageUrl,
    required String name,
    required int followers,
    required String description,
    required Color headerColor,
    required Color actionsRowColor,
  }) {
    // Currently redirects to Spotify style.
    // Planned for future Material 3 Expressive / Liquid Glass implementation.
    return _buildDesktopArtistContentSpotify(
      imageUrl: imageUrl,
      name: name,
      followers: followers,
      description: description,
      headerColor: headerColor,
      actionsRowColor: actionsRowColor,
    );
  }
}
