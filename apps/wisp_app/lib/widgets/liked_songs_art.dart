/// Liked Songs thumbnail widget
library;

import 'package:flutter/material.dart';

class LikedSongsArt extends StatelessWidget {
  final double? size;

  const LikedSongsArt({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final child = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF7B2FF7),
            Color(0xFFF6F0FF),
          ],
        ),
      ),
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconSize = (constraints.maxWidth < constraints.maxHeight
          ? constraints.maxWidth
          : constraints.maxHeight) *
          0.5;
            return Icon(
              Icons.favorite,
              color: Colors.white,
              size: iconSize,
            );
          },
        )
        ),
      );

    if (size == null) return child;
    return SizedBox(width: size, height: size, child: child);
  }
}
