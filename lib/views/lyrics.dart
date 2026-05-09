/// Full-screen lyrics view
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/metadata_models.dart';
import '../widgets/sliding_track_background.dart';
import '../services/wisp_audio_handler.dart';
import '../services/playback/playback_coordinator.dart';
import '../providers/lyrics/provider.dart';
import '../utils/logger.dart';
import '../utils/lyrics_timing.dart';

class LyricsView extends StatefulWidget {
  final bool hideHeader;

  const LyricsView({super.key, this.hideHeader = false});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  List<GlobalKey> _lineKeys = [];
  LyricsSyncMode _syncMode = LyricsSyncMode.synced;
  bool _autoScrollEnabled = true;
  int _currentLineIndex = -1;
  LyricsTimingState? _timingState;
  String? _trackId;
  final TextEditingController _delayController = TextEditingController(
    text: '0',
  );
  double _lyricsDelaySeconds = 0;
  Timer? _positionTimer;
  LyricsResult? _activeLyrics;
  WispAudioHandler? _playerRef;
  bool _syncedLyricsAvailable = true;
  bool _didInitialCenter = false;
  bool _initialCenterScheduled = false;
  int _pendingInitialCenterIndex = -1;
  int _hoveredLineIndex = -1;
  String? _delaySyncTrackId;
  double? _delaySyncValue;

  static const Duration _lineScrollDuration = Duration(milliseconds: 620);

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _scrollController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final visible = _isCurrentLineVisible();
    if (!visible && _autoScrollEnabled) {
      setState(() => _autoScrollEnabled = false);
    } else if (visible && !_autoScrollEnabled) {
      setState(() => _autoScrollEnabled = true);
    }
  }

  bool _isCurrentLineVisible() {
    if (_currentLineIndex < 0 || _currentLineIndex >= _lineKeys.length) {
      return true;
    }
    final lineContext = _lineKeys[_currentLineIndex].currentContext;
    final listContext = _listKey.currentContext;
    if (lineContext == null || listContext == null) return true;

    final lineBox = lineContext.findRenderObject() as RenderBox?;
    final listBox = listContext.findRenderObject() as RenderBox?;
    if (lineBox == null || listBox == null) return true;

    final lineOffset = lineBox.localToGlobal(Offset.zero, ancestor: listBox);
    final lineTop = lineOffset.dy;
    final lineBottom = lineTop + lineBox.size.height;

    return lineBottom >= 0 && lineTop <= listBox.size.height;
  }

  void _updateCurrentLine(LyricsResult lyrics, int positionMs) {
    final delayMs = (_lyricsDelaySeconds * 1000).round();
    final adjustedPosition = positionMs - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    if (!lyrics.synced) {
      final newIndex = lyrics.lines.isEmpty ? -1 : 0;
      if (newIndex != _currentLineIndex || _timingState != null) {
        setState(() {
          _currentLineIndex = newIndex;
          _timingState = null;
        });
      }
      return;
    }

    final timing = resolveSyncedLyricsTiming(lyrics.lines, effectivePosition);
    final scrollIndex = _scrollTargetIndex(timing);
    final shouldScroll = _autoScrollEnabled &&
      scrollIndex != null &&
      scrollIndex != _currentLineIndex;
    final targetScrollIndex = scrollIndex ?? timing.activeIndex;

    setState(() {
      _currentLineIndex = timing.activeIndex;
      _timingState = timing;
    });

    if (shouldScroll) {
      _scrollToLine(targetScrollIndex);
    }
  }

  int? _scrollTargetIndex(LyricsTimingState timing) {
    if (timing.activeIndex >= 0) {
      return timing.activeIndex;
    }
    return timing.nextIndex ?? timing.previousIndex;
  }

  void _ensurePositionTimer() {
    if (_positionTimer != null) return;
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final player = _playerRef;
      final lyrics = _activeLyrics;
      if (player == null || lyrics == null) return;
      final positionMs = _effectivePositionMs();
      _updateCurrentLine(lyrics, positionMs);
    });
  }

  int _effectivePositionMs() {
    return context
        .read<PlaybackCoordinator>()
        .effectiveInterpolatedPosition
        .inMilliseconds;
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
    _activeLyrics = null;
    _playerRef = null;
  }

  void _scrollToLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    if (!_scrollController.hasClients) return;

    final lineContext = _lineKeys[index].currentContext;
    final listContext = _listKey.currentContext;
    if (lineContext == null || listContext == null) return;

    final lineBox = lineContext.findRenderObject() as RenderBox?;
    final listBox = listContext.findRenderObject() as RenderBox?;
    if (lineBox == null || listBox == null) return;

    final lineGlobalTop = lineBox.localToGlobal(Offset.zero).dy;
    final viewportGlobalTop = listBox.localToGlobal(Offset.zero).dy;
    final lineTopInViewport = lineGlobalTop - viewportGlobalTop;

    final currentOffset = _scrollController.offset;
    final targetOffset =
        (lineTopInViewport + currentOffset) -
        ((_scrollController.position.viewportDimension - lineBox.size.height) /
            2);

    final clampedOffset = targetOffset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: _lineScrollDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  void _centerCurrentLineOnOpen(WispAudioHandler player, LyricsResult lyrics) {
    if (_didInitialCenter) return;
    final timing = lyrics.synced
      ? resolveSyncedLyricsTiming(lyrics.lines, _effectivePositionMs())
        : null;
    final initialIndex = lyrics.synced ? timing!.activeIndex : 0;
    _currentLineIndex = initialIndex;
    _timingState = timing;
    if (initialIndex < 0) {
      _pendingInitialCenterIndex = timing == null
          ? -1
          : (timing.nextIndex ?? timing.previousIndex ?? -1);
      _didInitialCenter = true;
      return;
    }
    _pendingInitialCenterIndex = initialIndex;
  }

  void _scheduleInitialCenterIfNeeded(
    LyricsResult lyrics,
    double viewportWidth,
    double viewportHeight,
    double horizontalPadding,
    double edgeCenterPadding,
  ) {
    if (_didInitialCenter || _initialCenterScheduled) return;
    final index = _pendingInitialCenterIndex;
    if (index < 0) return;
    if (!_scrollController.hasClients) return;

    _initialCenterScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialCenterScheduled = false;
      if (!mounted || _didInitialCenter) return;
      if (_trackId == null) return;
      if (index >= lyrics.lines.length) return;

      final targetOffset = _estimateInitialScrollOffset(
        lyrics: lyrics,
        index: index,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        horizontalPadding: horizontalPadding,
        edgeCenterPadding: edgeCenterPadding,
      );

      _didInitialCenter = true;
      _pendingInitialCenterIndex = -1;
      _scrollController.jumpTo(
        targetOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  double _estimateInitialScrollOffset({
    required LyricsResult lyrics,
    required int index,
    required double viewportWidth,
    required double viewportHeight,
    required double horizontalPadding,
    required double edgeCenterPadding,
  }) {
    final fontSize = _isDesktop ? 42.0 : 30.0;
    final lineStyle = TextStyle(
      fontSize: fontSize,
      letterSpacing: _isDesktop ? -1.5 : 0.6,
      fontWeight: FontWeight.w700,
      height: _isDesktop ? 1.4 : 1.06,
    );
    final textMaxWidth = (viewportWidth - (horizontalPadding * 2)).clamp(
      120.0,
      viewportWidth,
    );

    double offset = edgeCenterPadding;
    for (var i = 0; i < index; i++) {
      offset += _estimateLyricsLineHeight(
        lyrics.lines[i].content,
        lineStyle,
        textMaxWidth,
      );
    }

    final targetLineHeight = _estimateLyricsLineHeight(
      lyrics.lines[index].content,
      lineStyle,
      textMaxWidth,
    );

    return offset - ((viewportHeight - targetLineHeight) / 2);
  }

  double _estimateLyricsLineHeight(
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    return painter.height + 16.0;
  }

  void _onSyncModeChanged(LyricsSyncMode mode) {
    if (_syncMode == mode) return;
    setState(() {
      _syncMode = mode;
      _currentLineIndex = mode == LyricsSyncMode.synced ? -1 : 0;
      _timingState = null;
      _autoScrollEnabled = true;
      _didInitialCenter = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    if (mode == LyricsSyncMode.synced) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final player = context.read<WispAudioHandler>();
        final provider = context.read<LyricsProvider>();
        final track = player.currentTrack;
        if (track == null) return;
        final syncedState = provider.getState(track, LyricsSyncMode.synced);
        final syncedLyrics = syncedState.lyrics;
        if (syncedLyrics == null || !syncedLyrics.synced) return;
        final cleanedSyncedLyrics = removeEmptyLyricsLines(syncedLyrics);
        if (cleanedSyncedLyrics.lines.isEmpty) return;
        final positionMs = _effectivePositionMs();
        final timing = resolveSyncedLyricsTiming(
          cleanedSyncedLyrics.lines,
          positionMs,
        );
        setState(() {
          _currentLineIndex = timing.activeIndex;
          _timingState = timing;
        });
        if (timing.activeIndex >= 0) {
          _scrollToLine(timing.activeIndex);
        }
      });
    }
  }

  void _handleSyncedUnavailable() {
    if (!_syncedLyricsAvailable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _syncedLyricsAvailable = false;
        _syncMode = LyricsSyncMode.unsynced;
        _currentLineIndex = 0;
        _timingState = null;
        _autoScrollEnabled = true;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _handleDelayChanged(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return;
    setState(() {
      _lyricsDelaySeconds = parsed;
    });
    _saveLyricsDelay();
  }

  void _resetDelay() {
    setState(() {
      _lyricsDelaySeconds = 0;
      _delayController.text = '0';
    });
    _saveLyricsDelay();
  }

  /// Load lyrics delay for current track from persistence
  Future<void> _loadLyricsDelay(
    LyricsProvider lyricsProvider,
    String trackId,
  ) async {
    try {
      final delay = await lyricsProvider.getDelaySeconds(trackId);
      if (!mounted) return;
      setState(() {
        _lyricsDelaySeconds = delay;
        _delayController.text = delay.toStringAsFixed(1);
      });
    } catch (e) {
      logger.e('Error loading lyrics delay', error: e);
    }
  }

  void _syncExternalDelay(LyricsProvider lyricsProvider, String trackId) {
    final providerDelay = lyricsProvider.getDelaySecondsCached(trackId);
    if (_delaySyncTrackId == trackId && _delaySyncValue == providerDelay) {
      return;
    }
    _delaySyncTrackId = trackId;
    _delaySyncValue = providerDelay;
    if (_lyricsDelaySeconds == providerDelay) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _trackId != trackId) return;
      setState(() {
        _lyricsDelaySeconds = providerDelay;
        _delayController.text = providerDelay.toStringAsFixed(1);
      });
    });
  }

  /// Save lyrics delay for current track to persistence
  Future<void> _saveLyricsDelay() async {
    final trackId = _trackId;
    if (trackId == null) return;
    final provider = context.read<LyricsProvider>();
    await provider.setDelaySeconds(trackId, _lyricsDelaySeconds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dominantColor = theme.colorScheme.primary;
    final backgroundColor = _tintedDominantColor(dominantColor);

    final content = _buildLyricsContent(backgroundColor);

    return Consumer2<WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
        final track = player.currentTrack;
        if (track == null) {
          _stopPositionTimer();
          return const Center(
            child: Text(
              'No track playing',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final backgroundLayer = SlidingTrackBackground(
          transitionToken: player.trackChangeToken,
          trackId: track.id,
          queueIndex: player.currentIndex,
          child: ColoredBox(color: backgroundColor),
        );

        final surface = _isDesktop
            ? Material(type: MaterialType.transparency, child: content)
            : Scaffold(
                backgroundColor: Colors.transparent,
                appBar: widget.hideHeader
                    ? null
                    : AppBar(
                        title: const Text('Lyrics'),
                        actions: [
                          if (!widget.hideHeader)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildLyricsControls(),
                            )
                        ],
                        backgroundColor:
                            _tintedDominantColor(dominantColor, blend: 0.55),
                      ),
                body: content,
              );

        return Stack(
          fit: StackFit.expand,
          children: [
            backgroundLayer,
            surface,
          ],
        );
      },
    );
  }

  Color _tintedDominantColor(Color color, {double blend = 0.4}) {
    final hsl = HSLColor.fromColor(color);
    final overlay = hsl
        .withLightness(0.22)
        .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
        .toColor();
    return Color.lerp(color, overlay, blend) ?? color;
  }

  Widget _buildLyricsContent(Color backgroundColor) {
    return Consumer2<WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
        final track = player.currentTrack;
        if (track == null) {
          _stopPositionTimer();
          return const Center(
            child: Text(
              'No track playing',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        if (_trackId != track.id) {
          _trackId = track.id;
          _currentLineIndex = _syncMode == LyricsSyncMode.synced ? -1 : 0;
          _timingState = null;
          _autoScrollEnabled = true;
          _syncedLyricsAvailable = true;
          _didInitialCenter = false;
          _hoveredLineIndex = -1;
          lyricsProvider.ensureDelayLoaded(track.id);
          _loadLyricsDelay(lyricsProvider, track.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        }

        _syncExternalDelay(lyricsProvider, track.id);

        final state = lyricsProvider.getState(track, _syncMode);
        if (!state.isLoading && state.lyrics == null && state.error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            lyricsProvider.ensureLyrics(track, _syncMode);
          });
        }

        if (state.isLoading && state.lyrics == null) {
          _stopPositionTimer();
          return const Center(child: CircularProgressIndicator());
        }

        final rawLyrics = state.lyrics;
        if (rawLyrics == null || rawLyrics.lines.isEmpty) {
          _stopPositionTimer();
          return const Center(
            child: Text(
              'No lyrics found',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final lyrics = removeEmptyLyricsLines(rawLyrics);
        if (lyrics.lines.isEmpty) {
          _stopPositionTimer();
          return const Center(
            child: Text(
              'No lyrics found',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        if (_syncMode == LyricsSyncMode.synced && !lyrics.synced) {
          _handleSyncedUnavailable();
        }

        if (_lineKeys.length != lyrics.lines.length) {
          _lineKeys = List.generate(lyrics.lines.length, (_) => GlobalKey());
        }

        _activeLyrics = lyrics;
        _playerRef = player;
        _ensurePositionTimer();
        _centerCurrentLineOnOpen(player, lyrics);
        final syncedTiming = lyrics.synced
            ? _timingState ??
                resolveSyncedLyricsTiming(
                  lyrics.lines,
                  _effectivePositionMs(),
                )
            : null;

        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (_isDesktop && !widget.hideHeader) Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lyrics',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _buildLyricsControls(),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                        final edgeCenterPadding = _isMobile
                          ? 0.0
                          : ((constraints.maxHeight - 56.0) / 4)
                            .clamp(16.0, double.infinity)
                            .toDouble();
                        final horizontalPadding = _isDesktop
                          ? (constraints.maxWidth * 0.2).clamp(24.0, 320.0)
                          : (constraints.maxWidth * 0.08).clamp(12.0, 40.0);
                        final topPadding = edgeCenterPadding + (_isMobile ? 32.0 : 0.0);

                      _scheduleInitialCenterIfNeeded(
                        lyrics,
                        constraints.maxWidth,
                        constraints.maxHeight,
                        horizontalPadding,
                        edgeCenterPadding,
                      );

                      return Align(
                        alignment: Alignment.topLeft,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            scrollbars: false,
                          ),
                          child: ListView.builder(
                            key: _listKey,
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              topPadding,
                              horizontalPadding,
                              edgeCenterPadding,
                            ),
                            itemCount: lyrics.lines.length + (_isMobile ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_isMobile && index == lyrics.lines.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                                  child: Text(
                                    'Lyrics provided by ${lyrics.provider.label}',
                                    style: TextStyle(color: Colors.grey[300], fontSize: 12),
                                    textAlign: TextAlign.left,
                                  ),
                                );
                              }
                              final line = lyrics.lines[index];
                              final isSynced = lyrics.synced;
                              final timing = syncedTiming;
                              final anchorIndex = _currentLineIndex >= 0
                                  ? _currentLineIndex
                                  : (timing?.nextIndex ?? timing?.previousIndex ?? 0);
                              final offset = isSynced ? (index - anchorIndex) : 0;
                              var opacity = 1.0;
                              if (isSynced && anchorIndex >= 0) {
                                if (offset > 0) {
                                  opacity = (0.75 - (offset * 0.05)).clamp(0.45, 0.75);
                                } else if (offset < 0) {
                                  opacity = (0.45 - (offset.abs() * 0.07)).clamp(0.2, 0.45);
                                }
                              }
                              final isCurrent =
                                  isSynced && index == _currentLineIndex;
                              final canSeek = line.startTimeMs > 0;
                              final delayMs =
                                  (_lyricsDelaySeconds * 1000).round();

                              if (isSynced &&
                                  timing != null &&
                                  timing.shouldFadePreviousLine &&
                                  timing.previousIndex == index &&
                                  timing.nextIndex != null) {
                                opacity = lerpDouble(1.0, 0.5, timing.fadeOutProgress)!;
                              }

                              final isActiveLine = isCurrent &&
                                  !(isSynced &&
                                      timing != null &&
                                      timing.shouldFadePreviousLine &&
                                    timing.fadeOutProgress > 0 &&
                                      timing.previousIndex == index);

                              final fontSize = _isDesktop ? 42.0 : 30.0;

                              final isHovered =
                                  _isDesktop && _hoveredLineIndex == index;
                              final underline = isHovered
                                  ? TextDecoration.underline
                                  : TextDecoration.none;
                                final inactiveColor =
                                  Color.lerp(Colors.white, backgroundColor, 0.6) ??
                                    Colors.white70;

                              final lineWidget = Padding(
                                key: _lineKeys[index],
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: MouseRegion(
                                    cursor: canSeek
                                        ? SystemMouseCursors.click
                                        : MouseCursor.defer,
                                    onEnter: (_) {
                                      if (!_isDesktop) return;
                                      setState(() => _hoveredLineIndex = index);
                                    },
                                    onExit: (_) {
                                      if (!_isDesktop) return;
                                      setState(() => _hoveredLineIndex = -1);
                                    },
                                    child: GestureDetector(
                                      onTap: canSeek
                                          ? () {
                                              final targetMs =
                                                  line.startTimeMs + delayMs;
                                              final safeMs =
                                                  targetMs < 0 ? 0 : targetMs;
                                              player.seek(
                                                Duration(milliseconds: safeMs),
                                              );
                                            }
                                          : null,
                                      child: Opacity(
                                        opacity: opacity,
                                        child: AnimatedDefaultTextStyle(
                                          duration: const Duration(milliseconds: 250),
                                          style: TextStyle(
                                            color: isActiveLine
                                                ? Colors.white
                                                : inactiveColor,
                                            fontSize: fontSize,
                                            letterSpacing: _isDesktop ? -1.5 : -0.7,
                                            fontWeight: FontWeight.w700,
                                            height: _isDesktop ? 1.4 : 1.06,
                                            decoration: underline,
                                            decorationColor: Colors.white70,
                                          ),
                                          child: Text(
                                            line.content,
                                            textAlign: TextAlign.left,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );

                              final showWaitingDots = isSynced &&
                                  timing != null &&
                                  timing.showWaitingDots &&
                                  timing.nextIndex == index;

                              if (!showWaitingDots) {
                                return lineWidget;
                              }

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildWaitingDots(
                                    progress: timing.progressToNext,
                                  ),
                                  lineWidget,
                                ],
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  if (_isDesktop)
                    Positioned(
                      left: 24,
                      bottom: 12,
                      child: Text(
                        'Lyrics provided by ${lyrics.provider.label}',
                        style: TextStyle(color: Colors.grey[300], fontSize: 12),
                        textAlign: TextAlign.left,
                      ),
                    ),
                ],
              ),
            ),
            if (_isMobile) _buildMobileLyricsPlayer(backgroundColor),
            ],
        );
      },
    );
  }

  Widget _buildMobileLyricsPlayer(Color backgroundColor) {
    final surfaceColor =
        Color.lerp(backgroundColor, Colors.black, 0.25) ?? backgroundColor;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMobileSeekBar(),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 28),
                    color: Colors.white,
                    onPressed: () {
                      context.read<PlaybackCoordinator>().skipPrevious();
                    },
                  ),
                  _buildMobilePlayPauseButton(),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 28),
                    color: Colors.white,
                    onPressed: () {
                      context.read<PlaybackCoordinator>().skipNext();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileSeekBar() {
    return Consumer2<PlaybackCoordinator, WispAudioHandler>(
      builder: (context, coordinator, player, child) {
        final useHandoffState = coordinator.useLinkedPlaybackState;
        final effectivePosition = coordinator.effectiveThrottledPosition;

        final data = _LyricsMobilePositionData(
          position: effectivePosition,
          duration: player.duration,
          isLoading: !useHandoffState && (player.isLoading || player.isBuffering),
        );

        if (data.duration.inMilliseconds <= 0) {
          return const SizedBox(height: 4);
        }

        if (data.isLoading) {
          return const SizedBox(
            height: 4,
            child: LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
        }

        final progress = data.duration.inMilliseconds > 0
            ? data.position.inMilliseconds / data.duration.inMilliseconds
            : 0.0;

        final positionText = _formatDuration(data.position);
        final durationText = _formatDuration(data.duration);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white10,
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (value) {
                  final newPosition = Duration(
                    milliseconds: (value * data.duration.inMilliseconds).round(),
                  );
                  context.read<PlaybackCoordinator>().seek(newPosition);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  positionText,
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  durationText,
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobilePlayPauseButton() {
    return Consumer2<PlaybackCoordinator, WispAudioHandler>(
      builder: (context, coordinator, player, child) {
        final useHandoffState = coordinator.useLinkedPlaybackState;
        final effectiveIsPlaying = coordinator.effectiveIsPlaying;

        final track = player.currentTrack;
        final data = _LyricsMobilePlaybackData(
          isPlaying: player.isPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isOnline: player.isOnline,
          currentTrackId: track?.id,
          currentTrackCached: track == null ? true : player.isTrackCached(track.id),
          queueNotEmpty: player.queueTracks.isNotEmpty,
        );

        if (data.isLoading || data.isBuffering) {
          return const SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        }

        final isOfflineBlocked =
            !useHandoffState &&
            !data.isOnline &&
            data.currentTrackId != null &&
            !data.currentTrackCached;

        VoidCallback? onPressed;
        if (!isOfflineBlocked) {
          if (effectiveIsPlaying) {
            onPressed = () => context.read<PlaybackCoordinator>().pause();
          } else if (data.currentTrackId != null || data.queueNotEmpty) {
            onPressed = () => context.read<PlaybackCoordinator>().play();
          }
        }

        return IconButton(
          icon: Icon(
            effectiveIsPlaying ? Icons.pause : Icons.play_arrow,
            size: 32,
            color: Colors.white,
          ),
          onPressed: onPressed,
        );
      },
    );
  }

  Widget _buildLyricsControls() {
    if (widget.hideHeader) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            child: TextField(
              controller: _delayController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              onChanged: _handleDelayChanged,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Delay (s)',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
                isDense: true,
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.35),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            color: Colors.white,
            tooltip: 'Reset Delay',
            onPressed: _resetDelay,
          ),
          const SizedBox(width: 4),
          _isMobile
              ? _buildMobileSyncSelector()
              : _buildDesktopSyncSelector(),
        ],
      ),
    );
  }

  Widget _buildMobileSyncSelector() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: DropdownButtonHideUnderline(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: DropdownButton<LyricsSyncMode>(
            value: _syncMode,
            mouseCursor: SystemMouseCursors.click,
            dropdownColor: const Color(0xFF181818),
            iconEnabledColor: Colors.white,
            items: LyricsSyncMode.values
                .map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    enabled: mode == LyricsSyncMode.synced
                        ? _syncedLyricsAvailable
                        : true,
                    child: Text(
                      mode.label,
                      style: TextStyle(
                        color: mode == LyricsSyncMode.synced &&
                                !_syncedLyricsAvailable
                            ? Colors.grey[600]
                            : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (mode) {
              if (mode != null) _onSyncModeChanged(mode);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSyncSelector() {
    return ToggleButtons(
      isSelected: [
        _syncMode == LyricsSyncMode.synced,
        _syncMode == LyricsSyncMode.unsynced,
      ],
      onPressed: (index) {
        if (index == 0 && !_syncedLyricsAvailable) return;
        _onSyncModeChanged(
          index == 0 ? LyricsSyncMode.synced : LyricsSyncMode.unsynced,
        );
      },
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      disabledColor: Colors.grey[600],
      disabledBorderColor: Colors.grey[700],
      selectedColor: Colors.white,
      fillColor: Colors.black.withValues(alpha: 0.1),
      constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
      children: [
        Icon(
          Icons.sync,
          size: 16,
          color: _syncedLyricsAvailable ? null : Colors.grey[600],
        ),
        const Icon(
          Icons.sync_disabled,
          size: 16,
        )
      ],
    );
  }

  Widget _buildWaitingDots({required double progress}) {
    final dotSize = _isDesktop ? 12.0 : 10.0;

    final dots = List<Widget>.generate(3, (index) {
      final start = index / 3;
      final end = (index + 1) / 3;
      final localProgress = ((progress - start) / (end - start)).clamp(0.0, 1.0);
      final opacity = lerpDouble(0.24, 1.0, localProgress)!;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: dots,
          ),
        ),
      ),
    );
  }
}

class _LyricsMobilePositionData {
  final Duration position;
  final Duration duration;
  final bool isLoading;

  const _LyricsMobilePositionData({
    required this.position,
    required this.duration,
    required this.isLoading,
  });

  @override
  bool operator ==(Object other) {
    return other is _LyricsMobilePositionData &&
        other.position == position &&
        other.duration == duration &&
        other.isLoading == isLoading;
  }

  @override
  int get hashCode => Object.hash(position, duration, isLoading);
}

class _LyricsMobilePlaybackData {
  final bool isPlaying;
  final bool isLoading;
  final bool isBuffering;
  final bool isOnline;
  final String? currentTrackId;
  final bool currentTrackCached;
  final bool queueNotEmpty;

  const _LyricsMobilePlaybackData({
    required this.isPlaying,
    required this.isLoading,
    required this.isBuffering,
    required this.isOnline,
    required this.currentTrackId,
    required this.currentTrackCached,
    required this.queueNotEmpty,
  });

  @override
  bool operator ==(Object other) {
    return other is _LyricsMobilePlaybackData &&
        other.isPlaying == isPlaying &&
        other.isLoading == isLoading &&
        other.isBuffering == isBuffering &&
        other.isOnline == isOnline &&
        other.currentTrackId == currentTrackId &&
        other.currentTrackCached == currentTrackCached &&
        other.queueNotEmpty == queueNotEmpty;
  }

  @override
  int get hashCode => Object.hash(
    isPlaying,
    isLoading,
    isBuffering,
    isOnline,
    currentTrackId,
    currentTrackCached,
    queueNotEmpty,
  );
}

String _formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '$minutes:${twoDigits(seconds)}';
}
