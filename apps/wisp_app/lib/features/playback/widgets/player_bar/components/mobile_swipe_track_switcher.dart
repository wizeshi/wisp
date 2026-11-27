// Copyright © 2026 wizeshi

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/metadata_models.dart';

/// Snapshot of the current horizontal swipe gesture across mobile player bars.
class MobileSwipeState {
  final double dragOffset;
  final double dragProgress;
  final bool isSwipingLeft;
  final bool crossedThreshold;
  final GenericSong? previewTrack;

  const MobileSwipeState({
    required this.dragOffset,
    required this.dragProgress,
    required this.isSwipingLeft,
    required this.crossedThreshold,
    required this.previewTrack,
  });

  static const empty = MobileSwipeState(
    dragOffset: 0,
    dragProgress: 0,
    isSwipingLeft: false,
    crossedThreshold: false,
    previewTrack: null,
  );
}

/// Wraps a mobile player bar with responsive horizontal swipe-to-skip physics,
/// boundary resistance, haptic threshold feedback, and smooth spring-back.
class MobileSwipeablePlayerBar extends StatefulWidget {
  static const double maxDragExtent = 150.0;
  static const double skipThreshold = 96.0;
  static const double velocityThreshold = 650.0;

  final GenericSong? currentTrack;
  final GenericSong? previousTrack;
  final GenericSong? nextTrack;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final Widget Function(BuildContext context, MobileSwipeState swipe) builder;

  const MobileSwipeablePlayerBar({
    super.key,
    required this.currentTrack,
    required this.previousTrack,
    required this.nextTrack,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.builder,
  });

  @override
  State<MobileSwipeablePlayerBar> createState() =>
      _MobileSwipeablePlayerBarState();
}

class _MobileSwipeablePlayerBarState extends State<MobileSwipeablePlayerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapController;
  double _dragOffset = 0.0;
  double _snapStartOffset = 0.0;
  bool _thresholdHapticFired = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _snapController.removeListener(_onSnapTick);
    _snapController.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    final t = Curves.easeOutCubic.transform(_snapController.value);
    setState(() {
      _dragOffset = _snapStartOffset * (1.0 - t);
    });
  }

  void _animateSnapBack() {
    _thresholdHapticFired = false;
    if (_dragOffset == 0.0) return;
    _snapStartOffset = _dragOffset;
    _snapController.forward(from: 0.0);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_snapController.isAnimating) {
      _snapController.stop();
    }
    _thresholdHapticFired = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    if (delta == 0.0) return;

    final nextProposed = _dragOffset + delta;
    final movingLeft = nextProposed < 0;
    final hasTarget =
        movingLeft ? widget.nextTrack != null : widget.previousTrack != null;

    double updated;
    if (!hasTarget) {
      updated = (_dragOffset + delta * 0.25).clamp(-28.0, 28.0);
    } else {
      final multiplier =
          _dragOffset.abs() > MobileSwipeablePlayerBar.skipThreshold
              ? 0.55
              : 1.0;
      updated = (_dragOffset + delta * multiplier).clamp(
        -MobileSwipeablePlayerBar.maxDragExtent,
        MobileSwipeablePlayerBar.maxDragExtent,
      );
    }

    if (hasTarget &&
        updated.abs() >= MobileSwipeablePlayerBar.skipThreshold &&
        !_thresholdHapticFired) {
      _thresholdHapticFired = true;
      HapticFeedback.selectionClick();
    } else if (updated.abs() < MobileSwipeablePlayerBar.skipThreshold * 0.85) {
      _thresholdHapticFired = false;
    }

    setState(() {
      _dragOffset = updated;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    final triggerNext =
        (_dragOffset <= -MobileSwipeablePlayerBar.skipThreshold ||
            (velocity < -MobileSwipeablePlayerBar.velocityThreshold &&
                _dragOffset <= -24.0)) &&
        widget.nextTrack != null;
    final triggerPrevious =
        (_dragOffset >= MobileSwipeablePlayerBar.skipThreshold ||
            (velocity > MobileSwipeablePlayerBar.velocityThreshold &&
                _dragOffset >= 24.0)) &&
        widget.previousTrack != null;

    if (triggerNext) {
      if (!_thresholdHapticFired) {
        HapticFeedback.lightImpact();
      }
      widget.onSkipNext();
    } else if (triggerPrevious) {
      if (!_thresholdHapticFired) {
        HapticFeedback.lightImpact();
      }
      widget.onSkipPrevious();
    }

    _animateSnapBack();
  }

  void _onHorizontalDragCancel() {
    _animateSnapBack();
  }

  @override
  Widget build(BuildContext context) {
    final isSwipingLeft = _dragOffset < 0;
    final previewTrack = _dragOffset == 0
        ? null
        : (isSwipingLeft ? widget.nextTrack : widget.previousTrack);
    final dragProgress = (_dragOffset.abs() /
            MobileSwipeablePlayerBar.skipThreshold)
        .clamp(0.0, 1.0);
    final crossedThreshold =
        previewTrack != null &&
        _dragOffset.abs() >= MobileSwipeablePlayerBar.skipThreshold;

    final swipeState = MobileSwipeState(
      dragOffset: _dragOffset,
      dragProgress: dragProgress,
      isSwipingLeft: isSwipingLeft,
      crossedThreshold: crossedThreshold,
      previewTrack: previewTrack,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: widget.builder(context, swipeState),
    );
  }
}

/// Renders the sliding current track info and incoming preview track info
/// with directional skip affordances.
class MobileSwipeTrackInfoStack extends StatelessWidget {
  final MobileSwipeState swipe;
  final Widget currentChild;
  final Widget? previewChild;
  final Color accentColor;
  final Color secondaryColor;

  const MobileSwipeTrackInfoStack({
    super.key,
    required this.swipe,
    required this.currentChild,
    required this.previewChild,
    required this.accentColor,
    required this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasPreview = previewChild != null && swipe.dragProgress > 0.02;
    final currentOpacity = hasPreview
        ? (1.0 - swipe.dragProgress * 1.15).clamp(0.0, 1.0)
        : (1.0 - swipe.dragProgress * 0.2).clamp(0.75, 1.0);
    final iconColor = swipe.crossedThreshold ? accentColor : secondaryColor;

    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Transform.translate(
            offset: Offset(swipe.dragOffset * 0.65, 0),
            child: Opacity(opacity: currentOpacity, child: currentChild),
          ),
          if (hasPreview)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: Curves.easeOut.transform(swipe.dragProgress).clamp(
                    0.0,
                    1.0,
                  ),
                  child: Transform.translate(
                    offset: Offset(
                      swipe.isSwipingLeft
                          ? (1.0 - swipe.dragProgress) * 44
                          : -(1.0 - swipe.dragProgress) * 44,
                      0,
                    ),
                    child: Row(
                      children: [
                        if (!swipe.isSwipingLeft) ...[
                          Icon(
                            Icons.skip_previous_rounded,
                            size: 18,
                            color: iconColor,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(child: previewChild!),
                        if (swipe.isSwipingLeft) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.skip_next_rounded,
                            size: 18,
                            color: iconColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cross-fades non-Hero preview artwork over the persistent active Hero artwork
/// while swiping toward an adjacent track.
class MobileSwipeArtworkOverlay extends StatelessWidget {
  final MobileSwipeState swipe;
  final double size;
  final BorderRadius borderRadius;
  final Widget child;

  const MobileSwipeArtworkOverlay({
    super.key,
    required this.swipe,
    required this.size,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final previewTrack = swipe.previewTrack;
    final showPreview = previewTrack != null && swipe.dragProgress > 0.05;
    final scale = showPreview ? (1.0 - swipe.dragProgress * 0.05) : 1.0;
    final colors = context.colors;

    return Transform.scale(
      scale: scale,
      child: Stack(
        children: [
          child,
          if (showPreview)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: swipe.dragProgress.clamp(0.0, 0.96),
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: Container(
                      width: size,
                      height: size,
                      color: colors.artworkPlaceholder,
                      child: previewTrack.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: previewTrack.thumbnailUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 138,
                              memCacheHeight: 138,
                              placeholder: (_, _) =>
                                  Container(color: colors.artworkPlaceholder),
                              errorWidget: (_, _, _) => Icon(
                                Icons.music_note,
                                color: colors.textMuted,
                              ),
                            )
                          : Icon(Icons.music_note, color: colors.textMuted),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
