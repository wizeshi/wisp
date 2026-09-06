import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// Whether the current platform supports mouse hover.
///
/// Hover affordances (play buttons that fade in, cursor changes) only make
/// sense on desktop — there's no hover state on a touch screen, so mobile
/// falls back to whatever [HoverPlayOverlay.showOnMobile] / the surrounding
/// tap target provides instead.
bool get isDesktopPlatform =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// Tracks hover state for a region of the UI and makes it available to
/// descendants (e.g. a [HoverPlayOverlay] nested a few levels below it)
/// via [HoverRegion.of].
///
/// This is the generic building block behind "hovering anywhere on a card
/// reveals the play button on its artwork, not just hovering the artwork
/// itself." It has no opinion about playback, cards, or artwork — it's
/// just a hover + tap wrapper, reusable anywhere that pattern is useful.
///
/// Hover/cursor behavior is a no-op on non-desktop platforms; taps still
/// work everywhere.
class HoverRegion extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;
  final BorderRadius? borderRadius;

  const HoverRegion({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.borderRadius,
  });

  /// Returns whether the nearest enclosing [HoverRegion] is currently
  /// hovered, or `null` if there isn't one. Widgets that care about this
  /// (like [HoverPlayOverlay]) should treat `null` the same as `false`.
  static bool? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_HoverRegionScope>()
        ?.isHovering;
  }

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _isHovering = false;

  void _setHovering(bool value) {
    if (isDesktopPlatform && _isHovering != value) {
      setState(() => _isHovering = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isDesktopPlatform ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: InkWell(
        mouseCursor: isDesktopPlatform ? SystemMouseCursors.click : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        borderRadius: widget.borderRadius,
        child: _HoverRegionScope(
          isHovering: _isHovering,
          child: widget.child,
        ),
      ),
    );
  }
}

class _HoverRegionScope extends InheritedWidget {
  final bool isHovering;

  const _HoverRegionScope({
    required this.isHovering,
    required super.child,
  });

  @override
  bool updateShouldNotify(_HoverRegionScope oldWidget) =>
      isHovering != oldWidget.isHovering;
}

/// A play/pause button that fades in over [child] (typically an
/// [ArtworkThumbnail]) on hover.
///
/// Deliberately knows nothing about `WispAudioHandler`, `PlaybackCoordinator`,
/// or any specific playback stack — it only takes [isPlaying] and
/// [onPressed]. The caller (e.g. a `TrackRow`, which already resolved
/// "is *this* track the one playing" via its own narrow provider select)
/// decides what pressing the button actually does. This keeps the overlay
/// reusable and testable without a provider tree, and keeps play/pause
/// *semantics* where the identity of "which track" already lives.
///
/// Shows when either this widget itself is hovered, or an ancestor
/// [HoverRegion] reports hovering — so wrapping a whole card in a
/// [HoverRegion] reveals the button even when the cursor is over the
/// title text, not just the artwork.
class HoverPlayOverlay extends StatefulWidget {
  final Widget child;
  final bool isPlaying;
  final VoidCallback onPressed;

  /// Where the button sits over [child]. Defaults to bottom-right, which
  /// suits square card artwork; pass [Alignment.center] for row-style
  /// contexts where the button should replace a track-number indicator.
  final Alignment alignment;

  final double buttonSize;
  final double iconSize;
  final EdgeInsets padding;

  /// If true, the button is always visible instead of only on hover —
  /// useful on touch devices where hover can't reveal it. Defaults to
  /// false, matching the app's existing behavior of relying on tap/menu
  /// actions for playback on mobile instead of a persistent overlay button.
  final bool showOnMobile;

  const HoverPlayOverlay({
    super.key,
    required this.child,
    required this.isPlaying,
    required this.onPressed,
    this.alignment = Alignment.bottomRight,
    this.buttonSize = 44,
    this.iconSize = 22,
    this.padding = const EdgeInsets.all(8),
    this.showOnMobile = false,
  });

  @override
  State<HoverPlayOverlay> createState() => _HoverPlayOverlayState();
}

class _HoverPlayOverlayState extends State<HoverPlayOverlay> {
  bool _isHovering = false;

  void _setHovering(bool value) {
    if (_isHovering != value) setState(() => _isHovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final parentHovering = HoverRegion.of(context) ?? false;
    final visible = widget.showOnMobile ||
        (isDesktopPlatform && (_isHovering || parentHovering));

    return MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: widget.alignment,
        children: [
          widget.child,
          Padding(
            padding: widget.padding,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: IgnorePointer(
                ignoring: !visible,
                child: _PlayPauseButton(
                  isPlaying: widget.isPlaying,
                  onPressed: widget.onPressed,
                  size: widget.buttonSize,
                  iconSize: widget.iconSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
    required this.size,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: colorScheme.primary,
        shape: const CircleBorder(),
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: iconSize,
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: colorScheme.onPrimary,
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}