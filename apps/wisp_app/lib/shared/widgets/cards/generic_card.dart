import 'package:flutter/material.dart';
import 'package:wisp/ui/overlay/hover.dart';
import 'package:wisp/utils/text_parser.dart';

const double _kSubtitleLineHeight = 18;

class GenericCard extends StatelessWidget {
  final String title;
  final String? subtitle;

  final Widget artwork;

  final bool isPlaying;

  final VoidCallback onTap;

  final VoidCallback? onPlay;

  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  final double? width;

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
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = HoverRegion(
      onTap: onTap,
      onLongPress: isDesktopPlatform ? null : onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
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
                        fontSize: 13,
                      ),
                      linkStyle: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return content;
  }
}
