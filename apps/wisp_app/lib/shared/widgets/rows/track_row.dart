// Copyright © 2026 wizeshi

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/overlay/cover_play_button.dart';
import 'package:wisp/shared/widgets/overlay/hover.dart';
import 'package:wisp/shared/widgets/overlay/waveform.dart';
import 'package:wisp/shared/widgets/playback/playback_selectors.dart';
import 'package:wisp/core/utils/song_source_icon.dart';
import 'package:wisp/shared/widgets/display/hover_underline.dart';

import 'package:wisp/data/models/metadata_models.dart';

/// Where a [TrackRow]'s play/pause affordance lives. Having both the index
/// column *and* the cover art independently offer a play button is
/// redundant and visually noisy, so a row picks exactly one.
enum PlayIconLocation {
  /// The leading index/track-number column (see [TrackRow.index]) swaps to
  /// a play/pause button on hover. The cover art stays a plain,
  /// non-interactive thumbnail. This is the "Spotify style" desktop list.
  number,

  /// The cover art itself swaps to a play/pause button on hover, via the
  /// same [CoverPlayOverlay] every other row in the app uses. The index
  /// column, if present, stays a plain, static number. This is the "Apple
  /// style" list, and the right choice for any row with no index column
  /// at all (search results, artist top tracks).
  art,
}

/// A row representing a single track, used in the list-detail (playlist /
/// album) view, search results, and artist pages.
///
/// This is deliberately **not** built on top of [GenericRow]. `GenericRow`
/// is a `title` + optional `subtitle` + artwork + single play affordance —
/// exactly what an album/playlist/artist/folder row needs. A track row
/// needs a lot more than that (an artist line *and* an optional album
/// column, an optional date-added column, a duration column, a source
/// badge, an optional track-number column, download/cache state, and
/// playback state that's aware of *which view* is asking about it) and
/// none of those are things the other rows want. Bolting all of that onto
/// `GenericRow` behind a pile of nullable params would make every other
/// row's constructor harder to read for a shape only this one uses.
/// Instead, `TrackRow` reuses the same lower-level building blocks
/// `GenericRow` uses ([ArtworkThumbnail], [CoverPlayOverlay],
/// [HoverRegion]) so the two stay visually and behaviorally consistent
/// without sharing a base class.
///
/// ### "Playing" is scoped to a view, not just a track
///
/// The same song can sit in two playlists at once. If you're playing it
/// from playlist A, playlist B's row for that song must **not** show a
/// "playing" state — otherwise every list containing a song the user has
/// ever played anywhere would light up. To get this right, pass
/// [viewContext]: the [PlaybackContext] this row's *parent view* represents
/// (e.g. `PlaybackContext(type: PlaybackContextType.playlist, id:
/// playlist.id, name: playlist.title, source: playlist.source)` for a
/// playlist page, or the equivalent for an album/artist/search-results
/// view). `TrackRow` then only reports itself as current/playing when the
/// player's *actual, currently-loaded* context matches — see
/// `watchIsCurrentTrackHere` / `watchIsPlayingTrackHere` in
/// `playback_selectors.dart`, which this row calls internally. Pass `null`
/// for a view that has no stable queue identity of its own; the row will
/// then simply never highlight itself as current.
///
/// ### Extra per-track fields
///
/// Rather than a separate `PlaylistItemRow`, "date added" is just an
/// optional field here ([dateAdded] + [showDateAdded]): every other
/// difference between a plain track and a playlist entry (artists, album,
/// duration, source) is already identical, so a second widget would mostly
/// duplicate this one's layout and hover/playing logic. A caller rendering
/// playlist entries passes `dateAdded: item.addedAt, showDateAdded: true`;
/// everyone else just leaves both at their defaults.
///
/// ### Aligning with a column header
///
/// A caller that draws its own header row above a list of `TrackRow`s (see
/// list_detail.dart's `_buildListHeaderContent`) needs its header's column
/// widths, and its show/hide breakpoints, to exactly match this widget's.
/// [indexColumnWidth], [durationColumnWidth] and [dateColumnWidth] exist for
/// the widths — keep them in sync with the header rather than letting each
/// side pick its own numbers. For show/hide, a hidden column collapses to
/// nothing here (its space goes to the title, the only flexible column) —
/// it is not reserved as blank space — so the header must collapse the same
/// column the same way at the same breakpoint, or the two drift apart.
class TrackRow extends StatelessWidget {
  final GenericSong track;

  /// The playback context this row's parent view represents. Used purely
  /// to decide whether *this* row should show as current/playing — see the
  /// class doc. Not used for navigation or queueing; the caller still owns
  /// [onTap] / [onPlayPause].
  final PlaybackContext? viewContext;

  /// 0-based position of this track within its parent view's queue. When
  /// non-null, a leading number column is shown (1-based). When null, no
  /// leading column is shown at all (e.g. a compact search-result row).
  final int? index;

  /// Optional style override. When null, the row queries [PreferencesProvider.style]
  /// via context so each track row element knows which style the app uses.
  final AppStyle? style;

  /// Where the play/pause affordance appears. When null, defaults based on the active
  /// app style: [PlayIconLocation.art] for Apple Music style, or [PlayIconLocation.number]
  /// (if [index] is non-null) for Spotify style.
  final PlayIconLocation? playIconLocation;

  /// Called when the row itself (title/subtitle area or row background) is
  /// tapped. What "tap" should do — start this track fresh, or toggle
  /// playback if it's already current — is a per-view decision, so it's
  /// left entirely to the caller.
  final VoidCallback? onTap;

  /// Called from whichever element [playIconLocation] designates as the
  /// play button. When null, that element still shows hover feedback (for
  /// [PlayIconLocation.art], the cover's scrim/waveform) but isn't
  /// interactive, mirroring `GenericRow(onPlay: null)`.
  final VoidCallback? onPlayPause;

  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  /// Called when the album name is tapped, if [showAlbumName] is set and
  /// the track has an album. When null, the album name is plain text.
  final VoidCallback? onAlbumTap;

  /// Called on right-click / secondary tap of the album name.
  final void Function(TapDownDetails details)? onAlbumSecondaryTapDown;

  /// Called when one of the artist names in the subtitle is tapped. When
  /// null, artist names are plain (non-underlined, non-interactive) text.
  final void Function(GenericSimpleArtist artist)? onArtistTap;

  /// Called on right-click / secondary tap of one artist name. Ignored if
  /// [onArtistTap] is null.
  final void Function(GenericSimpleArtist artist, TapDownDetails details)?
  onArtistSecondaryTapDown;

  /// Called when the three-dots (more options) button is tapped.
  /// When provided in Apple Music style, renders an ellipsis button at the end of the row.
  final void Function(BuildContext buttonContext)? onMoreTap;

  final bool showArtistColumn;
  final bool showArtistInline;
  final bool showAlbumName;
  final bool showDuration;
  final bool showSource;

  /// When [showAlbumName] is true but this is also true, the album name is
  /// folded into the subtitle line next to the artist names (split evenly,
  /// see [_buildSubtitle]) instead of getting its own column. Leave false
  /// for a row that sits under a column header — a header's columns don't
  /// move, so this row's shouldn't either; the caller should instead just
  /// stop passing `showAlbumName: true` once its own layout gets tight, the
  /// same breakpoint its header already uses. Set true for a compact row
  /// with no header of its own (e.g. search results) that still wants the
  /// album name visible somewhere.
  final bool foldAlbumIntoSubtitle;

  /// Only shown when both this and [dateAdded] are set.
  final bool showDateAdded;
  final DateTime? dateAdded;

  final ArtworkSize artworkSize;
  final double height;
  final EdgeInsetsGeometry padding;

  /// Width of the leading index/play-button column. Only relevant when
  /// [index] is non-null.
  final double indexColumnWidth;

  /// Width of the duration column. Only relevant when [showDuration].
  /// When null, defaults to 70 for Apple Music style and 80 for Spotify style.
  final double? durationColumnWidth;

  /// Width of the date-added column. Only relevant when [showDateAdded] and
  /// [dateAdded] are both set — there's no reserved space for this column
  /// when it's hidden, so its width doesn't matter otherwise.
  final double dateColumnWidth;

  /// Optional trailing widget — e.g. a like button — placed after the
  /// album/date columns and before the duration/source columns, matching
  /// where a "favorite" affordance sits in most music-app track lists.
  final Widget? trailing;

  const TrackRow({
    super.key,
    required this.track,
    this.viewContext,
    this.index,
    this.style,
    this.playIconLocation,
    this.onTap,
    this.onPlayPause,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onAlbumTap,
    this.onAlbumSecondaryTapDown,
    this.onArtistTap,
    this.onArtistSecondaryTapDown,
    this.onMoreTap,
    this.showArtistColumn = false,
    this.showArtistInline = true,
    this.showAlbumName = false,
    this.showDuration = false,
    this.showSource = false,
    this.foldAlbumIntoSubtitle = false,
    this.showDateAdded = false,
    this.dateAdded,
    this.artworkSize = ArtworkSize.small,
    this.height = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.indexColumnWidth = 32,
    this.durationColumnWidth,
    this.dateColumnWidth = 120,
    this.trailing,
  }) : assert(
         playIconLocation == null ||
             playIconLocation != PlayIconLocation.number ||
             index != null,
         'playIconLocation: PlayIconLocation.number needs a non-null index '
         '— otherwise there is nowhere for the play button to appear.',
       );

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  static String _formatDateAdded(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  String get _artistNames => track.artists.map((a) => a.name).join(', ');

  Widget get _artwork => ArtworkThumbnail(
    source: ArtworkSource.fromUrl(track.thumbnailUrl),
    size: artworkSize,
    sizeOverride: height,
    semanticLabel: 'Artwork for ${track.title}',
  );

  double get _fontScaling => height / 48.0; 

  /// Explicit badge + cache/download indicator + artist names (individually
  /// tappable via [onArtistTap]), in that order — matching how the old
  /// per-screen "Spotify style" row built its subtitle line.
  Widget _buildTitle(
    BuildContext context, {
    required bool isCurrentHere,
    required bool isApple,
  }) {
    final titleWidget = Text(
      track.title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14 * _fontScaling,
        color: isCurrentHere
            ? Theme.of(context).colorScheme.primary
            : Colors.white,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (!isApple) {
      return titleWidget;
    }

    return Row(
      children: [
        if (track.explicit) ...[
          Icon(Icons.explicit, size: 14 * _fontScaling, color: Colors.grey[500]),
          const SizedBox(width: 4),
        ],
        _CacheIndicator(trackId: track.id, fontScaling: _fontScaling),
        Expanded(child: titleWidget),
      ],
    );
  }

  /// In Spotify style: Explicit badge + cache/download indicator + artist names (individually
  /// tappable via [onArtistTap]), in that order — matching the desktop Spotify row.
  /// In Apple Music style: Artist names only (explicit & cache indicator are placed with the title).
  Widget _buildSubtitle(
    BuildContext context, {
    required bool foldAlbum,
    required bool isApple,
  }) {
    final artistWidget = _buildArtistWrap();
    final Widget artistArea = foldAlbum && track.album?.title.isNotEmpty == true
        ? Row(
            children: [
              Expanded(child: artistWidget),
              Text(
                ' \u2022 ',
                style: TextStyle(color: Colors.grey[400], fontSize: 12 * _fontScaling),
              ),
              Expanded(child: _buildAlbumText()),
            ],
          )
        : artistWidget;

    if (isApple) {
      return artistArea;
    }

    return Row(
      children: [
        if (track.explicit) ...[
          Icon(Icons.explicit, size: 14 * _fontScaling, color: Colors.grey[500]),
          const SizedBox(width: 4),
        ],
        _CacheIndicator(trackId: track.id, fontScaling: _fontScaling),
        Expanded(child: artistArea),
      ],
    );
  }

  Widget _buildArtistWrap() {
    if (track.artists.isEmpty) {
      return const SizedBox.shrink();
    }
    if (onArtistTap == null) {
      return Text(
        _artistNames,
        style: TextStyle(color: Colors.grey[500], fontSize: 12 * _fontScaling),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Wrap(
      children: [
        for (var i = 0; i < track.artists.length; i++) ...[
          HoverUnderline(
            onTap: () => onArtistTap!(track.artists[i]),
            onSecondaryTapDown: onArtistSecondaryTapDown == null
                ? null
                : (details) =>
                      onArtistSecondaryTapDown!(track.artists[i], details),
            builder: (hovering) => Text(
              track.artists[i].name,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12 * _fontScaling,
                decoration: hovering
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (i < track.artists.length - 1)
            Text(', ', style: TextStyle(color: Colors.grey[500], fontSize: 12 * _fontScaling)),
        ],
      ],
    );
  }

  Widget _buildAlbumText() {
    final album = track.album;
    if (album == null || album.title.isEmpty) {
      return const SizedBox.shrink();
    }
    final title = album.title;
    final style = TextStyle(color: Colors.grey[400], fontSize: 12 * _fontScaling);
    if (onAlbumTap == null && onAlbumSecondaryTapDown == null) {
      return Text(
        title,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return HoverUnderline(
      onTap: onAlbumTap,
      onSecondaryTapDown: onAlbumSecondaryTapDown,
      builder: (hovering) => Text(
        title,
        style: style.copyWith(
          decoration: (hovering && onAlbumTap != null)
              ? TextDecoration.underline
              : TextDecoration.none,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ??
        context.select<PreferencesProvider, AppStyle>((p) => p.style);
    final isApple = effectiveStyle == AppStyle.AppleMusic;

    final effectivePlayIconLocation = playIconLocation ??
        (isApple
            ? PlayIconLocation.art
            : (index != null
                ? PlayIconLocation.number
                : PlayIconLocation.art));

    final effectiveDurationColumnWidth =
        durationColumnWidth ?? (isApple ? 70.0 : 80.0);

    final isCurrentHere = context.watchIsCurrentTrackHere(
      trackId: track.id,
      viewContext: viewContext,
    );
    final isPlayingHere = context.watchIsPlayingTrackHere(
      trackId: track.id,
      viewContext: viewContext,
    );

    return Material(
      color: Colors.transparent,
      child: HoverRegion(
        onTap: onTap,
        onLongPress: isDesktopPlatform ? null : onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: padding,
          child: SizedBox(
            height: height,
            child: Builder(
              builder: (context) {
                final showAlbumColumn =
                    showAlbumName && !foldAlbumIntoSubtitle;
                final showDateColumn = showDateAdded && !isApple;
                final showSubtitle = !isApple ||
                    showArtistInline ||
                    (foldAlbumIntoSubtitle && showAlbumName);

                return Row(
                  children: [
                    if (index != null) ...[
                      SizedBox(
                        width: indexColumnWidth,
                        child: _IndexOrPlayButton(
                          index: index!,
                          isPlaying: isPlayingHere,
                          onPressed: onPlayPause,
                          canTogglePlay:
                              effectivePlayIconLocation == PlayIconLocation.number,
                          fontScaling: _fontScaling,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    SizedBox(
                      height: height,
                      width: height,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: effectivePlayIconLocation == PlayIconLocation.art
                            ? CoverPlayOverlay(
                                isPlaying: isPlayingHere,
                                onPressed: onPlayPause,
                                iconSize: height * 0.42,
                                waveformSize: height * 0.32,
                                child: _artwork,
                              )
                            : _artwork,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTitle(
                            context,
                            isCurrentHere: isCurrentHere,
                            isApple: isApple,
                          ),
                          if (showSubtitle) ...[
                            const SizedBox(height: 2),
                            _buildSubtitle(
                              context,
                              foldAlbum:
                                  foldAlbumIntoSubtitle && showAlbumName,
                              isApple: isApple,
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (isApple && showArtistColumn)
                      Expanded(flex: 2, child: _buildArtistWrap()),

                    if (showAlbumColumn)
                      Expanded(flex: 2, child: _buildAlbumText()),

                    if (showDateColumn)
                      SizedBox(
                        width: dateColumnWidth,
                        child: dateAdded != null
                            ? Text(
                                _formatDateAdded(dateAdded!),
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12 * _fontScaling,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : const SizedBox.shrink(),
                      ),

                    if (!isApple && trailing != null) trailing!,

                    if (showDuration) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: effectiveDurationColumnWidth,
                        child: Text(
                          _formatDuration(track.durationSecs),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12 * _fontScaling,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],

                    if (showSource && !isApple) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 32,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            songSourceIcon(track.source),
                            size: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],

                    if (onMoreTap != null)
                      SizedBox(
                        width: 48,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Builder(
                            builder: (buttonContext) => IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              icon: Icon(
                                isApple
                                    ? CupertinoIcons.ellipsis
                                    : Icons.more_horiz,
                                color: isApple
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey[400],
                                size: 18,
                              ),
                              onPressed: () => onMoreTap!(buttonContext),
                            ),
                          ),
                        ),
                      )
                    else if (isApple)
                      const SizedBox(width: 48)
                    else
                      const SizedBox(width: 16),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Cache/download state for one track — cached (offline pin), downloading
/// (progress ring), or neither (nothing). Ported from the per-screen
/// `AnimatedBuilder(animation: AudioCacheManager.instance, ...)` blocks
/// that used to be duplicated in `_buildSongTitleWithIcons` and
/// `_buildArtistWithIcons`.
class _CacheIndicator extends StatelessWidget {
  final String trackId;
  final double fontScaling;

  const _CacheIndicator({required this.trackId, required this.fontScaling});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AudioCacheManager.instance,
      builder: (context, _) {
        final cacheManager = AudioCacheManager.instance;
        final isCached = cacheManager.isTrackCached(trackId);
        final isDownloading = cacheManager.isDownloading(trackId);
        if (!isCached && !isDownloading) return const SizedBox.shrink();
        if (isDownloading) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: SizedBox(
              width: 12 * fontScaling,
              height: 12 * fontScaling,
              child: CircularProgressIndicator(
                value: cacheManager.getDownloadProgress(trackId) ?? 0,
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Colors.grey[800],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            Icons.offline_pin,
            size: 12 * fontScaling,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

/// The leading `1`, `2`, `3`... column. When [canTogglePlay] is set (i.e.
/// [TrackRow.playIconLocation] is [PlayIconLocation.number]), it swaps to a
/// play/pause button on hover on desktop, and to the same [PlayingWaveform]
/// the cover uses elsewhere when the track is playing *and* not hovered —
/// mirroring [CoverPlayOverlay]'s own button-vs-waveform logic, just with a
/// flat icon instead of a filled circular button, matching this column's
/// plain numeric style. Otherwise — including whenever the play affordance
/// lives on the cover instead — it's always a plain, static number.
class _IndexOrPlayButton extends StatelessWidget {
  final int index;
  final bool isPlaying;
  final VoidCallback? onPressed;
  final bool canTogglePlay;
  final double fontScaling;

  const _IndexOrPlayButton({
    required this.index,
    required this.isPlaying,
    required this.onPressed,
    required this.canTogglePlay,
    required this.fontScaling,
  });

  @override
  Widget build(BuildContext context) {
    final number = Text(
      '${index + 1}',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.grey[400], fontSize: 12 * fontScaling),
    );

    if (!canTogglePlay) {
      return number;
    }

    final hovering = isDesktopPlatform && (HoverRegion.of(context) ?? false);
    final showButton = hovering && onPressed != null;
    final showWaveform = isPlaying && !showButton;

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: showButton || showWaveform ? 0 : 1,
          duration: const Duration(milliseconds: 120),
          child: number,
        ),
        AnimatedOpacity(
          opacity: showWaveform ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: PlayingWaveform(
            active: showWaveform,
            color: Theme.of(context).colorScheme.primary,
            size: 14,
          ),
        ),
        AnimatedOpacity(
          opacity: showButton ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: IgnorePointer(
            ignoring: !showButton,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              iconSize: 18,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              color: Colors.white,
              onPressed: onPressed,
            ),
          ),
        ),
      ],
    );
  }
}
