// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';
import 'package:wisp/utils/text_parser.dart';
import 'package:wisp/widgets/marquee_text.dart';

import '../models/metadata_models.dart';
import '../providers/navigation_state.dart';
import '../services/app_focus_service.dart';
import '../services/wisp_audio_handler.dart';
import '../providers/lyrics/provider.dart';
import '../providers/library/library_state.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/app_navigation.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/navigation_history.dart';
import '../utils/lyrics_timing.dart';
import '../views/list_detail.dart';
import 'full_player.dart';
import 'animated_lyrics_preview.dart';
import 'focus_freeze_builder.dart';
import 'connect/connect_menu.dart';
import 'entity_context_menus.dart';
import 'hover_underline.dart';
import 'like_button.dart';

class RightSidebar extends StatefulWidget {
  final double width;
  final ValueChanged<double> onResize;

  const RightSidebar({super.key, required this.width, required this.onResize});

  @override
  State<RightSidebar> createState() => _RightSidebarState();
}

class _RightSidebarState extends State<RightSidebar> {
  bool _isHoveringSidebar = false;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return const SizedBox.shrink();
    }

    final navState = context.watch<NavigationState>();

    return SizedBox(
      width: widget.width,
      height: double.infinity,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHoveringSidebar = true),
        onExit: (_) => setState(() => _isHoveringSidebar = false),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ResizeHandle(onResize: widget.onResize),
            Expanded(
              child: Material(
                color: const Color(0xFF0F0F0F),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.grey[900]!, width: 1),
                    ),
                  ),
                  child: SafeArea(
                    left: false,
                    right: true,
                    top: false,
                    bottom: false,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.topCenter,
                          children: [
                            ...previousChildren,
                            ?currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        final offset = Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(animation);
                        return ClipRect(
                          child: SlideTransition(
                            position: offset,
                            child: child,
                          ),
                        );
                      },
                      child:
                          navState.rightSidebarContent ==
                              RightSidebarContent.connect
                          ? ConnectMenu(
                              key: const ValueKey('connect-sidebar-content'),
                              compact: false,
                              onClose: () {
                                context
                                    .read<NavigationState>()
                                    .showLibrarySidebar();
                              },
                            )
                          : SingleChildScrollView(
                              key: const ValueKey('library-sidebar-content'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _NowPlayingCard(
                                    showHoverControls: _isHoveringSidebar,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _LyricsPreviewCard(),
                                        SizedBox(height: 16),
                                        _ArtistInfoCard(),
                                        SizedBox(height: 16),
                                        _QueuePreviewCard(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onResize;

  const _ResizeHandle({required this.onResize});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
        child: Container(
          color: Colors.black,
          width: 8,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              width: 2,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Widget? background;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool showBottomFade;
  final Color bottomFadeColor;
  final double bottomFadeHeight;

  const _SectionCard({
    required this.child,
    this.backgroundColor,
    this.background,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = 14,
    this.showBottomFade = false,
    this.bottomFadeColor = const Color(0xFF0F0F0F),
    this.bottomFadeHeight = 24,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = backgroundColor ?? const Color(0xFF1A1A1A);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            if (background != null) Positioned.fill(child: background!),
            Container(
              color: background == null ? baseColor : Colors.transparent,
              padding: padding,
              child: child,
            ),
            if (showBottomFade)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: bottomFadeHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          bottomFadeColor.withValues(alpha: 0),
                          bottomFadeColor.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final bool showHoverControls;

  const _NowPlayingCard({required this.showHoverControls});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppleMusicFullScreenPlayer
          .animatedCanvasTemporarilyDisabledListenable,
      builder: (context, animatedCanvasDisabled, _) {
        return Selector<WispAudioHandler, _NowPlayingData>(
          selector: (context, player) => _NowPlayingData(
            track: player.currentTrack,
            playbackContextName: player.playbackContext?.name,
            playbackContextType: player.playbackContext?.type,
            playbackContextID: player.playbackContext?.id,
          ),
          builder: (context, data, child) {
            final useCanvas = context.select<PreferencesProvider, bool>(
              (prefs) => prefs.animatedCanvasEnabled,
            );
            final libraryState = context.read<LibraryState>();
            final track = data.track;
            final resolvedContextName = _resolvePlaybackContextName(
              data,
              libraryState,
            );
            final headerText = resolvedContextName ?? 'Now Playing';
            final canOpenContext =
                data.playbackContextID != null &&
                data.playbackContextID!.isNotEmpty &&
                (data.playbackContextType == PlaybackContextType.playlist ||
                    data.playbackContextType == PlaybackContextType.album ||
                    data.playbackContextType == PlaybackContextType.artist);
            final canUseCanvas =
                !animatedCanvasDisabled &&
                useCanvas &&
                (track?.source == SongSource.spotifyInternal ||
                    track?.source == SongSource.spotify);

            Widget buildCard({String? canvasUrl}) {
              final hasCanvas = canvasUrl != null && canvasUrl.isNotEmpty;
              return _SectionCard(
                background: hasCanvas
                    ? _CanvasBackground(url: canvasUrl)
                    : null,
                borderRadius: 0,
                showBottomFade: hasCanvas,
                bottomFadeColor: const Color(0xFF0F0F0F),
                bottomFadeHeight: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          width: showHoverControls ? 28 : 0,
                          child: ClipRect(
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              offset: showHoverControls
                                  ? Offset.zero
                                  : const Offset(-0.25, 0),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: showHoverControls ? 1 : 0,
                                child: IgnorePointer(
                                  ignoring: !showHoverControls,
                                  child: IconButton(
                                    tooltip: 'Hide sidebar',
                                    icon: const Icon(
                                      Symbols.right_panel_close,
                                    ),
                                    iconSize: 20,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 20,
                                      maxWidth: 20,
                                      minHeight: 20,
                                      maxHeight: 20,
                                    ),
                                    onPressed: () {
                                      context
                                          .read<NavigationState>()
                                          .toggleRightSidebar();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: HoverUnderline(
                            cursor: canOpenContext
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                            onTap: canOpenContext
                                ? () => _openPlaybackContext(
                                    context,
                                    data.playbackContextType!,
                                    data.playbackContextID!,
                                    resolvedContextName,
                                  )
                                : null,
                            onSecondaryTapDown: canOpenContext
                                ? (details) {
                                    _showPlaybackContextMenu(
                                      context,
                                      data,
                                      libraryState,
                                      details.globalPosition,
                                    );
                                  }
                                : null,
                            builder: (isHovering) => Text(
                              headerText,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: isHovering
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                        AnimatedScale(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          scale: showHoverControls ? 1 : 0.85,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: showHoverControls ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !showHoverControls,
                              child: Builder(
                                builder: (buttonContext) {
                                  return IconButton(
                                    tooltip: 'More',
                                    icon: const Icon(Icons.more_horiz),
                                    iconSize: 18,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    onPressed: track == null
                                        ? null
                                        : () async {
                                            final overlay =
                                                Overlay.of(
                                                      context,
                                                    ).context.findRenderObject()
                                                    as RenderBox;
                                            final box =
                                                buttonContext.findRenderObject()
                                                    as RenderBox?;
                                            if (box == null) return;
                                            final rect = Rect.fromPoints(
                                              box.localToGlobal(
                                                Offset.zero,
                                                ancestor: overlay,
                                              ),
                                              box.localToGlobal(
                                                box.size.bottomRight(
                                                  Offset.zero,
                                                ),
                                                ancestor: overlay,
                                              ),
                                            );
                                            await AppleMusicFullScreenPlayer.showTrackMenuWithCanvasToggle(
                                              context,
                                              track: track,
                                              anchorRect: rect,
                                            );
                                          },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (track == null)
                      const Text(
                        'Nothing playing',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: hasCanvas
                                ? const _BlankArtwork()
                                : _TrackArtwork(url: track.thumbnailUrl),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTrackTitle(context, track),
                                    const SizedBox(height: 2),
                                    _buildTrackArtists(context, track),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                    width: showHoverControls ? 28 : 0,
                                    child: ClipRect(
                                      child: AnimatedOpacity(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        opacity: showHoverControls ? 1 : 0,
                                        child: IgnorePointer(
                                          ignoring: !showHoverControls,
                                          child: IconButton(
                                            tooltip: 'Share',
                                            icon: const Icon(Icons.share),
                                            iconSize: 18,
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            onPressed: () async {
                                              await EntityContextMenus.copySpotifyShareUrl(
                                                context,
                                                source: track.source,
                                                type: 'track',
                                                id: track.id,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  LikeButton(
                                    track: track,
                                    iconSize: 20,
                                    padding: const EdgeInsets.all(2),
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              );
            }

            if (track == null || !canUseCanvas) {
              return buildCard();
            }

            final spotifyInternal = context.read<SpotifyInternalProvider>();
            return FutureBuilder<String?>(
              future: spotifyInternal.getCanvasUrl(track.id),
              builder: (context, snapshot) {
                final canvasUrl = snapshot.data ?? '';
                return buildCard(canvasUrl: canvasUrl);
              },
            );
          },
        );
      },
    );
  }

  String? _resolvePlaybackContextName(
    _NowPlayingData data,
    LibraryState libraryState,
  ) {
    final contextName = data.playbackContextName?.trim();
    if (_isUsableContextName(contextName)) {
      return contextName;
    }

    final contextType = data.playbackContextType;
    final contextId = data.playbackContextID;
    if (contextType == null || contextId == null || contextId.isEmpty) {
      return null;
    }

    switch (contextType) {
      case PlaybackContextType.playlist:
        final playlist = libraryState.playlists
            .cast<GenericPlaylist?>()
            .firstWhere((item) => item?.id == contextId, orElse: () => null);
        final title = playlist?.title.trim();
        return _isUsableContextName(title) ? title : null;
      case PlaybackContextType.album:
        final album = libraryState.albums.cast<GenericAlbum?>().firstWhere(
          (item) => item?.id == contextId,
          orElse: () => null,
        );
        final title = album?.title.trim();
        return _isUsableContextName(title) ? title : null;
      case PlaybackContextType.artist:
        final artist = libraryState.artists
            .cast<GenericSimpleArtist?>()
            .firstWhere((item) => item?.id == contextId, orElse: () => null);
        final name = artist?.name.trim();
        return _isUsableContextName(name) ? name : null;
      default:
        return null;
    }
  }

  bool _isUsableContextName(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }

    final normalized = value.toLowerCase();
    return normalized != 'unknown' &&
        normalized != 'unknown playlist' &&
        normalized != 'unknown album' &&
        normalized != 'unknown artist';
  }

  Widget _buildTrackTitle(BuildContext context, GenericSong track) {
    final album = track.album;
    final hasAlbum = album != null && album.id.isNotEmpty;
    const style = TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    );

    return MarqueeText(
      text: track.title,
      style: style,
      pauseWhenUnfocused: true,
      builder: (context, textStyle) => HoverUnderline(
        cursor: hasAlbum ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: hasAlbum ? () => _openAlbum(context, album) : null,
        onSecondaryTapDown: (details) {
          EntityContextMenus.showTrackMenu(
            context,
            track: track,
            globalPosition: details.globalPosition,
          );
        },
        builder: (isHovering) => Text(
          track.title,
          style: textStyle.copyWith(
            decoration: isHovering && hasAlbum
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildTrackArtists(BuildContext context, GenericSong track) {
    final artists = track.artists;
    if (artists.isEmpty) return const SizedBox.shrink();

    final joinedText = artists.map((a) => a.name).join(', ');
    final style = TextStyle(
      color: Colors.grey[200],
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: joinedText, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final overflows =
            constraints.hasBoundedWidth &&
            textPainter.width > constraints.maxWidth;

        if (overflows) {
          return MarqueeText(
            text: joinedText,
            style: style,
            pauseWhenUnfocused: true,
            builder: artists.length == 1
                ? (context, textStyle) => HoverUnderline(
                    cursor: SystemMouseCursors.click,
                    onTap: () => _openArtist(context, artists.first),
                    onSecondaryTapDown: (details) {
                      EntityContextMenus.showArtistMenu(
                        context,
                        artist: artists.first,
                        globalPosition: details.globalPosition,
                      );
                    },
                    builder: (isHovering) => Text(
                      joinedText,
                      style: textStyle.copyWith(
                        decoration: isHovering
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  )
                : null,
          );
        }

        return Wrap(
          children: [
            for (int i = 0; i < artists.length; i++) ...[
              HoverUnderline(
                cursor: SystemMouseCursors.click,
                onTap: () => _openArtist(context, artists[i]),
                onSecondaryTapDown: (details) {
                  EntityContextMenus.showArtistMenu(
                    context,
                    artist: artists[i],
                    globalPosition: details.globalPosition,
                  );
                },
                builder: (isHovering) => Text(
                  artists[i].name,
                  style: style.copyWith(
                    decoration: isHovering
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                ),
              ),
              if (i < artists.length - 1)
                Text(', ', style: style),
            ],
          ],
        );
      },
    );
  }

  void _openAlbum(BuildContext context, GenericSimpleAlbum album) {
    AppNavigation.instance.openSharedList(
      context,
      id: album.id,
      type: SharedListType.album,
      initialTitle: album.title,
      initialThumbnailUrl: album.thumbnailUrl,
    );
  }

  void _openArtist(BuildContext context, GenericSimpleArtist artist) {
    AppNavigation.instance.openArtist(
      context,
      artistId: artist.id,
      initialArtist: artist,
    );
  }

  void _openPlaybackContext(
    BuildContext context,
    PlaybackContextType contextType,
    String contextId,
    String? contextName,
  ) {
    AppNavigation.instance.openPlaybackContext(
      context,
      contextType: contextType,
      contextId: contextId,
      contextName: contextName,
    );
  }

  void _showPlaybackContextMenu(
    BuildContext context,
    _NowPlayingData data,
    LibraryState libraryState,
    Offset globalPosition,
  ) {
    final contextType = data.playbackContextType;
    final contextId = data.playbackContextID;
    if (contextType == null || contextId == null || contextId.isEmpty) {
      return;
    }

    if (contextType == PlaybackContextType.playlist) {
      final playlist = libraryState.playlists
          .cast<GenericPlaylist?>()
          .firstWhere((item) => item?.id == contextId, orElse: () => null);
      if (playlist != null) {
        EntityContextMenus.showPlaylistMenu(
          context,
          playlist: playlist,
          globalPosition: globalPosition,
        );
      }
      return;
    }

    if (contextType == PlaybackContextType.album) {
      final album = libraryState.albums.cast<GenericAlbum?>().firstWhere(
        (item) => item?.id == contextId,
        orElse: () => null,
      );
      if (album != null) {
        EntityContextMenus.showAlbumMenu(
          context,
          album: album,
          globalPosition: globalPosition,
        );
      }
      return;
    }

    if (contextType == PlaybackContextType.artist) {
      final artist = libraryState.artists
          .cast<GenericSimpleArtist?>()
          .firstWhere((item) => item?.id == contextId, orElse: () => null);
      if (artist != null) {
        EntityContextMenus.showArtistMenu(
          context,
          artist: artist,
          globalPosition: globalPosition,
        );
      }
    }
  }
}

class _TrackArtwork extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;

  const _TrackArtwork({required this.url, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: (width == null && height == null)
          ? SizedBox.expand(child: _buildImage())
          : SizedBox(
              width: width ?? height,
              height: height ?? width,
              child: _buildImage(),
            ),
    );
  }

  Widget _buildImage() {
    return url.isEmpty
        ? Container(
            color: Colors.grey[850],
            child: const Icon(Icons.music_note),
          )
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            placeholder: (context, url) => Container(color: Colors.grey[850]),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[850],
              child: const Icon(Icons.music_note),
            ),
          );
  }
}

class _CanvasVideo extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final String fallbackUrl;

  const _CanvasVideo({
    required this.url,
    this.width,
    this.height,
    required this.fallbackUrl,
  });

  @override
  State<_CanvasVideo> createState() => _CanvasVideoState();
}

class _CanvasVideoState extends State<_CanvasVideo> {
  VideoPlayerController? _controller;
  bool _initFailed = false;
  bool? _lastShouldPlay;

  // Whether the "freeze while unfocused" behavior is turned on for this
  // widget, per the user's preference. Kept in sync from build().
  bool _freezeWhenUnfocused = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _CanvasVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _initialize();
    }
  }

  @override
  void dispose() {
    AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    _disposeController();
    super.dispose();
  }

  void _handleFocusChanged() {
    // Re-evaluate play/pause immediately: no need to wait for a rebuild
    // driven by the playback provider to freeze/resume this animated canvas.
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    final shouldPlay =
        context.read<PlaybackCoordinator>().effectiveIsPlaying &&
        (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    _syncPlayback(controller, shouldPlay);
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      _initFailed = true;
      if (mounted) setState(() {});
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _lastShouldPlay = null;
  }

  void _syncPlayback(VideoPlayerController controller, bool shouldPlay) {
    if (_lastShouldPlay == shouldPlay) return;
    _lastShouldPlay = shouldPlay;
    unawaited(_setPlayback(controller, shouldPlay));
  }

  Future<void> _setPlayback(
    VideoPlayerController controller,
    bool shouldPlay,
  ) async {
    try {
      if (shouldPlay) {
        if (!controller.value.isPlaying) {
          await controller.play();
        }
      } else {
        if (controller.value.isPlaying) {
          await controller.pause();
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIsPlaying = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.effectiveIsPlaying,
    );
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.animatedCanvasSidebar,
      ),
    );
    _freezeWhenUnfocused = freezeWhenUnfocused;
    // Freeze this animated canvas (stop decoding/painting video frames)
    // whenever the app/window is unfocused and the user has enabled that
    // behavior for it, regardless of playback state.
    final shouldPlay =
        effectiveIsPlaying &&
        (!freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    final controller = _controller;
    final hasSize = widget.width != null || widget.height != null;
    if (_initFailed || controller == null || !controller.value.isInitialized) {
      return _TrackArtwork(
        url: widget.fallbackUrl,
        width: widget.width,
        height: widget.height,
      );
    }

    _syncPlayback(controller, shouldPlay);

    final video = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: hasSize
          ? SizedBox(
              width: widget.width ?? widget.height,
              height: widget.height ?? widget.width,
              child: video,
            )
          : SizedBox.expand(child: video),
    );
  }
}

class _CanvasBackground extends StatefulWidget {
  final String url;

  const _CanvasBackground({required this.url});

  @override
  State<_CanvasBackground> createState() => _CanvasBackgroundState();
}

class _CanvasBackgroundState extends State<_CanvasBackground> {
  VideoPlayerController? _controller;
  bool _initFailed = false;
  bool? _lastShouldPlay;

  // Whether the "freeze while unfocused" behavior is turned on for this
  // widget, per the user's preference. Kept in sync from build().
  bool _freezeWhenUnfocused = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _CanvasBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _initialize();
    }
  }

  @override
  void dispose() {
    AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    _disposeController();
    super.dispose();
  }

  void _handleFocusChanged() {
    // Re-evaluate play/pause immediately: no need to wait for a rebuild
    // driven by the playback provider to freeze/resume this animated canvas.
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    final shouldPlay =
        context.read<PlaybackCoordinator>().effectiveIsPlaying &&
        (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    _syncPlayback(controller, shouldPlay);
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      _initFailed = true;
      if (mounted) setState(() {});
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _lastShouldPlay = null;
  }

  void _syncPlayback(VideoPlayerController controller, bool shouldPlay) {
    if (_lastShouldPlay == shouldPlay) return;
    _lastShouldPlay = shouldPlay;
    unawaited(_setPlayback(controller, shouldPlay));
  }

  Future<void> _setPlayback(
    VideoPlayerController controller,
    bool shouldPlay,
  ) async {
    try {
      if (shouldPlay) {
        if (!controller.value.isPlaying) {
          await controller.play();
        }
      } else {
        if (controller.value.isPlaying) {
          await controller.pause();
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIsPlaying = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.effectiveIsPlaying,
    );
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.animatedCanvasSidebar,
      ),
    );
    _freezeWhenUnfocused = freezeWhenUnfocused;
    // Freeze this animated canvas (stop decoding/painting video frames)
    // whenever the app/window is unfocused and the user has enabled that
    // behavior for it, regardless of playback state.
    final shouldPlay =
        effectiveIsPlaying &&
        (!freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    final controller = _controller;
    if (_initFailed || controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    _syncPlayback(controller, shouldPlay);

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.35)),
      ],
    );
  }
}

class _BlankArtwork extends StatelessWidget {
  const _BlankArtwork();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

class _ArtistInfoCard extends StatefulWidget {
  const _ArtistInfoCard();

  @override
  State<_ArtistInfoCard> createState() => _ArtistInfoCardState();
}

class _ArtistInfoCardState extends State<_ArtistInfoCard> {
  Future<GenericArtist?>? _artistFuture;
  String? _artistId;
  String? _trackId;
  bool _wasAuthenticated = false;

  @override
  Widget build(BuildContext context) {
    return Selector2<WispAudioHandler, SpotifyInternalProvider, (GenericSong?, bool)>(
      selector: (context, player, spotifyInternal) => (
        player.currentTrack,
        spotifyInternal.isAuthenticated,
      ),
      builder: (context, data, child) {
        final (track, isAuthenticated) = data;
        final spotifyInternal = context.read<SpotifyInternalProvider>();
        final artist = track?.artists.isNotEmpty == true
            ? track!.artists.first
            : null;

        final shouldRefetch =
            artist != null &&
            (artist.id != _artistId ||
                track?.id != _trackId ||
                (isAuthenticated && !_wasAuthenticated));

        if (shouldRefetch) {
          _artistId = artist.id;
          _trackId = track?.id;
          _artistFuture = _loadArtist(spotifyInternal, artist, track?.id ?? '');
        }

        _wasAuthenticated = isAuthenticated;

        if (artist == null) {
          return _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'About the artist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'No artist info available',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return FutureBuilder<GenericArtist?>(
          future: _artistFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting ||
                snapshot.connectionState == ConnectionState.active;
            final imageUrl = data?.thumbnailUrl.isNotEmpty == true
                ? data!.thumbnailUrl
                : artist.thumbnailUrl;

            return _SectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: imageUrl.isEmpty
                              ? Container(color: Colors.grey[850])
                              : CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(color: Colors.grey[850]),
                                ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Text(
                          'About the artist',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HoverUnderline(
                          onTap: () => _openArtist(data, artist),
                          onSecondaryTapDown: (details) {
                            final menuArtist = data != null
                                ? GenericSimpleArtist(
                                    id: data.id,
                                    source: data.source,
                                    name: data.name,
                                    thumbnailUrl: data.thumbnailUrl,
                                  )
                                : artist;
                            EntityContextMenus.showArtistMenu(
                              context,
                              artist: menuArtist,
                              globalPosition: details.globalPosition,
                            );
                          },
                          builder: (isHovering) => Text(
                            data?.name ?? artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              decoration: isHovering
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isLoading
                              ? 'Loading artist info…'
                              : data == null
                              ? 'Artist info unavailable'
                              : data.monthlyListeners != null
                              ? '${_formatNumber(data.monthlyListeners!)} monthly listeners'
                              : '${_formatNumber(data.followers)} followers',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                        if (data != null) ...[
                          if (data.description != null) ...[
                            const SizedBox(height: 6),
                            buildParsedText(
                              context,
                              data.description!,
                              maxLines: 3,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<GenericArtist?> _loadArtist(
    SpotifyInternalProvider spotifyInternal,
    GenericSimpleArtist artist,
    String trackId,
  ) async {
    try {
      if (!spotifyInternal.isAuthenticated) {
        await spotifyInternal.checkAuthState();
      }
      if (!spotifyInternal.isAuthenticated) {
        return null;
      }
      if (trackId.isEmpty) {
        return await spotifyInternal.getArtistInfo(artist.id);
      }
      return await spotifyInternal.getNpvArtistInfo(artist.id, trackId);
    } catch (_) {
      throw Exception('Failed to load artist info');
    }
  }

  String _formatNumber(int value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  void _openArtist(GenericArtist? data, GenericSimpleArtist fallback) {
    final artist = data == null
        ? fallback
        : GenericSimpleArtist(
            id: data.id,
            source: data.source,
            name: data.name,
            thumbnailUrl: data.thumbnailUrl,
          );

    AppNavigation.instance.openArtist(
      context,
      artistId: artist.id,
      initialArtist: artist,
    );
  }
}

Color _tintedDominantColor(Color color, {double blend = 0.4}) {
  final hsl = HSLColor.fromColor(color);
  final overlay = hsl
      .withLightness(0.22)
      .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
      .toColor();
  return Color.lerp(color, overlay, blend) ?? color;
}

class _LyricsPreviewCard extends StatefulWidget {
  const _LyricsPreviewCard();

  @override
  State<_LyricsPreviewCard> createState() => _LyricsPreviewCardState();
}

class _LyricsPreviewCardState extends State<_LyricsPreviewCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final track = context.select<WispAudioHandler, GenericSong?>(
      (p) => p.currentTrack,
    );

    if (track == null) {
      return _SectionCard(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Lyrics Preview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Play a song to see lyrics',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final bgColor = _tintedDominantColor(Theme.of(context).colorScheme.primary);
    final btnColor = Theme.of(context).colorScheme.primary;

    return Consumer<LyricsProvider>(
      builder: (context, lyricsProvider, child) {
        final state = lyricsProvider.getState(track, LyricsSyncMode.line);
        if (!state.isLoading && state.lyrics == null && state.error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            lyricsProvider.ensureLyrics(track, LyricsSyncMode.line);
          });
        }

        lyricsProvider.ensureDelayLoaded(track.id);

        final lyrics = state.lyrics;
        if (!state.isLoading && (lyrics == null || lyrics.lines.isEmpty)) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<Route<dynamic>?>(
          valueListenable: NavigationHistory.instance.currentRoute,
          builder: (context, route, child) {
            return MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: _SectionCard(
                backgroundColor: bgColor,
                child: SizedBox(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lyrics Preview',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (state.isLoading && lyrics == null)
                            const Text(
                              'Loading lyrics…',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            )
                          else
                            Selector<PlaybackCoordinator, int>(
                              selector: (context, coordinator) {
                                final posMs = coordinator
                                    .effectiveThrottledPosition
                                    .inMilliseconds;
                                final delaySeconds = lyricsProvider
                                    .getDelaySecondsCached(track.id);
                                final delayMs = (delaySeconds * 1000).round();
                                final effectivePosition =
                                    posMs - delayMs < 0 ? 0 : posMs - delayMs;
                                final lines = nonEmptyLyricsLines(lyrics!.lines);
                                if (lines.isEmpty ||
                                    lyrics.syncMode != LyricsSyncMode.line) {
                                  return 0;
                                }
                                final timing = resolveSyncedLyricsTiming(
                                  lines,
                                  effectivePosition,
                                );
                                return timing.activeIndex >= 0
                                    ? timing.activeIndex
                                    : (timing.nextIndex ??
                                        timing.previousIndex ??
                                        0);
                              },
                              builder: (context, startIndex, child) {
                                // Freeze the scrolling lyrics preview while
                                // the app/window is unfocused instead of
                                // rebuilding it on every position tick.
                                return FocusFreezeBuilder<int>(
                                  value: startIndex,
                                  builder: (context, startIndex) {
                                    final lines =
                                        nonEmptyLyricsLines(lyrics!.lines);
                                    final previewLines =
                                        lyrics.syncMode != LyricsSyncMode.line
                                            ? lines.take(3).toList()
                                            : lines
                                                .skip(startIndex)
                                                .take(3)
                                                .toList();
                                    return AnimatedLyricsPreviewList(
                                      lines: previewLines,
                                      resetKey: track.id,
                                      textStyle: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          SizedBox(height: 4),
                          Text(
                            lyrics == null
                                ? ''
                                : 'Lyrics provided by ${lyrics.provider.label}',
                            style: TextStyle(
                              color: Colors.grey[200],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: (_hovering && lyrics != null) ? 1.0 : 0.0,
                          child: IgnorePointer(
                            ignoring: !_hovering || lyrics == null,
                            child: SizedBox(
                              width: 38,
                              height: 38,
                              child: FloatingActionButton(
                                heroTag: null,
                                mini: true,
                                mouseCursor: SystemMouseCursors.click,
                                backgroundColor: btnColor,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                onPressed: lyrics == null
                                    ? null
                                    : () {
                                        _openLyrics(context);
                                      },
                                child: const Icon(
                                  Icons.lyrics_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openLyrics(BuildContext context) {
    AppNavigation.instance.openLyrics();
  }
}

class _QueuePreviewCard extends StatefulWidget {
  const _QueuePreviewCard();

  @override
  State<_QueuePreviewCard> createState() => _QueuePreviewCardState();
}

class _QueuePreviewCardState extends State<_QueuePreviewCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Selector<WispAudioHandler, _QueuePreviewData>(
      selector: (context, player) => _QueuePreviewData(
        queueLength: player.queueTracks.length,
        currentIndex: player.currentIndex,
        currentTrackId: player.currentTrack?.id,
      ),
      builder: (context, data, child) {
        final player = context.read<WispAudioHandler>();
        final queue = player.queueTracks;
        final currentIndex = data.currentIndex;
        final upcoming = currentIndex + 1 < queue.length
            ? queue.sublist(currentIndex + 1)
            : <GenericSong>[];

        final btnColor = Theme.of(context).colorScheme.primary;

        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: _SectionCard(
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Up next',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (upcoming.isEmpty)
                        const Text(
                          'Queue is empty',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      else
                        Column(
                          children: upcoming.take(4).map((track) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  _TrackArtwork(
                                    url: track.thumbnailUrl,
                                    width: 36,
                                    height: 36,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          track.artists
                                              .map((a) => a.name)
                                              .join(', '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: (_hovering && upcoming.isNotEmpty) ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_hovering || upcoming.isEmpty,
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: FloatingActionButton(
                            heroTag: null,
                            mini: true,
                            mouseCursor: SystemMouseCursors.click,
                            backgroundColor: btnColor,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            onPressed: upcoming.isEmpty
                                ? null
                                : () => _openQueue(),
                            child: const Icon(Icons.queue_music, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openQueue() {
    AppNavigation.instance.openQueue();
  }
}


class _NowPlayingData {
  final GenericSong? track;
  final String? playbackContextName;
  final PlaybackContextType? playbackContextType;
  final String? playbackContextID;

  const _NowPlayingData({
    required this.track,
    required this.playbackContextName,
    required this.playbackContextType,
    required this.playbackContextID,
  });

  @override
  bool operator ==(Object other) =>
      other is _NowPlayingData &&
      other.track?.id == track?.id &&
      other.playbackContextName == playbackContextName &&
      other.playbackContextType == playbackContextType &&
      other.playbackContextID == playbackContextID;

  @override
  int get hashCode => Object.hash(
    track?.id,
    playbackContextName,
    playbackContextType,
    playbackContextID,
  );
}

class _QueuePreviewData {
  final int queueLength;
  final int currentIndex;
  final String? currentTrackId;

  const _QueuePreviewData({
    required this.queueLength,
    required this.currentIndex,
    required this.currentTrackId,
  });

  @override
  bool operator ==(Object other) =>
      other is _QueuePreviewData &&
      other.queueLength == queueLength &&
      other.currentIndex == currentIndex &&
      other.currentTrackId == currentTrackId;

  @override
  int get hashCode => Object.hash(queueLength, currentIndex, currentTrackId);
}
