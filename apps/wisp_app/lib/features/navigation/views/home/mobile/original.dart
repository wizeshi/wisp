// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import '../home_view_data.dart';
import 'spotify.dart';

class MobileOriginalHome extends StatelessWidget {
  final HomeViewData data;
  final HomeViewActions actions;

  const MobileOriginalHome({
    super.key,
    required this.data,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    // Currently redirects to MobileSpotifyHome (planned for future Liquid Glass / M3E styling)
    return MobileSpotifyHome(data: data, actions: actions);
  }
}

