// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import '../home_view_data.dart';
import 'spotify.dart';

class DesktopOriginalHome extends StatelessWidget {
  final HomeViewData data;
  final HomeViewActions actions;

  const DesktopOriginalHome({
    super.key,
    required this.data,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    // Redirects to DesktopSpotifyHome (planned for future Liquid Glass / M3E desktop styling)
    return DesktopSpotifyHome(data: data, actions: actions);
  }
}

