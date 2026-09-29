// Copyright © 2026 wizeshi

import 'dart:io' show Platform;
import 'package:flutter/material.dart';

/// Calculates the bottom padding required on mobile so that scrollable content
/// can scroll underneath the floating player bar and bottom navigation bar,
/// but still be fully accessible when scrolled to the end.
double mobileBottomBarPadding(BuildContext context, {double extra = 20.0}) {
  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (!isMobile) return extra;

  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
  if (keyboardHeight > 0) return extra;

  final systemBottom = MediaQuery.paddingOf(context).bottom;
  // Player bar (56) + margin (8) + Nav bar (56) + system bottom safe area
  return 56.0 + 8.0 + 56.0 + systemBottom + extra;
}

/// A sliver that provides bottom padding on mobile to clear the floating
/// player bar and bottom navigation bar overlays.
class MobileBottomPaddingSliver extends StatelessWidget {
  final double extra;

  const MobileBottomPaddingSliver({super.key, this.extra = 20.0});

  @override
  Widget build(BuildContext context) {
    final padding = mobileBottomBarPadding(context, extra: extra);
    return SliverToBoxAdapter(
      child: SizedBox(height: padding),
    );
  }
}
