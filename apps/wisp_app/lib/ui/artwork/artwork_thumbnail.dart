import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Where an artwork image should be loaded from.
///
/// Centralizes the network-vs-local-file-vs-nothing branching that used to
/// be re-implemented at every call site (see `_isLocalImagePath` /
/// `Image.file` ternaries scattered across the views). Build one of these
/// with [ArtworkSource.fromUrl] in almost all cases — it auto-detects local
/// paths using the same convention the app already uses (`/...` or
/// `file://...`).
sealed class ArtworkSource {
  const ArtworkSource();

  /// Picks [ArtworkSource.network] or [ArtworkSource.file] based on
  /// [urlOrPath], and falls back to [ArtworkSource.none] for an empty
  /// string. This is the constructor most call sites should use, since
  /// `thumbnailUrl` fields across the app's models may contain either a
  /// remote URL or a local file path.
  factory ArtworkSource.fromUrl(String? urlOrPath) {
    if (urlOrPath == null || urlOrPath.isEmpty) {
      return const ArtworkSource.none();
    }
    if (urlOrPath.startsWith('/') || urlOrPath.startsWith('file://')) {
      return ArtworkSource.file(File(urlOrPath.replaceFirst('file://', '')));
    }
    return ArtworkSource.network(urlOrPath);
  }

  const factory ArtworkSource.network(String url) = _NetworkArtwork;

  const factory ArtworkSource.file(File file) = _FileArtwork;

  const factory ArtworkSource.none() = _NoArtwork;
}

class _NetworkArtwork extends ArtworkSource {
  final String url;
  const _NetworkArtwork(this.url);
}

class _FileArtwork extends ArtworkSource {
  final File file;
  const _FileArtwork(this.file);
}

class _NoArtwork extends ArtworkSource {
  const _NoArtwork();
}

/// The corner treatment for an [ArtworkThumbnail].
enum ArtworkShape {
  /// Rounded corners — albums, playlists, tracks, folders.
  rounded,

  /// Fully circular — artists.
  circle,
}

/// Standard artwork sizes used across the app.
///
/// Pick the token that matches where the artwork appears rather than an
/// arbitrary double — this keeps every screen's "list row" or "card" art
/// visually identical, and means resizing a whole category later is a
/// one-line change instead of a grep-and-replace.
///
/// If a screen genuinely needs a one-off size (e.g. a responsive full-bleed
/// player), use [ArtworkThumbnail.sizeOverride] rather than adding a token
/// here for a single caller.
enum ArtworkSize {
  /// Dense rows — queue list, mini rail items.
  tiny(32),

  /// Standard list rows — search results, library rows, track lists.
  small(48),

  /// Medium list contexts — e.g. the list-detail track rows.
  medium(88),

  /// Grid cards and horizontal rails.
  large(160),

  /// Full player / now-playing surfaces.
  full(300);

  final double logicalSize;

  const ArtworkSize(this.logicalSize);
}

/// A single, consistent way to render artwork anywhere in the app.
///
/// Handles, in one place:
/// - network vs. local-file vs. missing artwork ([ArtworkSource])
/// - correct memory-cache sizing for [CachedNetworkImage], computed from the
///   actual rendered size and the device's pixel ratio (so artwork is never
///   blurry on high-DPI displays, and never decoded larger than it needs to
///   be — see the previous flat `memCacheWidth: 88` used in list_detail.dart,
///   which ignored device pixel ratio entirely)
/// - a single placeholder/error/fallback treatment
/// - shape (rounded square vs. circle) and corner radius, proportional to
///   size rather than a hand-picked magic number per screen
///
/// This widget is intentionally non-interactive — it does not know about
/// hover, tap, or "now playing" state. Wrap it with something like
/// `HoverPlayOverlay` for interactive contexts; keeping this widget dumb
/// means it never causes a rebuild it doesn't need to.
class ArtworkThumbnail extends StatelessWidget {
  /// Where to load the image from. Build this with [ArtworkSource.fromUrl]
  /// in almost all cases.
  final ArtworkSource source;

  /// The size token to render at. See [ArtworkSize] for guidance on which
  /// to pick.
  final ArtworkSize size;

  /// Escape hatch for the rare case a screen needs a size that doesn't fit
  /// any [ArtworkSize] token (e.g. a responsive, fluid-width surface). When
  /// set, this overrides [size]'s logical size, but [size] is still used to
  /// pick a sensible default icon/placeholder scale.
  final double? sizeOverride;

  /// Rounded square (default) or circular (artists).
  final ArtworkShape shape;

  /// Icon shown when there is no artwork, or the image fails to load.
  /// Defaults to a generic music note; pass `Icons.person` for artists,
  /// `Icons.album` for albums, `Icons.playlist_play` for playlists, etc.
  final IconData fallbackIcon;

  /// Optional semantic label for accessibility (e.g. "Artwork for {title}").
  final String? semanticLabel;

  const ArtworkThumbnail({
    super.key,
    required this.source,
    required this.size,
    this.sizeOverride,
    this.shape = ArtworkShape.rounded,
    this.fallbackIcon = Icons.music_note,
    this.semanticLabel,
  });

  double get _renderSize => sizeOverride ?? size.logicalSize;

  BorderRadius get _borderRadius => shape == ArtworkShape.circle
      ? BorderRadius.circular(_renderSize / 2)
      // Proportional to size rather than a fixed magic number, so small
      // and large artwork both look correctly rounded instead of sharing
      // one radius that's too subtle at 160px or too aggressive at 32px.
      : BorderRadius.circular(_renderSize * 0.045);

  @override
  Widget build(BuildContext context) {
    final renderSize = _renderSize;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    // Decode/cache at the actual physical pixel size the artwork will be
    // painted at — sharp on high-DPI displays, and never wastefully large
    // on small ones. Computed once, here, instead of per-screen guesswork.
    final cacheDimension = (renderSize * devicePixelRatio).round();

    final Widget image = switch (source) {
      _NetworkArtwork(:final url) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: cacheDimension,
        memCacheHeight: cacheDimension,
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _fallback(),
      ),
      _FileArtwork(:final file) => Image.file(
        file,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      ),
      _NoArtwork() => _fallback(),
    };

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: _borderRadius,
        child: SizedBox(width: renderSize, height: renderSize, child: image),
      ),
    );
  }

  Widget _placeholder() {
    return Container(color: Colors.grey[900]);
  }

  Widget _fallback() {
    return Container(
      color: Colors.grey[900],
      alignment: Alignment.center,
      child: Icon(
        fallbackIcon,
        color: Colors.grey[600],
        size: _renderSize * 0.4,
      ),
    );
  }
}
