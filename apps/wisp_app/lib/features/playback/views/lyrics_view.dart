// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/services/system/app_focus_service.dart';
import 'package:wisp/shared/widgets/display/sliding_track_background.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import '_lyrics_line_item.dart';

class LyricsView extends StatefulWidget {
  final bool hideHeader;

  const LyricsView({super.key, this.hideHeader = false});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final TextEditingController _delayController = TextEditingController(
    text: '0.0',
  );

  List<GlobalKey> _lineKeys = [];
  List<ValueNotifier<LyricsFrame>> _lineTimingNotifiers = [];

  LyricsSyncMode _syncMode = LyricsSyncMode.word;
  bool _autoScrollEnabled = true;
  bool _wasAutoScrollEnabledBeforeUnfocus = true;
  int _currentLineIndex = -1;
  int _lastAutoScrollIndex = -1;
  Set<int> _currentActiveIndices = {};
  LyricsTimingState? _timingState;
  int? _previousWaitingDotsIndex;
  bool _userInteracting = false;
  Timer? _resumeAutoScrollTimer;

  String? _trackId;
  double _lyricsDelaySeconds = 0.0;
  Ticker? _positionTicker;
  LyricsResult? _activeLyrics;
  WispAudioHandler? _playerRef;

  bool _syncedLyricsAvailable = true;
  bool _didInitialCenter = false;
  bool _initialCenterScheduled = false;
  int _pendingInitialCenterIndex = -1;
  double _lastViewportWidth = 0.0;
  double _lastViewportHeight = 0.0;
  double _lastHorizontalPadding = 0.0;
  double _lastEdgeCenterPadding = 0.0;
  String? _delaySyncTrackId;
  double? _delaySyncValue;

  bool _freezeWhenUnfocused = false;

  static const Duration _lineScrollDuration = Duration(milliseconds: 620);

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _resumeAutoScrollTimer?.cancel();
    AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    _positionTicker?.dispose();
    _scrollController.dispose();
    for (final notifier in _lineTimingNotifiers) {
      notifier.dispose();
    }
    _delayController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    final isFocused = AppFocusService.instance.isFocused.value;
    if (isFocused) {
      if (_freezeWhenUnfocused && _positionTicker != null && !_positionTicker!.isActive) {
        _positionTicker!.start();
      }
      if (_wasAutoScrollEnabledBeforeUnfocus && _currentLineIndex >= 0) {
        _autoScrollEnabled = true;
        _userInteracting = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoScrollEnabled) {
            _scrollToLine(_currentLineIndex);
          }
        });
      }
    } else {
      _resumeAutoScrollTimer?.cancel();
      _wasAutoScrollEnabledBeforeUnfocus = _autoScrollEnabled;
      if (_freezeWhenUnfocused && _positionTicker != null && _positionTicker!.isActive) {
        _positionTicker!.stop();
      }
    }
  }

  void _handleScroll() {
    if (_userInteracting) return;
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

    if (lyrics.syncMode == LyricsSyncMode.unsynced) {
      final newIndex = lyrics.lines.isEmpty ? -1 : 0;
      if (newIndex != _currentLineIndex || _timingState != null) {
        _currentLineIndex = newIndex;
        _timingState = null;
        _currentActiveIndices = {0};
        _previousWaitingDotsIndex = null;
        _notifyTimingLines(const LyricsFrame.unsynced());
      }
      return;
    }

    final timing = resolveSyncedLyricsTiming(lyrics.lines, effectivePosition);
    final focusIndex = _scrollTargetIndex(timing);
    final shouldScroll =
        _autoScrollEnabled &&
        focusIndex != null &&
        focusIndex != _lastAutoScrollIndex;

    final waitingDotsIndex =
        (timing.showWaitingDots && timing.nextIndex != null)
            ? timing.nextIndex
            : null;
    final previousWaitingDotsIndex = _previousWaitingDotsIndex;
    _previousWaitingDotsIndex = waitingDotsIndex;

    final previousIndex = _currentLineIndex;
    final previousActiveIndices = _currentActiveIndices;
    final frame = LyricsFrame(
      activeIndex: timing.activeIndex,
      activeIndices: timing.activeIndices,
      timing: timing,
      positionMs: effectivePosition,
      delayMs: delayMs,
    );
    _currentLineIndex = timing.activeIndex;
    _currentActiveIndices = timing.activeIndices;
    _timingState = timing;

    _notifyTimingLines(
      frame,
      previousActiveIndices: previousActiveIndices,
      previousIndex: previousIndex,
      previousWaitingDotsIndex: previousWaitingDotsIndex,
    );

    if (shouldScroll) {
      _lastAutoScrollIndex = focusIndex;
      _scrollToLine(focusIndex);
    }
  }

  int? _scrollTargetIndex(LyricsTimingState timing) {
    if (timing.activeIndices.isNotEmpty) {
      return timing.activeIndices.last;
    }
    if (timing.activeIndex >= 0) {
      return timing.activeIndex;
    }
    if (timing.showWaitingDots) {
      return null;
    }
    return timing.nextIndex ?? timing.previousIndex;
  }

  void _notifyTimingLines(
    LyricsFrame frame, {
    Set<int>? previousActiveIndices,
    int? previousIndex,
    int? previousWaitingDotsIndex,
  }) {
    final indices = <int>{
      ?previousIndex,
      ...?previousActiveIndices,
      ?previousWaitingDotsIndex,
      ...frame.activeIndices,
      frame.activeIndex,
      if (frame.timing?.showWaitingDots == true &&
          frame.timing?.nextIndex != null)
        frame.timing!.nextIndex!,
    };

    for (final index in indices) {
      if (index >= 0 && index < _lineTimingNotifiers.length) {
        _lineTimingNotifiers[index].value = frame;
      }
    }
  }

  void _ensurePositionTimer() {
    _positionTicker ??= createTicker((_) {
      if (!mounted) return;
      if (_freezeWhenUnfocused && !AppFocusService.instance.isFocused.value) {
        return;
      }
      final player = _playerRef;
      final lyrics = _activeLyrics;
      if (player == null || lyrics == null) return;
      final positionMs = _effectivePositionMs();
      _updateCurrentLine(lyrics, positionMs);
    });

    if (!_positionTicker!.isActive) {
      if (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value) {
        _positionTicker!.start();
      }
    }
  }

  int _effectivePositionMs() {
    return context
        .read<PlaybackCoordinator>()
        .effectiveInterpolatedPosition
        .inMilliseconds;
  }

  void _stopPositionTimer() {
    _positionTicker?.stop();
    _activeLyrics = null;
    _playerRef = null;
  }

  void _scrollToLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    if (!_scrollController.hasClients) return;

    final lineContext = _lineKeys[index].currentContext;
    final listContext = _listKey.currentContext;

    double? targetOffset;

    if (lineContext != null && listContext != null) {
      final lineBox = lineContext.findRenderObject() as RenderBox?;
      final listBox = listContext.findRenderObject() as RenderBox?;
      if (lineBox != null && listBox != null) {
        final lineGlobalTop = lineBox.localToGlobal(Offset.zero).dy;
        final viewportGlobalTop = listBox.localToGlobal(Offset.zero).dy;
        final lineTopInViewport = lineGlobalTop - viewportGlobalTop;

        final currentOffset = _scrollController.offset;
        targetOffset = (lineTopInViewport + currentOffset) -
            ((_scrollController.position.viewportDimension - lineBox.size.height) /
                2);
      }
    }

    if (targetOffset == null && _activeLyrics != null && _lastViewportHeight > 0) {
      targetOffset = _estimateInitialScrollOffset(
        lyrics: _activeLyrics!,
        index: index,
        viewportWidth: _lastViewportWidth > 0
            ? _lastViewportWidth
            : MediaQuery.sizeOf(context).width,
        viewportHeight: _lastViewportHeight,
        horizontalPadding: _lastHorizontalPadding,
        edgeCenterPadding: _lastEdgeCenterPadding,
      );
    }

    if (targetOffset == null) return;

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
    final timing = lyrics.syncMode != LyricsSyncMode.unsynced
        ? resolveSyncedLyricsTiming(lyrics.lines, _effectivePositionMs())
        : null;
    final initialIndex = lyrics.syncMode != LyricsSyncMode.unsynced
        ? timing!.activeIndex
        : 0;
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
    final fontSize = _isDesktop ? 42.0 : 26.0;
    final lineStyle = TextStyle(
      letterSpacing: _isDesktop ? -1.5 : -0.3,
      fontWeight: _isDesktop ? FontWeight.w700 : FontWeight.w800,
      height: _isDesktop ? 1.4 : 1.1,
      fontSize: fontSize,
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

    return painter.height + (_isDesktop ? 16.0 : 24.0);
  }

  void _onSyncModeChanged(LyricsSyncMode mode) {
    if (_syncMode == mode) return;
    setState(() {
      _syncMode = mode;
      _currentLineIndex = mode == LyricsSyncMode.unsynced ? 0 : -1;
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

    if (mode != LyricsSyncMode.unsynced) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final player = context.read<WispAudioHandler>();
        final provider = context.read<LyricsProvider>();
        final track = player.currentTrack;
        if (track == null) return;
        final syncedState = provider.getState(track, mode);
        final syncedLyrics = syncedState.lyrics;
        if (syncedLyrics == null ||
            syncedLyrics.syncMode == LyricsSyncMode.unsynced) {
          return;
        }
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
      _lyricsDelaySeconds = 0.0;
      _delayController.text = '0.0';
    });
    _saveLyricsDelay();
  }

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
      logger.e('[Views/Lyrics] Error loading lyrics delay', error: e);
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

  Future<void> _saveLyricsDelay() async {
    final trackId = _trackId;
    if (trackId == null) return;
    final provider = context.read<LyricsProvider>();
    await provider.setDelaySeconds(trackId, _lyricsDelaySeconds);
  }

  @override
  Widget build(BuildContext context) {
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        widget.hideHeader
            ? PausedBackgroundWidget.lyricsFullscreen
            : PausedBackgroundWidget.lyricsView,
      ),
    );
    _freezeWhenUnfocused = freezeWhenUnfocused;

    final theme = Theme.of(context);
    final dominantColor = theme.colorScheme.primary;
    final backgroundColor = _tintedDominantColor(dominantColor);

    final content = _buildLyricsContent(backgroundColor);

    return Selector<WispAudioHandler, GenericSong?>(
      selector: (context, player) => player.currentTrack,
      builder: (context, track, child) {
        final player = context.read<WispAudioHandler>();
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
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        title: const Text(
                          'Lyrics',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        actions: [
                          if (!widget.hideHeader)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Consumer<LyricsProvider>(
                                builder: (context, lyricsProvider, _) =>
                                    _buildLyricsControls(
                                  lyricsProvider,
                                  track,
                                  isCompact: true,
                                ),
                              ),
                            ),
                        ],
                        backgroundColor: _tintedDominantColor(
                          dominantColor,
                          blend: 0.55,
                        ),
                      ),
                body: content,
                bottomNavigationBar: _buildMobilePlaybackBar(player, track, dominantColor),
              );

        return Stack(
          fit: StackFit.expand,
          children: [backgroundLayer, surface],
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
    return Selector<WispAudioHandler, GenericSong?>(
      selector: (context, player) => player.currentTrack,
      builder: (context, track, child) {
        final player = context.read<WispAudioHandler>();
        final lyricsProvider = context.watch<LyricsProvider>();
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
          _syncMode = LyricsSyncMode.word;
          _currentLineIndex = -1;
          _timingState = null;
          _autoScrollEnabled = true;
          _syncedLyricsAvailable = true;
          _didInitialCenter = false;
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

        if (lyricsProvider.isInitialized && !lyricsProvider.hasSources) {
          _stopPositionTimer();
          return const Center(
            child: Text(
              'No lyrics providers available.\nAdd some in the settings!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.4),
            ),
          );
        }

        if (state.isLoading && state.lyrics == null) {
          _stopPositionTimer();
          return const Center(child: CircularProgressIndicator());
        }

        final rawLyrics = state.lyrics;
        if (rawLyrics == null || rawLyrics.lines.isEmpty) {
          _stopPositionTimer();
          final noProviders = !lyricsProvider.hasSources;
          return Center(
            child: Text(
              noProviders
                  ? 'No lyrics providers available.\nAdd some in the settings!'
                  : 'No lyrics found',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
          );
        }

        final lyrics = removeEmptyLyricsLines(rawLyrics);
        if (lyrics.lines.isEmpty) {
          _stopPositionTimer();
          final noProviders = !lyricsProvider.hasSources;
          return Center(
            child: Text(
              noProviders
                  ? 'No lyrics providers available.\nAdd some in the settings!'
                  : 'No lyrics found',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
          );
        }

        if (_syncMode != LyricsSyncMode.unsynced &&
            lyrics.syncMode == LyricsSyncMode.unsynced) {
          _handleSyncedUnavailable();
        }

        final lyricsObj = state.lyrics;
        if (state.hasFetched && lyricsObj != null) {
          LyricsSyncMode? fallbackMode;
          if (_syncMode == LyricsSyncMode.word && !lyricsObj.isWordSynced) {
            fallbackMode = lyricsObj.isLineSynced
                ? LyricsSyncMode.line
                : LyricsSyncMode.unsynced;
          } else if (_syncMode == LyricsSyncMode.line &&
              !lyricsObj.isLineSynced &&
              !lyricsObj.isWordSynced) {
            fallbackMode = LyricsSyncMode.unsynced;
          }

          if (fallbackMode != null && fallbackMode != _syncMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _trackId != track.id) return;
              if (_syncMode != fallbackMode) {
                _onSyncModeChanged(fallbackMode!);
              }
            });
          }
        }

        if (_lineKeys.length != lyrics.lines.length) {
          _previousWaitingDotsIndex = null;
          _lineKeys = List.generate(lyrics.lines.length, (_) => GlobalKey());
          for (final notifier in _lineTimingNotifiers) {
            notifier.dispose();
          }
          final initialPosition = _effectivePositionMs();
          final initialTiming = lyrics.syncMode != LyricsSyncMode.unsynced
              ? resolveSyncedLyricsTiming(lyrics.lines, initialPosition)
              : null;
          final initialFrame = LyricsFrame(
            activeIndex: initialTiming?.activeIndex ?? 0,
            activeIndices: initialTiming?.activeIndices ?? const {0},
            timing: initialTiming,
            positionMs: initialPosition,
            delayMs: (_lyricsDelaySeconds * 1000).round(),
          );
          _lineTimingNotifiers = List.generate(
            lyrics.lines.length,
            (_) => ValueNotifier<LyricsFrame>(initialFrame),
          );
        }

        _activeLyrics = lyrics;
        _playerRef = player;
        _ensurePositionTimer();
        _centerCurrentLineOnOpen(player, lyrics);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isDesktop && !widget.hideHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Lyrics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    _buildLyricsControls(lyricsProvider, track),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 600 || _isMobile;
                      final edgeCenterPadding = isCompact
                          ? ((constraints.maxHeight - 56.0) * 0.38)
                                .clamp(32.0, double.infinity)
                                .toDouble()
                          : ((constraints.maxHeight - 56.0) / 4)
                                .clamp(16.0, double.infinity)
                                .toDouble();

                      final widgetWidth = constraints.maxWidth;
                      final horizontalPadding = isCompact
                          ? (widgetWidth * 0.06).clamp(16.0, 32.0)
                          : (widgetWidth * 0.2).clamp(24.0, double.infinity);
                      final topPadding = edgeCenterPadding;

                      _lastViewportWidth = constraints.maxWidth;
                      _lastViewportHeight = constraints.maxHeight;
                      _lastHorizontalPadding = horizontalPadding;
                      _lastEdgeCenterPadding = edgeCenterPadding;

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
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollStartNotification) {
                                if (notification.dragDetails != null) {
                                  _userInteracting = true;
                                  _resumeAutoScrollTimer?.cancel();
                                  if (_autoScrollEnabled) {
                                    setState(() => _autoScrollEnabled = false);
                                  }
                                }
                              } else if (notification is UserScrollNotification) {
                                if (notification.direction != ScrollDirection.idle) {
                                  _userInteracting = true;
                                  _resumeAutoScrollTimer?.cancel();
                                  if (_autoScrollEnabled) {
                                    setState(() => _autoScrollEnabled = false);
                                  }
                                } else {
                                  _userInteracting = false;
                                  _resumeAutoScrollTimer?.cancel();
                                  _resumeAutoScrollTimer = Timer(
                                    const Duration(seconds: 4),
                                    () {
                                      if (!mounted) return;
                                      setState(() => _autoScrollEnabled = true);
                                      if (_currentLineIndex >= 0) {
                                        _scrollToLine(_currentLineIndex);
                                      }
                                    },
                                  );
                                }
                              } else if (notification is ScrollEndNotification) {
                                if (_userInteracting) {
                                  _userInteracting = false;
                                  _resumeAutoScrollTimer?.cancel();
                                  _resumeAutoScrollTimer = Timer(
                                    const Duration(seconds: 4),
                                    () {
                                      if (!mounted) return;
                                      setState(() => _autoScrollEnabled = true);
                                      if (_currentLineIndex >= 0) {
                                        _scrollToLine(_currentLineIndex);
                                      }
                                    },
                                  );
                                }
                              }
                              return false;
                            },
                            child: RepaintBoundary(
                              child: WispSmoothScroll(
                                controller: _scrollController,
                                builder: (context, smoothController, smoothPhysics) =>
                                    ListView.builder(
                                  key: _listKey,
                                  controller: smoothController,
                                  physics: smoothPhysics,
                                  padding: EdgeInsets.fromLTRB(
                                    horizontalPadding,
                                    topPadding,
                                    horizontalPadding,
                                    edgeCenterPadding,
                                  ),
                                  itemCount:
                                      lyrics.lines.length + (_isMobile ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (_isMobile && index == lyrics.lines.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 12,
                                          bottom: 16,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Lyrics provided by ${lyrics.providerLabel}',
                                              style: TextStyle(
                                                color: Colors.grey[300],
                                                fontSize: 12,
                                              ),
                                              textAlign: TextAlign.left,
                                            ),
                                            if (lyrics.attribution != null && lyrics.attribution!.trim().isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              _buildAttributionText(
                                                lyrics.attribution!,
                                                baseStyle: TextStyle(
                                                  color: Colors.grey[400],
                                                  fontSize: 11,
                                                ),
                                                linkStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  decoration: TextDecoration.underline,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }
                                    final line = lyrics.lines[index];
                                    return LyricsLineItem(
                                      key: _lineKeys[index],
                                      line: line,
                                      index: index,
                                      isDesktop: _isDesktop,
                                      syncMode: _syncMode,
                                      backgroundColor: backgroundColor,
                                      player: player,
                                      frameListenable: _lineTimingNotifiers[index],
                                      onSeek: (position) => player.seek(position),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (!_autoScrollEnabled &&
                      _currentLineIndex >= 0 &&
                      _syncMode != LyricsSyncMode.unsynced)
                    Positioned(
                      bottom: _isMobile ? 24 : 32,
                      right: _isMobile ? 20 : 32,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.white.withValues(alpha: 0.2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            _resumeAutoScrollTimer?.cancel();
                            setState(() => _autoScrollEnabled = true);
                            if (_currentLineIndex >= 0) {
                              _scrollToLine(_currentLineIndex);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Sync',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_isDesktop)
                    Positioned(
                      left: 32,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lyrics provided by ${lyrics.providerLabel}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.left,
                          ),
                          if (lyrics.attribution != null && lyrics.attribution!.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            _buildAttributionText(
                              lyrics.attribution!,
                              baseStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                              linkStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttributionText(
    String text, {
    required TextStyle baseStyle,
    required TextStyle linkStyle,
  }) {
    final spans = <InlineSpan>[];
    final linkRegex = RegExp(r'\[([^\]]+)\]\((https?://[^\)]+)\)');
    int lastMatchEnd = 0;

    for (final match in linkRegex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }
      final linkText = match.group(1) ?? '';
      final linkUrl = match.group(2) ?? '';
      spans.add(
        TextSpan(
          text: linkText,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(linkUrl);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.left,
    );
  }

  Widget _buildDelayInput({bool isCompact = false}) {
    final width = isCompact ? 68.0 : 72.0;
    final height = isCompact ? 32.0 : 28.0;
    final fontSize = isCompact ? 13.0 : 12.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(isCompact ? 6 : 5),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: _delayController,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          onChanged: _handleDelayChanged,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsControls(
    LyricsProvider lyricsProvider,
    GenericSong track, {
    bool isCompact = false,
  }) {
    if (widget.hideHeader) return const SizedBox.shrink();
    final wordState = lyricsProvider.getState(track, LyricsSyncMode.word);
    final lineState = lyricsProvider.getState(track, LyricsSyncMode.line);
    final wordAvailable =
        !wordState.hasFetched || wordState.lyrics?.isWordSynced == true;
    final lineAvailable =
        !lineState.hasFetched ||
        lineState.lyrics?.isLineSynced == true ||
        wordState.lyrics?.isWordSynced == true;

    final btnMinSize = isCompact ? 34.0 : 28.0;
    final iconSize = isCompact ? 18.0 : 16.0;

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildDelayInput(isCompact: isCompact),
          const SizedBox(width: 4),
          GenericIconButton(
            icon: Icon(Icons.refresh, size: iconSize),
            color: Colors.white.withValues(alpha: 0.85),
            tooltip: 'Reset Delay',
            splashRadius: isCompact ? 18 : 16,
            mouseCursor: SystemMouseCursors.click,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: btnMinSize,
              minHeight: btnMinSize,
            ),
            onPressed: _resetDelay,
          ),
          SizedBox(width: isCompact ? 6 : 8),
          _buildDesktopSyncSelector(
            wordAvailable: wordAvailable,
            lineAvailable: lineAvailable,
            isCompact: isCompact,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSyncSelector({
    required bool wordAvailable,
    required bool lineAvailable,
    bool isCompact = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(isCompact ? 8 : 6),
      ),
      padding: EdgeInsets.all(isCompact ? 3 : 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSyncButton(
            icon: Icons.mic,
            mode: LyricsSyncMode.word,
            enabled: wordAvailable,
            tooltip: 'Word/Syllable synced',
            isCompact: isCompact,
          ),
          SizedBox(width: isCompact ? 3 : 2),
          _buildSyncButton(
            icon: Icons.sync,
            mode: LyricsSyncMode.line,
            enabled: lineAvailable,
            tooltip: 'Line synced',
            isCompact: isCompact,
          ),
          SizedBox(width: isCompact ? 3 : 2),
          _buildSyncButton(
            icon: Icons.sync_disabled,
            mode: LyricsSyncMode.unsynced,
            enabled: true,
            tooltip: 'Unsynced',
            isCompact: isCompact,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton({
    required IconData icon,
    required LyricsSyncMode mode,
    required bool enabled,
    required String tooltip,
    bool isCompact = false,
  }) {
    final isSelected = _syncMode == mode;
    final buttonColor = isSelected
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.transparent;
    final iconColor = !enabled
        ? Colors.white.withValues(alpha: 0.25)
        : isSelected
            ? Colors.white
            : Colors.white.withValues(alpha: 0.65);

    final size = isCompact ? 30.0 : 26.0;
    final iconSize = isCompact ? 16.0 : 15.0;

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: InkWell(
          borderRadius: BorderRadius.circular(isCompact ? 6 : 4),
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onTap: enabled ? () => _onSyncModeChanged(mode) : null,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(isCompact ? 6 : 4),
            ),
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }

  Widget _buildMobilePlaybackBar(
    WispAudioHandler player,
    GenericSong track,
    Color dominantColor,
  ) {
    return Consumer<PlaybackCoordinator>(
      builder: (context, coordinator, _) {
        final position = coordinator.effectiveInterpolatedPosition;
        final durationSecs = track.durationSecs;
        final duration = durationSecs > 0
            ? Duration(seconds: durationSecs)
            : (position > Duration.zero ? position : const Duration(seconds: 1));

        final maxMs = duration.inMilliseconds;
        final curMs = position.inMilliseconds.clamp(0, maxMs);
        final progress = maxMs > 0 ? (curMs / maxMs).clamp(0.0, 1.0) : 0.0;
        final isPlaying = coordinator.effectiveIsPlaying;

        final barBackground = _tintedDominantColor(dominantColor, blend: 0.7)
            .withValues(alpha: 0.94);

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              decoration: BoxDecoration(
                color: barBackground,
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress Bar & Durations
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                          thumbColor: Colors.white,
                          overlayColor: Colors.white.withValues(alpha: 0.15),
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: (value) {
                            final targetMs = (value * maxMs).round();
                            coordinator.seek(Duration(milliseconds: targetMs));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatMobileDuration(position),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _formatMobileDuration(duration),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Controls: Skip Backward, Play/Pause, Skip Forward
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GenericIconButton(
                            icon: const Icon(Icons.skip_previous_rounded, size: 28),
                            color: Colors.white,
                            splashRadius: 22,
                            onPressed: () => coordinator.skipPrevious(),
                          ),
                          const SizedBox(width: 20),
                          Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                if (isPlaying) {
                                  coordinator.pause();
                                } else {
                                  coordinator.play();
                                }
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 26,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          GenericIconButton(
                            icon: const Icon(Icons.skip_next_rounded, size: 28),
                            color: Colors.white,
                            splashRadius: 22,
                            onPressed: () => coordinator.skipNext(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatMobileDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
