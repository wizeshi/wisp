// Copyright © 2026 wizeshi

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

class WispMobileOriginalNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const WispMobileOriginalNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destinations = [
      M3ENavigationBarDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home, color: colorScheme.primary),
        label: 'Home',
      ),
      M3ENavigationBarDestination(
        icon: const Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search, color: colorScheme.primary),
        label: 'Search',
      ),
      M3ENavigationBarDestination(
        icon: const Icon(Icons.library_music_outlined),
        selectedIcon: Icon(Icons.library_music, color: colorScheme.primary),
        label: 'Library',
      ),
    ];
    final safeIndex = selectedIndex.clamp(0, destinations.length - 1);

    return M3ENavigationBar(
      selectedIndex: safeIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations,
      indicatorColor: colorScheme.primary.withValues(alpha: 0.2),
      indicatorStyle: M3ENavBarIndicatorStyle.pill,
      shapeFamily: M3ENavBarShapeFamily.square,
      safeArea: true,
    );
  }
}

