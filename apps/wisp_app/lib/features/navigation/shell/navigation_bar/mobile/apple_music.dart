// Copyright © 2026 wizeshi

import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';

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
    final colors = context.colors;
    final isDark = colors.isDark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final barWidth = (screenWidth - 44).clamp(260.0, 360.0);
    const double barHeight = 62.0;
    const double bottomMargin = 12.0;
    final double totalHeight = barHeight + bottomMargin + bottomInset;

    final selectedShadows = isDark
        ? [
            Shadow(
              color: Colors.white.withValues(alpha: 0.85),
              blurRadius: 14,
            ),
          ]
        : null;

    final items = [
      LiquidGlassTabBarItem(
        label: 'Home',
        iconBuilder: (context, i) => Icon(
          i.selected ? Icons.home : Icons.home_outlined,
          size: i.size,
          color: i.color,
          shadows: i.selected ? selectedShadows : null,
        ),
      ),
      LiquidGlassTabBarItem(
        label: 'Search',
        iconBuilder: (context, i) => Icon(
          i.selected ? Icons.search : Icons.search_outlined,
          size: i.size,
          color: i.color,
          shadows: i.selected ? selectedShadows : null,
        ),
      ),
      LiquidGlassTabBarItem(
        label: 'Library',
        iconBuilder: (context, i) => Icon(
          i.selected ? Icons.library_music : Icons.library_music_outlined,
          size: i.size,
          color: i.color,
          shadows: i.selected ? selectedShadows : null,
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
              : Colors.white.withValues(alpha: 0.72),
          blur: 3.5,
          refractionIndex: 1.2,
          refractionWidth: 16.0,
          magnification: 1.02,
          dispersion: 2.5,
          shadow: LiquidGlassShadow(
            blur: 16,
            opacity: isDark ? 0.35 : 0.14,
          ),
        ),
        itemStyle: LiquidGlassTabItemStyle(
          selectedColor: isDark ? Colors.white : colors.textPrimary,
          unselectedColor: isDark
              ? Colors.white.withValues(alpha: 0.65)
              : colors.textSecondary,
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
            color: isDark
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.08),
            blur: 2.0,
            specular: const LiquidGlassLight.specular(
              thickness: 3.5,
              angle: 45,
              intensity: 1.2,
            ),
            glow: LiquidGlassLight.glow(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ),
      ),
    );
  }
}
