import 'package:flutter/material.dart';
import 'package:wisp/ui/cards/hover_overlay.dart';

/// Fixed height reserved for the subtitle line, whether or not a card
/// actually has one. Keeps every card in a row the same height by
/// construction, so a horizontal rail of cards doesn't need an expensive
/// intrinsic-height layout pass to line them up.
const double _kSubtitleLineHeight = 16;

/// The shared visual shell for "artwork + title + subtitle + play button"
/// cards — albums, artists, playlists, tracks shown as a grid card.
///
/// This widget only knows about layout and interaction chrome. It takes
/// artwork and playback state as plain values, so it has no dependency on
/// any specific model type (`GenericAlbum`, `GenericSong`, ...) or provider
/// (`WispAudioHandler`, ...). Entity-specific wrappers (`AlbumCard`,
/// `ArtistCard`, `TrackCard`, `PlaylistCard`) are thin adapters on top of
/// this that:
///   - build an `ArtworkThumbnail` from their model's source/shape
///   - resolve `isPlaying` via `context.watchIsPlayingTrack(...)` (or the
///     equivalent for the entity type) *inside their own build method*,
///     so each card instance owns its own narrow rebuild — never this
///     shell, and never whatever screen happens to be hosting it.
///
/// Example (roughly what `AlbumCard` would look like):
/// ```dart
/// class AlbumCard extends StatelessWidget {
///   final GenericAlbum album;
///   const AlbumCard({required this.album, super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final isPlaying = context.watchIsPlayingAlbum(album.id);
///     return GenericCard(
///       title: album.title,
///       subtitle: album.artists.map((a) => a.name).join(', '),
///       artwork: ArtworkThumbnail(
///         source: ArtworkSource.fromUrl(album.thumbnailUrl),
///         size: ArtworkSize.large,
///         fallbackIcon: Icons.album,
///       ),
///       isPlaying: isPlaying,
///       onTap: () => AppNavigation.of(context).openAlbum(album),
///       onPlay: () => context.read<PlaybackCoordinator>().playAlbum(album),
///     );
///   }
/// }
/// ```
class GenericCard extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// The artwork to display — typically an `ArtworkThumbnail`, but any
  /// widget works (e.g. the special-cased "Liked Songs" art).
  final Widget artwork;

  /// Whether *this entity* is the one currently playing. Callers should
  /// resolve this from their own narrow provider select (see class doc);
  /// `GenericCard` itself never reads playback state. Ignored if [onPlay]
  /// is null.
  final bool isPlaying;

  final VoidCallback onTap;

  /// Shows a hover play/pause button over the artwork when set. Leave
  /// null for entities that aren't playable (e.g. a user profile card) —
  /// the artwork is then shown plain, with no overlay at all.
  final VoidCallback? onPlay;

  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  /// Width of the card. Responsive sizing (e.g. narrower on mobile) is a
  /// layout decision for whatever's arranging a row of these cards — pass
  /// a different width per platform/breakpoint from there rather than
  /// baking platform checks into every card.
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
        onLongPress: onLongPress,
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
                    : HoverPlayOverlay(
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
                    : Text(
                        subtitle!,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
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