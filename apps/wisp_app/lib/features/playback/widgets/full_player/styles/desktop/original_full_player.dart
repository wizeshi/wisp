// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'spotify_full_player.dart';

/// Original variant — currently reuses the Spotify layout.
class OriginalDesktopFullScreenPlayer extends StatelessWidget {
  const OriginalDesktopFullScreenPlayer({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SpotifyDesktopFullScreenPlayer();
  }
}