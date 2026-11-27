// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';

abstract final class PlayerHeroTags {
  static const String artwork = 'wisp-player-artwork-hero';
}

/// Shared Hero wrapper for artwork transitions between the mobile player bar
/// and the full-screen player.
///
/// Pass [enabled] as `false` for desktop embedded player bars, hidden canvas
/// covers, or swipe previews so duplicate Hero tags are never registered.
class PlayerArtworkHero extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool enabled;
  final String tag;

  const PlayerArtworkHero({
    super.key,
    required this.child,
    required this.borderRadius,
    this.enabled = true,
    this.tag = PlayerHeroTags.artwork,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return Hero(
      tag: tag,
      createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
      flightShuttleBuilder: (
        BuildContext flightContext,
        Animation<double> animation,
        HeroFlightDirection flightDirection,
        BuildContext fromHeroContext,
        BuildContext toHeroContext,
      ) {
        final Hero toHero = toHeroContext.widget as Hero;
        final Hero fromHero = fromHeroContext.widget as Hero;
        final Widget flightChild =
            flightDirection == HeroFlightDirection.push ? toHero.child : fromHero.child;

        return Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: flightChild,
          ),
        );
      },
      child: child,
    );
  }
}
