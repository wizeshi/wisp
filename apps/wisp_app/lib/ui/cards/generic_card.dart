import 'package:flutter/material.dart';
import 'package:wisp/ui/overlay/hover.dart';
import 'package:wisp/utils/text_parser.dart';

const double _kSubtitleLineHeight = 16;

class GenericCard extends StatelessWidget {
  final String title;
  final String? subtitle;

  final Widget artwork;

  final bool isPlaying;

  final VoidCallback onTap;

  final VoidCallback? onPlay;

  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  final double width;

  const GenericCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.artwork,
    this.isPlaying = false,
    required this.onTap,
    this.onPlay,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: HoverRegion(
        onTap: onTap,
        onLongPress: isDesktopPlatform ? null : onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: onPlay == null
                    ? artwork
                    : CardHoverPlayOverlay(
                        isPlaying: isPlaying,
                        onPressed: onPlay!,
                        child: artwork,
                      ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 2),
              SizedBox(
                height: _kSubtitleLineHeight,
                child: subtitle == null
                    ? null
                    : TextParser.needsParsing(subtitle!)
                    ? buildParsedText(
                        context,
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        linkStyle: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
