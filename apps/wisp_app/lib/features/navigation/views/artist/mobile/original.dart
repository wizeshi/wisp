// Copyright © 2026 wizeshi

part of '../view.dart';

extension _MobileOriginalStyle on _ArtistDetailViewState {
  Widget _buildMobileArtistContentOriginal({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
    // Currently redirects to Spotify style.
    // Planned for future Material 3 Expressive / Liquid Glass implementation.
    return _buildMobileArtistContentSpotify(
      imageUrl: imageUrl,
      name: name,
      followers: followers,
    );
  }
}
