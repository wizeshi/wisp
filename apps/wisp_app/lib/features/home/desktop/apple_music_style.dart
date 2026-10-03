// Copyright © 2026 wizeshi

part of '../home_view.dart';

extension _DesktopAppleMusicStyle on HomePageState {
  Widget _buildDesktopHomeContentApple() {
    // Currently redirects to Spotify desktop layout as Apple Music desktop layout is not yet differentiated.
    return _buildDesktopHomeContentSpotify();
  }
}
