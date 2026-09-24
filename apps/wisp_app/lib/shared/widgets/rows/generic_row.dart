import 'package:flutter/material.dart';
import 'package:wisp/ui/overlay/cover_play_button.dart';
import 'package:wisp/ui/overlay/hover.dart';

enum GenericRowPlayPosition { cover, end, none }

class GenericRow extends StatelessWidget {
  final String title;
  final String? subtitle;

  final Widget artwork;

  final bool isPlaying;

  final VoidCallback onTap;

  final VoidCallback? onPlay;

  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  final GenericRowPlayPosition playPosition;

  final double height;
  final double width;

  final EdgeInsetsGeometry padding;

  final Color? backgroundColor;
  final bool showSubtitle;

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
    this.playPosition = GenericRowPlayPosition.end,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: HoverRegion(
        onTap: onTap,
        onLongPress: isDesktopPlatform ? null : onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              SizedBox(
                height: height,
                width: height,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: playPosition == GenericRowPlayPosition.cover
                      ? CoverPlayOverlay(
                          isPlaying: isPlaying,
                          onPressed: onPlay,
                          iconSize: height * 0.42,
                          waveformSize: height * 0.32,
                          child: artwork,
                        )
                      : artwork,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
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
                    if (showSubtitle && subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              if (playPosition == GenericRowPlayPosition.end)
                Builder(
                  builder: (context) {
                    final visible = HoverRegion.of(context) ?? false;
                    return PlaybackAffordance(
                      visible: visible,
                      isPlaying: isPlaying,
                      onPressed: onPlay,
                    );
                  },
                ),

              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
