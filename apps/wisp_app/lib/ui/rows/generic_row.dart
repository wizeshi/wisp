import 'package:flutter/material.dart';
import 'package:wisp/ui/overlay/hover.dart';
import 'package:wisp/ui/overlay/waveform.dart';

class GenericRow extends StatelessWidget {
  final String title;
  final String? subtitle;

  final Widget artwork;

  final bool isPlaying;

  final VoidCallback onTap;

  final VoidCallback? onPlay;

  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  final double height;
  final double width;

  const GenericRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.artwork,
    this.isPlaying = false,
    required this.onTap,
    this.onPlay,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.height = 48,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: HoverRegion(
        onTap: onTap,
        onLongPress: isDesktopPlatform ? null : onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            SizedBox(
              height: height,
              width: height,
              child: AspectRatio(aspectRatio: 1, child: artwork),
            ),

            const SizedBox(width: 8),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),

            const Spacer(),

            SizedBox(
              width: 44,
              height: 44,
              child: Builder(
                builder: (context) {
                  final isHovering = HoverRegion.of(context) ?? false;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedOpacity(
                        opacity: (!isPlaying || isHovering) ? 0 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: PlayingWaveform(
                          color: Theme.of(context).colorScheme.primary,
                          size: 16,
                        ),
                      ),
                      if (onPlay != null)
                        HoverVisible(
                          child: IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 20,
                            ),
                            onPressed: onPlay,
                            style: IconButton.styleFrom(
                              shape: const CircleBorder(),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
