import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';

import '../models/metadata_models.dart';
import '../services/wisp_audio_handler.dart';
import '../providers/lyrics/provider.dart';
import '../providers/connect/connect_session_provider.dart';
import '../providers/library/library_state.dart';
import '../providers/navigation_state.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/theme/cover_art_palette_provider.dart';
import '../services/app_navigation.dart';
import '../services/navigation_history.dart';
import '../views/list_detail.dart';
import 'animated_lyrics_preview.dart';
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

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHoveringSidebar = true),
        onExit: (_) => setState(() => _isHoveringSidebar = false),
        child: Row(
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
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _NowPlayingCard(
                            showHoverControls: _isHoveringSidebar,
                          ),
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
        child: SizedBox(
          width: 6,
          child: Align(
            alignment: Alignment.centerLeft,
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
    return Selector<WispAudioHandler, _NowPlayingData>(
      selector: (context, player) => _NowPlayingData(
        track: player.currentTrack,
        playbackContextName: player.playbackContextName,
        playbackContextType: player.playbackContextType,
        playbackContextID: player.playbackContextID,
      ),
      builder: (context, data, child) {
        final useCanvas = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.animatedCanvasEnabled,
        );
        final libraryState = context.read<LibraryState>();
        final navState = context.read<NavigationState>();
        final track = data.track;
        final resolvedContextName = _resolvePlaybackContextName(
          data,
          libraryState,
        );
        final headerText = resolvedContextName ?? 'Now Playing';
        final canOpenContext =
            data.playbackContextID != null &&
            data.playbackContextID!.isNotEmpty &&
            (data.playbackContextType == 'playlist' ||
                data.playbackContextType == 'album' ||
                data.playbackContextType == 'artist');
        final album = track?.album;
        final canUseCanvas =
            useCanvas &&
            (track?.source == SongSource.spotifyInternal ||
                track?.source == SongSource.spotify);

        Widget buildCard({String? canvasUrl}) {
          final hasCanvas = canvasUrl != null && canvasUrl.isNotEmpty;
          return _SectionCard(
            background: hasCanvas ? _CanvasBackground(url: canvasUrl) : null,
            borderRadius: 0,
            showBottomFade: hasCanvas,
            bottomFadeColor: const Color(0xFF0F0F0F),
            bottomFadeHeight: 28,
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
                                icon: const Icon(Icons.keyboard_arrow_right),
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
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
                                            box.size.bottomRight(Offset.zero),
                                            ancestor: overlay,
                                          ),
                                        );
                                        await EntityContextMenus.showTrackMenu(
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              HoverUnderline(
                                cursor: album != null && album.id.isNotEmpty
                                    ? SystemMouseCursors.click
                                    : SystemMouseCursors.basic,
                                onTap: album != null && album.id.isNotEmpty
                                    ? () => _openAlbum(context, album)
                                    : null,
                                onSecondaryTapDown: (details) {
                                  EntityContextMenus.showTrackMenu(
                                    context,
                                    track: track,
                                    globalPosition: details.globalPosition,
                                  );
                                },
                                builder: (isHovering) => _MarqueeText(
                                  text: track.title,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    decoration: isHovering && album != null
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                              Row(
                                children: track.artists
                                    .map(
                                      (artist) => HoverUnderline(
                                        cursor: SystemMouseCursors.click,
                                        onTap: () =>
                                            _openArtist(context, artist),
                                        onSecondaryTapDown: (details) {
                                          EntityContextMenus.showArtistMenu(
                                            context,
                                            artist: artist,
                                            globalPosition:
                                                details.globalPosition,
                                          );
                                        },
                                        builder: (isHovering) => Text(
                                          artist.name +
                                              (track.artists.last != artist
                                                  ? ', '
                                                  : ''),
                                          style: TextStyle(
                                            color: Colors.grey[200],
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            decoration: isHovering
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                width: showHoverControls ? 28 : 0,
                                child: ClipRect(
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 180),
                                    opacity: showHoverControls ? 1 : 0,
                                    child: IgnorePointer(
                                      ignoring: !showHoverControls,
                                      child: IconButton(
                                        tooltip: 'Share',
                                        icon: const Icon(Icons.share),
                                        iconSize: 18,
                                        visualDensity: VisualDensity.compact,
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
      case 'playlist':
        final playlist = libraryState.playlists
            .cast<GenericPlaylist?>()
            .firstWhere((item) => item?.id == contextId, orElse: () => null);
        final title = playlist?.title.trim();
        return _isUsableContextName(title) ? title : null;
      case 'album':
        final album = libraryState.albums.cast<GenericAlbum?>().firstWhere(
          (item) => item?.id == contextId,
          orElse: () => null,
        );
        final title = album?.title.trim();
        return _isUsableContextName(title) ? title : null;
      case 'artist':
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
    String contextType,
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

    if (contextType == 'playlist') {
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

    if (contextType == 'album') {
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

    if (contextType == 'artist') {
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
            placeholder: (context, url) => Container(color: Colors.grey[850]),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[850],
              child: const Icon(Icons.music_note),
            ),
          );
  }
}

class _TrackArtworkWithCanvas extends StatelessWidget {
  final GenericSong track;
  final double? width;
  final double? height;

  const _TrackArtworkWithCanvas({required this.track, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final useCanvas = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.animatedCanvasEnabled,
    );
    final canUseCanvas =
        useCanvas &&
        (track.source == SongSource.spotifyInternal ||
            track.source == SongSource.spotify);

    if (!canUseCanvas) {
      return _TrackArtwork(
        url: track.thumbnailUrl,
        width: width,
        height: height,
      );
    }

    final spotifyInternal = context.read<SpotifyInternalProvider>();
    return FutureBuilder<String?>(
      future: spotifyInternal.getCanvasUrl(track.id),
      builder: (context, snapshot) {
        final canvasUrl = snapshot.data ?? '';
        if (canvasUrl.isNotEmpty) {
          return _CanvasVideo(
            url: canvasUrl,
            width: width,
            height: height,
            fallbackUrl: track.thumbnailUrl,
          );
        }
        return _TrackArtwork(
          url: track.thumbnailUrl,
          width: width,
          height: height,
        );
      },
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

  @override
  void initState() {
    super.initState();
    _initialize();
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
    _disposeController();
    super.dispose();
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
    final useLinkedState = context.select<ConnectSessionProvider, bool>(
      (connect) => connect.isLinked && connect.isHost,
    );
    final linkedShouldPlay = context.select<ConnectSessionProvider, bool>(
      (connect) => connect.linkedIsPlaying,
    );
    final localShouldPlay = context.select<WispAudioHandler, bool>(
      (player) => player.isPlaying,
    );
    final shouldPlay = useLinkedState ? linkedShouldPlay : localShouldPlay;
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

  @override
  void initState() {
    super.initState();
    _initialize();
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
    _disposeController();
    super.dispose();
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
    final useLinkedState = context.select<ConnectSessionProvider, bool>(
      (connect) => connect.isLinked && connect.isHost,
    );
    final linkedShouldPlay = context.select<ConnectSessionProvider, bool>(
      (connect) => connect.linkedIsPlaying,
    );
    final localShouldPlay = context.select<WispAudioHandler, bool>(
      (player) => player.isPlaying,
    );
    final shouldPlay = useLinkedState ? linkedShouldPlay : localShouldPlay;
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
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
        Container(color: Colors.black.withOpacity(0.35)),
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

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _scrollDistance = 0;
  bool _needsMarquee = false;
  Timer? _pauseTimer;

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _configureController(forceStop: true);
    }
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _configureController({bool forceStop = false}) {
    if (!_needsMarquee || forceStop) {
      _pauseTimer?.cancel();
      _controller?.stop();
      if (_controller != null) {
        _controller!.value = 0;
      }
    }
    if (!_needsMarquee) return;

    _controller ??= AnimationController(vsync: this)
      ..addStatusListener(_handleStatusChange);
    final ms = ((_scrollDistance / 24) * 1000).clamp(2400, 12000).toInt();
    _controller!.duration = Duration(milliseconds: ms);
    _scheduleStart();
  }

  void _handleStatusChange(AnimationStatus status) {
    if (!_needsMarquee) return;
    if (status == AnimationStatus.completed) {
      _pauseThen(() => _controller?.reverse());
    } else if (status == AnimationStatus.dismissed) {
      _pauseThen(() => _controller?.forward());
    }
  }

  void _pauseThen(VoidCallback action) {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !_needsMarquee) return;
      action();
    });
  }

  void _scheduleStart() {
    if (_controller == null) return;
    _pauseTimer?.cancel();
    _controller!.value = 0;
    _pauseThen(() => _controller?.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final maxWidth = constraints.maxWidth;
        final textWidth = textPainter.width;
        final needsMarquee = textWidth > maxWidth;
        const endPadding = 8.0;
        final scrollDistance = (textWidth - maxWidth + endPadding)
            .clamp(0, textWidth)
            .toDouble();

        if (_needsMarquee != needsMarquee ||
            _scrollDistance != scrollDistance) {
          _needsMarquee = needsMarquee;
          _scrollDistance = scrollDistance;
          _configureController();
        }

        if (!needsMarquee) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller ?? const AlwaysStoppedAnimation<double>(0),
            builder: (context, child) {
              final value = _controller?.value ?? 0;
              final dx = -value * _scrollDistance;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        );
      },
    );
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
    return Consumer2<WispAudioHandler, SpotifyInternalProvider>(
      builder: (context, player, spotifyInternal, child) {
        final track = player.currentTrack;
        final artist = track?.artists.isNotEmpty == true
            ? track!.artists.first
            : null;

        final shouldRefetch =
            artist != null &&
            (artist.id != _artistId ||
                track?.id != _trackId ||
                (spotifyInternal.isAuthenticated && !_wasAuthenticated));

        if (shouldRefetch) {
          _artistId = artist.id;
          _trackId = track?.id;
          _artistFuture = _loadArtist(spotifyInternal, artist, track?.id ?? '');
        }

        _wasAuthenticated = spotifyInternal.isAuthenticated;

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
                            Text(
                              data.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
    /* final cached = await spotifyInternal.getCachedArtistInfo(artist.id);
    if (cached != null) return cached; */
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
      /* return cached; */
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

    final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (provider) => provider.palette,
    );
    final bgColor = Theme.of(context).colorScheme.primary;
    final btnColor = HSLColor.fromColor(
      palette?.onPrimaryContainer ?? const Color(0xFF1A1A1A),
    ).withLightness(0.7).withSaturation(1).toColor();

    return Consumer<LyricsProvider>(
      builder: (context, lyricsProvider, child) {
        final state = lyricsProvider.getState(track, LyricsSyncMode.synced);
        if (!state.isLoading && state.lyrics == null && state.error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            lyricsProvider.ensureLyrics(track, LyricsSyncMode.synced);
          });
        }

        lyricsProvider.ensureDelayLoaded(track.id);

        final lyrics = state.lyrics;

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
                          else if (lyrics == null)
                            const Text(
                              'No lyrics found',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            )
                          else
                            Selector2<
                              WispAudioHandler,
                              ConnectSessionProvider,
                              int
                            >(
                              selector: (context, player, connect) {
                                final useHandoffState =
                                    connect.isLinked && connect.isHost;
                                final position = useHandoffState
                                    ? connect.linkedInterpolatedPosition
                                    : player.throttledPosition;
                                return position.inMilliseconds;
                              },
                              builder: (context, positionMs, child) {
                                return AnimatedLyricsPreviewList(
                                  lines: _getPreviewLines(lyrics, positionMs),
                                  resetKey: track.id,
                                  textStyle: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
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

class _QueuePreviewCard extends StatelessWidget {
  const _QueuePreviewCard();

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

        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Up next',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openQueue(),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  track.artists.map((a) => a.name).join(', '),
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
        );
      },
    );
  }

  void _openQueue() {
    AppNavigation.instance.openQueue();
  }
}

class _LyricsPreviewLines extends StatelessWidget {
  final LyricsResult lyrics;
  final String resetKey;

  const _LyricsPreviewLines({required this.lyrics, required this.resetKey});

  @override
  Widget build(BuildContext context) {
    return Selector2<WispAudioHandler, ConnectSessionProvider, int>(
      selector: (context, player, connect) {
        final useHandoffState = connect.isLinked && connect.isHost;
        final position = useHandoffState
            ? connect.linkedInterpolatedPosition
            : player.throttledPosition;
        return position.inMilliseconds;
      },
      builder: (context, positionMs, child) {
        final delaySeconds = context.select<LyricsProvider, double>(
          (provider) => provider.getDelaySecondsCached(resetKey),
        );
        final delayMs = (delaySeconds * 1000).round();
        final adjustedPosition = positionMs - delayMs;
        final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
        final previewLines = _getPreviewLines(lyrics, effectivePosition);
        if (previewLines.isEmpty) {
          return const Text(
            'No lyrics found',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          );
        }

        return AnimatedLyricsPreviewList(
          lines: previewLines,
          resetKey: resetKey,
          maxLines: 2,
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }
}

List<LyricsLine> _getPreviewLines(LyricsResult lyrics, int positionMs) {
  if (lyrics.lines.isEmpty) return const [];
  if (!lyrics.synced) {
    return lyrics.lines.take(3).toList();
  }
  final currentIndex = _findCurrentLineIndex(lyrics.lines, positionMs);
  return lyrics.lines.skip(currentIndex).take(3).toList();
}

int _findCurrentLineIndex(List<LyricsLine> lines, int positionMs) {
  var index = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startTimeMs <= positionMs) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}

class _NowPlayingData {
  final GenericSong? track;
  final String? playbackContextName;
  final String? playbackContextType;
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
