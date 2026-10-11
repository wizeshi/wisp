// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/overlay/hover.dart';
import 'package:wisp/core/utils/text_parser.dart';

const double _kSubtitleLineHeight = 18;

class GenericCard extends StatelessWidget {
  final String title;
  final String? subtitle;

  final Widget artwork;

  final bool isPlaying;

  final VoidCallback onTap;

  final VoidCallback? onPlay;
  final VoidCallback? onDoubleTap;

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
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cardRadius = context.tokens.cardRadius;

    Widget visualContent = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: artwork,
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
    );

    Widget content = HoverRegion(
      borderRadius: cardRadius,
      cursor: isDesktopPlatform ? SystemMouseCursors.click : MouseCursor.defer,
      child: Stack(
        children: [
          // Layer 0: Visual card content
          visualContent,

          // Layer 1: InkWell overlay on top of artwork and text for visible ripples
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: isDesktopPlatform ? SystemMouseCursors.click : MouseCursor.defer,
                borderRadius: cardRadius,
                onTap: onTap,
                onDoubleTap: onDoubleTap ?? onPlay,
                onLongPress: isDesktopPlatform ? null : onLongPress,
                onSecondaryTapDown: onSecondaryTapDown,
              ),
            ),
          ),

          // Layer 2: Play button on top of InkWell overlay
          if (onPlay != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: AspectRatio(
                aspectRatio: 1,
                child: CardHoverPlayOverlay(
                  isPlaying: isPlaying,
                  onPressed: onPlay!,
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return content;
  }
}
