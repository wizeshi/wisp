// Copyright © 2026 wizeshi

import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

class WispMobileAppleMusicNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const WispMobileAppleMusicNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final barWidth = (screenWidth - 44).clamp(260.0, 360.0);
    const double barHeight = 62.0;
    const double bottomMargin = 12.0;
    final double totalHeight = barHeight + bottomMargin + bottomInset;

    final items = [
      LiquidGlassTabBarItem(
        label: 'Home',
        iconBuilder: (context, i) => Icon(
          i.selected ? Icons.home : Icons.home_outlined,
          size: i.size,
          color: i.color,
          shadows: i.selected
              ? [
                  Shadow(
                    color: colorScheme.primary.withValues(alpha: 0.85),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
      ),
      LiquidGlassTabBarItem(
        label: 'Search',
        iconBuilder: (context, i) => Icon(
          i.selected ? Icons.search : Icons.search_outlined,
          size: i.size,
          color: i.color,
          shadows: i.selected
              ? [
                  Shadow(
                    color: colorScheme.primary.withValues(alpha: 0.85),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
      ),
      LiquidGlassTabBarItem(
        label: 'Library',
        iconBuilder: (context, i) => Icon(
          i.selected ? Icons.library_music : Icons.library_music_outlined,
          size: i.size,
          color: i.color,
          shadows: i.selected
              ? [
                  Shadow(
                    color: colorScheme.primary.withValues(alpha: 0.85),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
      ),
    ];
    final safeIndex = selectedIndex.clamp(0, items.length - 1);

    return SizedBox(
      width: screenWidth,
      height: totalHeight,
      child: LiquidGlassTabBar(
        width: barWidth,
        height: barHeight,
        margin: const EdgeInsets.only(bottom: bottomMargin),
        items: items,
        selectedIndex: safeIndex,
        onChanged: onDestinationSelected,
        style: LiquidGlassStyle(
          shape: const LiquidGlassShape(
            cornerStyle: LiquidGlassCornerStyle.continuousRoundedRectangle,
            cornerRadius: 31,
            clipQuality: LiquidGlassClipQuality.exact,
          ),
          specular: const LiquidGlassLight.specular(
            thickness: 4.8,
            angle: 45,
            intensity: 1.3,
          ),
          glow: const LiquidGlassLight.glow(
            thickness: 8.0,
            angle: 135,
            intensity: 0.85,
          ),
          color: isDark
              ? const Color(0x1EFFFFFF)
              : const Color(0x38FFFFFF),
          blur: 3.5,
          refractionIndex: 1.2,
          refractionWidth: 16.0,
          magnification: 1.02,
          dispersion: 2.5,
          shadow: const LiquidGlassShadow(
            blur: 16,
            opacity: 0.35,
          ),
        ),
        itemStyle: LiquidGlassTabItemStyle(
          selectedColor: colorScheme.primary,
          unselectedColor: isDark
              ? Colors.white.withValues(alpha: 0.65)
              : Colors.black.withValues(alpha: 0.6),
          iconSize: 22,
          underGlassIconSize: 26,
          labelFontSize: 10.5,
          underGlassLabelFontSize: 11,
          iconLabelGap: 2,
          selectedFontWeight: FontWeight.w700,
          unselectedFontWeight: FontWeight.w500,
        ),
        pillStyle: LiquidGlassTabPillStyle(
          mode: LiquidGlassPillMode.both,
          animated: true,
          growHeight: 4,
          refractionIndex: 1.25,
          refractionWidth: 14,
          magnification: 1.06,
          animationDuration: const Duration(milliseconds: 300),
          animationCurve: Curves.easeOutCubic,
          rest: LiquidGlassStyle(
            shape: const LiquidGlassShape(
              cornerStyle: LiquidGlassCornerStyle.continuousRoundedRectangle,
              cornerRadius: 24,
            ),
            color: colorScheme.primary.withValues(alpha: 0.22),
            blur: 2.0,
            specular: const LiquidGlassLight.specular(
              thickness: 3.5,
              angle: 45,
              intensity: 1.2,
            ),
            glow: LiquidGlassLight.glow(
              color: colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
