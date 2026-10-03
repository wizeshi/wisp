// Copyright © 2026 wizeshi

part of '../../user_detail_view.dart';

/// Original user profile style — redirects to Spotify for now until M3E / Liquid Glass are officially supported.
Widget _buildOriginalUserContent(_UserDetailViewState view, GenericUser user) {
  return _buildSpotifyUserContent(view, user);
}
