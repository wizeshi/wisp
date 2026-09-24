import 'package:flutter/material.dart';

import 'package:wisp/shared/widgets/overlay/hover.dart';
import 'package:wisp/shared/widgets/overlay/waveform.dart';

class PlaybackAffordance extends StatelessWidget {
  final bool visible;
  final bool isPlaying;
  final VoidCallback? onPressed;
  final double buttonSize;
  final double iconSize;
  final double waveformSize;

  const PlaybackAffordance({
    super.key,
    required this.visible,
    required this.isPlaying,
    this.onPressed,
    this.buttonSize = 44,
    this.iconSize = 20,
    this.waveformSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final showButton = visible && onPressed != null;
    final showWaveform = isPlaying && !showButton;

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: showWaveform ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: PlayingWaveform(
              active: showWaveform,
              color: Theme.of(context).colorScheme.primary,
              size: waveformSize,
            ),
          ),
          if (onPressed != null)
            AnimatedOpacity(
              opacity: showButton ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: IgnorePointer(
                ignoring: !showButton,
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: iconSize,
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    onPressed: onPressed,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CoverPlayOverlay extends StatefulWidget {
  final Widget child;
  final bool isPlaying;
  final VoidCallback? onPressed;
  final double iconSize;
  final double waveformSize;
  final Color scrimColor;

  const CoverPlayOverlay({
    super.key,
    required this.child,
    required this.isPlaying,
    this.onPressed,
    this.iconSize = 20,
    this.waveformSize = 16,
    this.scrimColor = const Color(0x73000000), // Colors.black @ 45% alpha
  });

  @override
  State<CoverPlayOverlay> createState() => _CoverPlayOverlayState();
}

class _CoverPlayOverlayState extends State<CoverPlayOverlay> {
  bool _isHovering = false;

  void _setHovering(bool value) {
    if (isDesktopPlatform && _isHovering != value) {
      setState(() => _isHovering = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentHovering = HoverRegion.of(context) ?? false;
    final hovering = isDesktopPlatform && (_isHovering || parentHovering);
    final showButton = hovering && widget.onPressed != null;
    final showWaveform = widget.isPlaying && !showButton;
    final showScrim = showButton || showWaveform;

    return MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          AnimatedOpacity(
            opacity: showScrim ? 1 : 0,
            duration: const Duration(milliseconds: 130),
            child: Container(color: widget.scrimColor),
          ),
          if (showButton)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onPressed,
                  child: Icon(
                    widget.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: widget.iconSize,
                  ),
                ),
              ),
            )
          else if (showWaveform)
            Center(
              child: PlayingWaveform(
                color: Theme.of(context).colorScheme.primary,
                size: widget.waveformSize,
              ),
            ),
        ],
      ),
    );
  }
}
