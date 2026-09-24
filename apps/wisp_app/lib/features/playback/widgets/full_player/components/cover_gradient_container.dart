// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';

Color tintedDominantColor(Color color, {double blend = 0.4}) {
  final hsl = HSLColor.fromColor(color);
  final overlay = hsl
      .withLightness(0.22)
      .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
      .toColor();
  return Color.lerp(color, overlay, blend) ?? color;
}

class CoverGradientContainer extends StatelessWidget {
  final Widget child;
  final Widget? background;

  const CoverGradientContainer({
    super.key,
    required this.child,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final dominantColor = tintedDominantColor(
      Theme.of(context).colorScheme.primary,
    );

    final gradientLayer = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            dominantColor.withValues(alpha: 0.9),
            dominantColor.withValues(alpha: 0.7),
            dominantColor.withValues(alpha: 0.5),
            dominantColor.withValues(alpha: 0.4),
            Colors.black.withValues(alpha: 0.2),
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        gradientLayer,
        if (background != null) Positioned.fill(child: background!),
        child,
      ],
    );
  }
}

