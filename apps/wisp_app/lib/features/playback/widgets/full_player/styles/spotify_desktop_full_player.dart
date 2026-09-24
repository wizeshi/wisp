// Copyright © 2026 wizeshi

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/playback/views/lyrics_view.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/shared/widgets/display/sliding_track_background.dart';
import 'package:wisp/features/playback/widgets/player_bar.dart';
import '../components/canvas_video.dart';
import '../components/cover_gradient_container.dart';
import '../components/desktop_lyrics_preview.dart';
import '../components/inline_delay_editor.dart';
import '../components/mobile_artist_info_card.dart';
import 'apple_music_full_player.dart';

enum _SpotifyDisplayMode { artwork, canvas, lyrics, queue }

extension _SpotifyDisplayModeMapping on _SpotifyDisplayMode {
  FullPlayerDesktopMode get appMode {
    switch (this) {
      case _SpotifyDisplayMode.artwork:
        return FullPlayerDesktopMode.artwork;
      case _SpotifyDisplayMode.canvas:
        return FullPlayerDesktopMode.canvas;
      case _SpotifyDisplayMode.lyrics:
        return FullPlayerDesktopMode.lyrics;
      case _SpotifyDisplayMode.queue:
        return FullPlayerDesktopMode.queue;
    }
  }
}

/// Desktop state holder for Spotify fullscreen player
class _SpotifyDesktopFullScreenState extends ChangeNotifier {
  _SpotifyDisplayMode _preferredMode = _SpotifyDisplayMode.artwork;
  bool _canvasAvailable = false;
  bool _topControlsVisible = true;
  int _lastSkipDirection = 0; // -1 for backward, 1 for forward, 0 for none
  String? _lastTrackId;

  _SpotifyDisplayMode get preferredMode => _preferredMode;
  bool get canvasAvailable => _canvasAvailable;
  bool get topControlsVisible => _topControlsVisible;
  int get lastSkipDirection => _lastSkipDirection;

  void setPreferredMode(_SpotifyDisplayMode mode) {
    if (_preferredMode != mode) {
      final previousMode = _preferredMode;
      _preferredMode = mode;
      AppNavigation.instance.setFullPlayerDesktopMode(
        mode.appMode,
        rememberPrevious: previousMode != mode,
      );
      AppNavigation.instance.fullPlayerLyricsMode.value =
          mode == _SpotifyDisplayMode.lyrics;
      if (mode == _SpotifyDisplayMode.queue && !_topControlsVisible) {
        _topControlsVisible = true;
      } else if (mode != _SpotifyDisplayMode.lyrics && !_topControlsVisible) {
        _topControlsVisible = true;
      }
      notifyListeners();
    } else {
      AppNavigation.instance.setFullPlayerDesktopMode(
        mode.appMode,
        rememberPrevious: false,
      );
      AppNavigation.instance.fullPlayerLyricsMode.value =
          mode == _SpotifyDisplayMode.lyrics;
    }
  }

  void updateCanvasAvailability(bool available) {
    if (_canvasAvailable != available) {
      _canvasAvailable = available;
      notifyListeners();
    }
  }

  void setTopControlsVisible(bool visible) {
    if (_topControlsVisible != visible) {
      _topControlsVisible = visible;
      notifyListeners();
    }
  }

  void recordSkipDirection(String trackId, bool isForward) {
    _lastTrackId = trackId;
    _lastSkipDirection = isForward ? 1 : -1;
  }

  void clearSkipDirection() {
    _lastSkipDirection = 0;
  }

  bool hasTrackChanged(String trackId) {
    return _lastTrackId != trackId;
  }
}

/// Spotify-style desktop fullscreen player with animated transitions
class SpotifyDesktopFullScreenPlayer extends StatefulWidget {
  const SpotifyDesktopFullScreenPlayer({super.key});

  @override
  State<SpotifyDesktopFullScreenPlayer> createState() =>
      _SpotifyDesktopFullScreenPlayerState();
}

class _SpotifyDesktopFullScreenPlayerState
    extends State<SpotifyDesktopFullScreenPlayer>
    with SingleTickerProviderStateMixin {
  late final _SpotifyDesktopFullScreenState _desktopState;
  late AnimationController _colorTransitionController;
  Timer? _inactivityTimer;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _desktopState = _SpotifyDesktopFullScreenState();
    _colorTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _scrollController = ScrollController();
    AppNavigation.instance.fullPlayerDesktopMode.addListener(
      _handleExternalDesktopModeChange,
    );
    _startInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _colorTransitionController.dispose();
    AppNavigation.instance.fullPlayerDesktopMode.removeListener(
      _handleExternalDesktopModeChange,
    );
    _scrollController.dispose();
    _desktopState.dispose();
    super.dispose();
  }

  void _handleExternalDesktopModeChange() {
    final appMode = AppNavigation.instance.fullPlayerDesktopMode.value;
    final desiredMode = switch (appMode) {
      FullPlayerDesktopMode.artwork => _SpotifyDisplayMode.artwork,
      FullPlayerDesktopMode.canvas => _SpotifyDisplayMode.canvas,
      FullPlayerDesktopMode.lyrics => _SpotifyDisplayMode.lyrics,
      FullPlayerDesktopMode.queue => _SpotifyDisplayMode.queue,
    };
    if (_desktopState.preferredMode != desiredMode) {
      _desktopState.setPreferredMode(desiredMode);
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        if (_desktopState.preferredMode == _SpotifyDisplayMode.queue) {
          return;
        }
        // Auto-hide controls unless the user is viewing the cards area.
        // Determine if we're in the cards area by checking the scroll offset
        // relative to the viewport. If the offset is beyond ~55% of the
        // viewport height we assume the user is viewing cards and won't
        // auto-hide.
        var inCardsArea = false;
        if (_scrollController.hasClients &&
            _scrollController.position.viewportDimension > 0) {
          final thresh = _scrollController.position.viewportDimension * 0.55;
          inCardsArea = _scrollController.offset > thresh;
        }

        if (!inCardsArea) {
          setState(() {
            _desktopState.setTopControlsVisible(false);
          });
        }
      }
    });
  }

  void _resetInactivityTimer() {
    if (!_desktopState.topControlsVisible) {
      setState(() {
        _desktopState.setTopControlsVisible(true);
      });
    }
    _startInactivityTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<global_audio_player.WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
        final currentTrack = player.currentTrack;
        if (currentTrack == null) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: const Center(
              child: Text(
                'No track playing',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          );
        }

        // Update canvas availability
        final useCanvas = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.animatedCanvasEnabled,
        );
        final spotifyInternal = context.read<SpotifyInternalProvider>();
        final canUseCanvas =
            useCanvas &&
            (currentTrack.source == SongSource.spotifyInternal ||
                currentTrack.source == SongSource.spotify);

        return ChangeNotifierProvider<_SpotifyDesktopFullScreenState>.value(
          value: _desktopState,
          child: MouseRegion(
            onEnter: (_) => _resetInactivityTimer(),
            onHover: (_) => _resetInactivityTimer(),
            child: _SpotifyDesktopFullScreenBody(
              player: player,
              lyricsProvider: lyricsProvider,
              currentTrack: currentTrack,
              canUseCanvas: canUseCanvas,
              spotifyInternal: spotifyInternal,
              scrollController: _scrollController,
            ),
          ),
        );
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppNavigation.instance.setFullPlayerDesktopMode(
      _desktopState.preferredMode.appMode,
      rememberPrevious: false,
    );
    AppNavigation.instance.fullPlayerLyricsMode.value =
        _desktopState.preferredMode == _SpotifyDisplayMode.lyrics;
  }
}

class _SpotifyDesktopFullScreenBody extends StatelessWidget {
  final global_audio_player.WispAudioHandler player;
  final LyricsProvider lyricsProvider;
  final dynamic currentTrack;
  final bool canUseCanvas;
  final SpotifyInternalProvider spotifyInternal;
  final ScrollController scrollController;

  const _SpotifyDesktopFullScreenBody({
    required this.player,
    required this.lyricsProvider,
    required this.currentTrack,
    required this.canUseCanvas,
    required this.spotifyInternal,
    required this.scrollController,
  });

  Widget _buildSlidingBackground({
    required String? trackId,
    required int queueIndex,
    required Widget child,
  }) {
    return SlidingTrackBackground(
      transitionToken: player.trackChangeToken,
      trackId: trackId,
      queueIndex: queueIndex,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = currentTrack?.thumbnailUrl ?? '';
    final dominantColor = tintedDominantColor(
      Theme.of(context).colorScheme.primary,
    );
    final song = currentTrack as GenericSong?;
    final trackId = song?.id;
    final canvasUrlFuture = canUseCanvas && trackId != null
        ? spotifyInternal.getCanvasUrl(trackId)
        : Future<String?>.value(null);

    return Consumer<_SpotifyDesktopFullScreenState>(
      builder: (context, desktopState, _) {
        return FutureBuilder<String?>(
          future: canvasUrlFuture,
          builder: (context, snapshot) {
            final resolvedCanvasUrl =
                (snapshot.data != null && snapshot.data!.isNotEmpty)
                ? snapshot.data
                : null;
            final hasCanvas = canUseCanvas && resolvedCanvasUrl != null;

            if (!hasCanvas &&
                desktopState.preferredMode == _SpotifyDisplayMode.canvas) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                desktopState.setPreferredMode(_SpotifyDisplayMode.artwork);
              });
            }

            const topBarHeight = 66.0;
            const bottomBarHeight = 90.0;
            final controlsVisible = desktopState.topControlsVisible;
            final showCards =
                desktopState.preferredMode != _SpotifyDisplayMode.lyrics;
            final reservedBottomInset = showCards && controlsVisible
                ? bottomBarHeight
                : 0.0;

            final background = Stack(
              fit: StackFit.expand,
              children: [
                Container(color: dominantColor),
                if (showCards)
                  AnimatedOpacity(
                    opacity: controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: _buildBackgroundGradient(
                      dominantColor,
                      desktopState.preferredMode,
                    ),
                  ),
              ],
            );

            return Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  _buildSlidingBackground(
                    trackId: currentTrack?.id,
                    queueIndex: player.currentIndex,
                    child: background,
                  ),

                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: showCards ? topBarHeight : 0,
                        // when cards are shown reserve space for the bottom bar;
                        // when in lyrics mode allow the lyrics to extend under
                        // the player bar (the player overlays in lyrics mode).
                        bottom: reservedBottomInset,
                      ),
                      child: showCards
                          ? _buildScrollableVisualAndCards(
                              context,
                              imageUrl,
                              desktopState,
                              resolvedCanvasUrl,
                              player.trackChangeToken,
                              player.currentIndex,
                              const Color(0xFF0F0F0F),
                            )
                          : _buildLyricsMode(context),
                    ),
                  ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopBar(
                      context,
                      player,
                      desktopState,
                      hasCanvas,
                    ),
                  ),

                  if (song != null)
                    Positioned(
                      left: 32,
                      bottom: 32,
                      child: AnimatedOpacity(
                        opacity: controlsVisible ? 0 : 1,
                        duration: !controlsVisible
                            ? Duration(milliseconds: 750)
                            : Duration(milliseconds: 200),
                        curve: Easing.emphasizedAccelerate,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              song.artists.map((a) => a.name).join(', '),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildAnimatedBottomPlayerBar(context, desktopState),
                  ),

                  // Small lyrics delay control (inline TextField) shown in lyrics mode.
                  if (desktopState.preferredMode == _SpotifyDisplayMode.lyrics)
                    Positioned(
                      right: 24,
                      bottom: bottomBarHeight + 12,
                      child: InlineDelayEditor(
                        lyricsProvider: lyricsProvider,
                        trackId: currentTrack.id,
                        visible: desktopState.topControlsVisible,
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

  Widget _buildBackgroundGradient(
    Color dominantColor,
    _SpotifyDisplayMode mode,
  ) {
    if (mode == _SpotifyDisplayMode.lyrics) {
      return Container(color: Colors.black);
    }
    if (mode == _SpotifyDisplayMode.queue) {
      return Container(color: const Color(0xFF0F0F0F));
    }

    // Match the brighter, more alive tint from LyricsView and blend it gently
    // into the cards' dark gray background.
    final start = tintedDominantColor(dominantColor, blend: 0.26);
    final mid = const Color(0xFF0F0F0F);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [start, start, mid],
          stops: const [0.0, 0.86, 1.0],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    _SpotifyDesktopFullScreenState desktopState,
    bool hasCanvas,
  ) {
    final visible = desktopState.topControlsVisible;
    final mode = desktopState.preferredMode;
    final pageLabel = switch (mode) {
      _SpotifyDisplayMode.lyrics => 'Singing along to',
      _SpotifyDisplayMode.queue => 'Next up from',
      _SpotifyDisplayMode.artwork ||
      _SpotifyDisplayMode.canvas => 'Listening to',
    };
    final contextName = player.playbackContext?.name ?? 'Now Playing';

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 240),
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 240),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: mode == _SpotifyDisplayMode.queue
                ? const Color(0xFF0F0F0F)
                : null,
            gradient: mode == _SpotifyDisplayMode.queue
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      pageLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contextName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              // Right: Mode selectors and menu
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModeToggleButton(
                    context,
                    'Artwork',
                    Icons.album,
                    _SpotifyDisplayMode.artwork,
                    desktopState,
                    enabled: true,
                  ),
                  const SizedBox(width: 8),
                  _buildModeToggleButton(
                    context,
                    'Canvas',
                    Icons.image,
                    _SpotifyDisplayMode.canvas,
                    desktopState,
                    enabled: hasCanvas,
                  ),
                  const SizedBox(width: 8),
                  _buildModeToggleButton(
                    context,
                    'Lyrics',
                    Icons.music_note,
                    _SpotifyDisplayMode.lyrics,
                    desktopState,
                    enabled: true,
                  ),
                  const SizedBox(width: 8),
                  _buildModeToggleButton(
                    context,
                    'Queue',
                    Icons.queue_music,
                    _SpotifyDisplayMode.queue,
                    desktopState,
                    enabled: true,
                  ),
                  const SizedBox(width: 16),
                  Builder(
                    builder: (buttonContext) {
                      return IconButton(
                        icon: const Icon(Icons.more_vert),
                        color: Colors.white70,
                        onPressed: () => _openTrackMenu(buttonContext),
                        tooltip: 'More options',
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.fullscreen_exit),
                    color: Colors.white70,
                    onPressed: () =>
                        unawaited(AppNavigation.instance.closeFullPlayer()),
                    tooltip: 'Exit fullscreen',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggleButton(
    BuildContext context,
    String label,
    IconData icon,
    _SpotifyDisplayMode mode,
    _SpotifyDesktopFullScreenState desktopState, {
    required bool enabled,
  }) {
    final isSelected = desktopState.preferredMode == mode;
    final color = isSelected ? Colors.white : Colors.white54;

    return Tooltip(
      message: !enabled && mode == _SpotifyDisplayMode.canvas
          ? 'Not available for this track'
          : label,
      child: IconButton(
        icon: Icon(icon),
        color: enabled ? color : Colors.grey[700],
        onPressed: enabled
            ? () {
                desktopState.setPreferredMode(mode);
              }
            : null,
      ),
    );
  }

  Widget _buildCenterContent(
    BuildContext context,
    String imageUrl,
    _SpotifyDesktopFullScreenState desktopState,
    String? canvasUrl,
    int transitionToken,
    int queueIndex,
    Color queueBackgroundColor,
  ) {
    switch (desktopState.preferredMode) {
      case _SpotifyDisplayMode.artwork:
        return SlidingTrackBackground(
          transitionToken: transitionToken,
          trackId: imageUrl,
          queueIndex: queueIndex,
          child: _buildArtworkMode(imageUrl),
        );

      case _SpotifyDisplayMode.canvas:
        final visualChild = canvasUrl != null
            ? _buildCanvasMode(canvasUrl, imageUrl)
            : _buildArtworkMode(imageUrl);
        return SlidingTrackBackground(
          transitionToken: transitionToken,
          trackId: canvasUrl ?? imageUrl,
          queueIndex: queueIndex,
          child: visualChild,
        );

      case _SpotifyDisplayMode.lyrics:
        return _buildLyricsMode(context);

      case _SpotifyDisplayMode.queue:
        return QueueView(
          contentOnly: true,
          hideHeader: true,
          backgroundColor: queueBackgroundColor,
        );
    }
  }

  Widget _buildScrollableVisualAndCards(
    BuildContext context,
    String imageUrl,
    _SpotifyDesktopFullScreenState desktopState,
    String? canvasUrl,
    int transitionToken,
    int queueIndex,
    Color queueBackgroundColor,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              final desktopState = context
                  .read<_SpotifyDesktopFullScreenState>();
              if (!desktopState.topControlsVisible) {
                desktopState.setTopControlsVisible(true);
              }
              // Reset the inactivity timer on user scroll so controls stay visible.
              final parentState = context
                  .findAncestorStateOfType<
                    _SpotifyDesktopFullScreenPlayerState
                  >();
              parentState?._resetInactivityTimer();
            }
            return false;
          },
          child: CustomScrollView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: _buildCenterContent(
                    context,
                    imageUrl,
                    desktopState,
                    canvasUrl,
                    transitionToken,
                    queueIndex,
                    queueBackgroundColor,
                  ),
                ),
              ),

              // subtle transition gradient between the main visual and the cards
              SliverToBoxAdapter(
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, const Color(0xFF0F0F0F)],
                      stops: const [0.0, 0.95],
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFF0F0F0F),
                  child: _buildCardsSection(context, desktopState),
                ),
              ),
              // extra padding below cards to give breathing room; keep same
              // background color so the visual remains seamless.
              SliverToBoxAdapter(
                child: Container(height: 20, color: const Color(0xFF0F0F0F)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtworkMode(String imageUrl) {
    return _buildMainVisualViewport(
      aspectRatio: 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey[900],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey[900],
            child: const Icon(Icons.music_note, size: 120, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasMode(String canvasUrl, String fallbackUrl) {
    // Canvas is a portrait video — preserve a portrait aspect ratio so width scales
    return _buildMainVisualViewport(
      aspectRatio: 9.0 / 16.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CanvasVideo(url: canvasUrl, fallbackUrl: fallbackUrl),
        ),
      ),
    );
  }

  Widget _buildMainVisualViewport({
    required Widget child,
    double aspectRatio = 1.0,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxHeight * 0.56).clamp(
          260.0,
          constraints.maxWidth * 0.68,
        );
        final width = (height * aspectRatio).clamp(
          160.0,
          constraints.maxWidth * 0.9,
        );
        return Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 36,
                  spreadRadius: -10,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: SizedBox(width: width, height: height, child: child),
          ),
        );
      },
    );
  }

  Widget _buildLyricsMode(BuildContext context) {
    return const LyricsView(hideHeader: true);
  }

  Widget _buildCardsSection(
    BuildContext context,
    _SpotifyDesktopFullScreenState desktopState,
  ) {
    final song = currentTrack as GenericSong?;
    final artist = song?.artists.isNotEmpty == true
        ? song!.artists.first
        : null;
    final queue = player.queueTracks;
    final nextIndex = player.currentIndex + 1;
    final nextTrack = nextIndex >= 0 && nextIndex < queue.length
        ? queue[nextIndex]
        : null;
    final lyricsProvider = context.read<LyricsProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _buildDesktopSpotifyCard(
                  title: 'Lyrics Preview',
                  trailing: Icons.lyrics_outlined,
                  onTrailingPressed: () =>
                      desktopState.setPreferredMode(_SpotifyDisplayMode.lyrics),
                  background: tintedDominantColor(
                    Theme.of(context).colorScheme.primary,
                  ),
                  child: DesktopLyricsPreviewWidget(
                    player: player,
                    lyricsProvider: lyricsProvider,
                    bgColor: tintedDominantColor(
                      Theme.of(context).colorScheme.primary,
                    ),
                    btnColor: Colors.white,
                    inCard: true,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDesktopSpotifyCard(
                  title: 'Next in queue',
                  trailing: Icons.queue_music,
                  background: const Color(0xFF1A1A1A).withValues(alpha: 0.85),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: CachedNetworkImage(
                            imageUrl: nextTrack?.thumbnailUrl ?? '',
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                Container(color: Colors.grey[800]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nextTrack?.title ?? 'Queue is empty',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    transitionDuration: Duration.zero,
                                    reverseTransitionDuration: Duration.zero,
                                    settings: const RouteSettings(
                                      name: '/queue',
                                    ),
                                    pageBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => const QueueView(),
                                  ),
                                );
                              },
                              child: Text(
                                nextTrack == null
                                    ? 'Open queue'
                                    : (nextTrack.artists.isNotEmpty
                                          ? nextTrack.artists.first.name
                                          : 'Unknown artist'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[350],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: [
                if (artist != null)
                  MobileArtistInfoCard(artist: artist, trackId: song?.id)
                else
                  _buildDesktopSpotifyCard(
                    title: 'About the artist',
                    trailing: Icons.person_outline,
                    child: const Text(
                      'No artist info available.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSpotifyCard({
    required String title,
    required IconData trailing,
    required Widget child,
    VoidCallback? onTrailingPressed,
    Color? background,
  }) {
    final bg = background ?? const Color(0xFF0F0F0F).withValues(alpha: 0.85);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              onTrailingPressed != null
                  ? IconButton(
                      icon: Icon(trailing, color: Colors.white70, size: 20),
                      onPressed: onTrailingPressed,
                      splashRadius: 20,
                    )
                  : Icon(trailing, color: Colors.white70, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildBottomPlayerBar(BuildContext context) {
    return const WispPlayerBar();
  }

  Widget _buildAnimatedBottomPlayerBar(
    BuildContext context,
    _SpotifyDesktopFullScreenState desktopState,
  ) {
    final visible = desktopState.topControlsVisible;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: _buildBottomPlayerBar(context),
        ),
      ),
    );
  }

  void _openTrackMenu(BuildContext context) {
    final currentTrack_ = currentTrack as GenericSong?;
    if (currentTrack_ == null) return;

    Rect? anchorRect;
    final overlayState = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    final buttonBox = context.findRenderObject() as RenderBox?;
    if (overlayBox != null && buttonBox != null) {
      anchorRect = Rect.fromPoints(
        buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox),
        buttonBox.localToGlobal(
          buttonBox.size.bottomRight(Offset.zero),
          ancestor: overlayBox,
        ),
      );
    }

    unawaited(
      AppleMusicFullScreenPlayer.showTrackMenuWithCanvasToggle(
        context,
        track: currentTrack_,
        anchorRect: anchorRect,
      ),
    );
  }
}
