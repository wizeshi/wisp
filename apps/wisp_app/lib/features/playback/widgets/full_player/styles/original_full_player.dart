// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'spotify_full_player.dart';

/// Original variant — currently reuses the Spotify layout.
class OriginalFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;

  const OriginalFullScreenPlayer({
    required this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SpotifyFullScreenPlayer(scrollController: scrollController);
  }
}