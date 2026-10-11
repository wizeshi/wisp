// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import '../home_view_data.dart';
import 'spotify.dart';

class DesktopAppleMusicHome extends StatelessWidget {
  final HomeViewData data;
  final HomeViewActions actions;

  const DesktopAppleMusicHome({
    super.key,
    required this.data,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    // Redirects to DesktopSpotifyHome as Apple Music desktop layout is not yet differentiated
    return DesktopSpotifyHome(data: data, actions: actions);
  }
}

