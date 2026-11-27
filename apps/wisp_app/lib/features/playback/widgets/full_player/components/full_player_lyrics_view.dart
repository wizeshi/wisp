// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart'
    as global_audio_player;
import 'package:wisp/services/system/app_focus_service.dart';
import 'package:wisp/shared/widgets/lyrics/word_fill_lyrics_line.dart';

/// Dedicated full-player lyrics container that resolves synced/unsynced lyrics
/// via [LyricsProvider] and displays them with [FullPlayerSyncedLyricsView].
class FullPlayerLyricsSection extends StatelessWidget {
  final global_audio_player.WispAudioHandler player;
  final LyricsProvider lyricsProvider;
  final double activeFontSize;
  final double inactiveFontSize;
  final Color activeColor;
  final Color? waitingDotColor;
  final double topPadding;

  const FullPlayerLyricsSection({
    super.key,
    required this.player,
    required this.lyricsProvider,
    this.activeFontSize = 34.0,
    this.inactiveFontSize = 30.0,
    this.activeColor = Colors.white,
    this.waitingDotColor,
    this.topPadding = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final currentTrack = player.currentTrack;
    if (currentTrack == null) {
      return Center(
        child: Text(
          'No track playing',
          style: TextStyle(color: Colors.grey[400], fontSize: 16),
        ),
      );
    }

    final syncedState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.word,
    );
    final lineState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.line,
    );
    if (!syncedState.isLoading &&
        syncedState.lyrics == null &&
        syncedState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.word);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final wordLyrics = syncedState.lyrics;
    final syncedLyrics = wordLyrics?.isWordSynced == true
        ? wordLyrics
        : syncedState.hasFetched && !syncedState.isLoading
        ? lineState.lyrics ?? wordLyrics
        : null;
    if ((wordLyrics == null || !wordLyrics.isWordSynced) &&
        !lineState.isLoading &&
        lineState.lyrics == null &&
        lineState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.line);
      });
    }
    final unsyncedState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.unsynced,
    );
    if (syncedLyrics == null &&
        !unsyncedState.isLoading &&
        unsyncedState.lyrics == null &&
        unsyncedState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.unsynced);
      });
    }

    final lyrics = syncedLyrics ?? unsyncedState.lyrics;
    final isLoading =
        (syncedState.isLoading ||
            lineState.isLoading ||
            unsyncedState.isLoading) &&
        lyrics == null;

    if (lyricsProvider.isInitialized && !lyricsProvider.hasSources) {
      return Center(
        child: Text(
          'No lyrics providers available.\nAdd some in the settings!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400], fontSize: 16, height: 1.4),
        ),
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (lyrics == null || lyrics.lines.isEmpty) {
      final noProviders = !lyricsProvider.hasSources;
      return Center(
        child: Text(
          noProviders
              ? 'No lyrics providers available.\nAdd some in the settings!'
              : 'No lyrics found',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400], fontSize: 16, height: 1.4),
        ),
      );
    }

    final normalizedLyrics = removeEmptyLyricsLines(lyrics);
    if (normalizedLyrics.lines.isEmpty) {
      final noProviders = !lyricsProvider.hasSources;
      return Center(
        child: Text(
          noProviders
              ? 'No lyrics providers available.\nAdd some in the settings!'
              : 'No lyrics found',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400], fontSize: 16, height: 1.4),
        ),
      );
    }
    final lyricsRenderMode = normalizedLyrics.isWordSynced
        ? LyricsSyncMode.word
        : normalizedLyrics.syncMode;

    return FullPlayerSyncedLyricsView(
      key: ValueKey<String>('${currentTrack.id}_${normalizedLyrics.syncMode}'),
      lyrics: normalizedLyrics,
      lyricsRenderMode: lyricsRenderMode,
      currentTrack: currentTrack,
      player: player,
      lyricsProvider: lyricsProvider,
      activeFontSize: activeFontSize,
      inactiveFontSize: inactiveFontSize,
      activeColor: activeColor,
      waitingDotColor: waitingDotColor,
      topPadding: topPadding,
    );
  }
}

class FullPlayerSyncedLyricsView extends StatefulWidget {
  final LyricsResult lyrics;
  final LyricsSyncMode lyricsRenderMode;
  final GenericSong currentTrack;
  final global_audio_player.WispAudioHandler player;
  final LyricsProvider lyricsProvider;
  final double activeFontSize;
  final double inactiveFontSize;
  final Color activeColor;
  final Color? waitingDotColor;
  final double topPadding;

  const FullPlayerSyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.lyricsRenderMode,
    required this.currentTrack,
    required this.player,
    required this.lyricsProvider,
    this.activeFontSize = 34.0,
    this.inactiveFontSize = 30.0,
    this.activeColor = Colors.white,
    this.waitingDotColor,
    this.topPadding = 24.0,
  });

  @override
  State<FullPlayerSyncedLyricsView> createState() =>
      _FullPlayerSyncedLyricsViewState();
}

class _FullPlayerSyncedLyricsViewState extends State<FullPlayerSyncedLyricsView>
    with SingleTickerProviderStateMixin {
  final GlobalKey _listKey = GlobalKey();
  late final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _lineKeys;
  late List<ValueNotifier<LyricsFrame>> _lineTimingNotifiers;
  Ticker? _positionTicker;
  VoidCallback? _focusListener;
  PlaybackCoordinator? _coordinatorRef;
  bool _freezeWhenUnfocused = false;
  int _currentLineIndex = -1;
  Set<int> _currentActiveIndices = {};
  int? _previousWaitingDotsIndex;
  int _lastFocusIndex = -1;
  bool _userInteracting = false;
  Timer? _resumeAutoScrollTimer;

  @override
  void initState() {
    super.initState();
    _initLines();
    _setupFocusListener();
    _startTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCurrentLine();
      final focusIndex = _lastFocusIndex >= 0 ? _lastFocusIndex : 0;
      _scrollToLine(focusIndex, instant: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final coordinator = context.read<PlaybackCoordinator>();
      if (!identical(_coordinatorRef, coordinator)) {
        _coordinatorRef?.removeListener(_handleCoordinatorChanged);
        _coordinatorRef = coordinator;
        _coordinatorRef?.addListener(_handleCoordinatorChanged);
      }
    } catch (_) {}
    _syncTickerState();
  }

  void _handleCoordinatorChanged() {
    if (!mounted) return;
    _syncTickerState();
    if (!(_coordinatorRef?.effectiveIsPlaying ?? false)) {
      _updateCurrentLine();
    }
  }

  void _syncTickerState() {
    final isPlaying = _coordinatorRef?.effectiveIsPlaying ?? false;
    final canTick =
        isPlaying &&
        widget.lyricsRenderMode != LyricsSyncMode.unsynced &&
        (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    if (canTick) {
      if (_positionTicker != null && !_positionTicker!.isActive) {
        _positionTicker!.start();
      }
    } else {
      _positionTicker?.stop();
    }
  }

  void _setupFocusListener() {
    _focusListener = () {
      if (!mounted) return;
      final isFocused = AppFocusService.instance.isFocused.value;
      _syncTickerState();
      if (isFocused) {
        _updateCurrentLine();
        if (!_userInteracting &&
            _lastFocusIndex >= 0 &&
            widget.lyricsRenderMode != LyricsSyncMode.unsynced) {
          _scrollToLine(_lastFocusIndex);
        }
      }
    };
    AppFocusService.instance.isFocused.addListener(_focusListener!);
  }

  void _initLines() {
    _lineKeys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
    final delayMs =
        (widget.lyricsProvider.getDelaySecondsCached(widget.currentTrack.id) *
                1000)
            .round();
    final initialPos = _effectivePositionMs(delayMs);
    final initialTiming = widget.lyricsRenderMode != LyricsSyncMode.unsynced
        ? resolveSyncedLyricsTiming(widget.lyrics.lines, initialPos)
        : null;
    final initialFrame = LyricsFrame(
      activeIndex: initialTiming?.activeIndex ?? 0,
      activeIndices: initialTiming?.activeIndices ?? const {0},
      timing: initialTiming,
      positionMs: initialPos,
      delayMs: delayMs,
    );
    _lineTimingNotifiers = List.generate(
      widget.lyrics.lines.length,
      (_) => ValueNotifier<LyricsFrame>(initialFrame),
    );
  }

  void _disposeLines() {
    for (final notifier in _lineTimingNotifiers) {
      notifier.dispose();
    }
  }

  @override
  void didUpdateWidget(FullPlayerSyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTrack.id != oldWidget.currentTrack.id ||
        widget.lyrics.lines.length != oldWidget.lyrics.lines.length ||
        widget.lyricsRenderMode != oldWidget.lyricsRenderMode) {
      _resumeAutoScrollTimer?.cancel();
      _userInteracting = false;
      _disposeLines();
      _currentLineIndex = -1;
      _currentActiveIndices = {};
      _previousWaitingDotsIndex = null;
      _lastFocusIndex = -1;
      _initLines();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    if (_focusListener != null) {
      AppFocusService.instance.isFocused.removeListener(_focusListener!);
      _focusListener = null;
    }
    _coordinatorRef?.removeListener(_handleCoordinatorChanged);
    _resumeAutoScrollTimer?.cancel();
    _positionTicker?.dispose();
    _disposeLines();
    _scrollController.dispose();
    super.dispose();
  }

  void _startTicker() {
    _positionTicker?.dispose();
    _positionTicker = createTicker((_) {
      if (!mounted) return;
      if (_freezeWhenUnfocused && !AppFocusService.instance.isFocused.value) {
        return;
      }
      if (!(_coordinatorRef?.effectiveIsPlaying ?? true)) {
        _positionTicker?.stop();
        return;
      }
      _updateCurrentLine();
    });
    _syncTickerState();
  }

  int _effectivePositionMs(int delayMs) {
    final basePos = context
        .read<PlaybackCoordinator>()
        .effectiveInterpolatedPosition
        .inMilliseconds;
    final adjusted = basePos - delayMs;
    return adjusted < 0 ? 0 : adjusted;
  }

  void _updateCurrentLine() {
    final delayMs =
        (widget.lyricsProvider.getDelaySecondsCached(widget.currentTrack.id) *
                1000)
            .round();
    final effectivePosition = _effectivePositionMs(delayMs);

    if (widget.lyricsRenderMode == LyricsSyncMode.unsynced) {
      final newIndex = widget.lyrics.lines.isEmpty ? -1 : 0;
      if (newIndex != _currentLineIndex) {
        _currentLineIndex = newIndex;
        _currentActiveIndices = {0};
        _previousWaitingDotsIndex = null;
        _notifyTimingLines(const LyricsFrame.unsynced());
      }
      return;
    }

    final timing = resolveSyncedLyricsTiming(
      widget.lyrics.lines,
      effectivePosition,
    );
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

    final focusIndex = timing.activeIndex >= 0
        ? timing.activeIndex
        : (timing.nextIndex ?? timing.previousIndex ?? 0);

    if (focusIndex != _lastFocusIndex) {
      _lastFocusIndex = focusIndex;
      if (!_userInteracting) {
        _scrollToLine(focusIndex);
      }
    }

    _notifyTimingLines(
      frame,
      previousActiveIndices: previousActiveIndices,
      previousIndex: previousIndex,
      previousWaitingDotsIndex: previousWaitingDotsIndex,
    );
  }

  void _scrollToLine(int focusIndex, {bool instant = false, int retries = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (focusIndex < 0 || focusIndex >= _lineKeys.length) return;
      final lineContext = _lineKeys[focusIndex].currentContext;
      final listContext = _listKey.currentContext;
      if (lineContext == null || listContext == null) {
        if (retries > 0) {
          _scrollToLine(focusIndex, instant: instant, retries: retries - 1);
        }
        return;
      }

      final lineBox = lineContext.findRenderObject() as RenderBox?;
      final listBox = listContext.findRenderObject() as RenderBox?;
      if (lineBox == null ||
          listBox == null ||
          !lineBox.hasSize ||
          !listBox.hasSize) {
        if (retries > 0) {
          _scrollToLine(focusIndex, instant: instant, retries: retries - 1);
        }
        return;
      }

      final lineGlobalTop = lineBox.localToGlobal(Offset.zero).dy;
      final viewportGlobalTop = listBox.localToGlobal(Offset.zero).dy;
      final lineTopInViewport = lineGlobalTop - viewportGlobalTop;

      final topTargetOffset = widget.topPadding;
      final currentOffset = _scrollController.offset;
      final targetOffset =
          (currentOffset + lineTopInViewport) - topTargetOffset;
      final clampedOffset = targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );

      if (instant) {
        _scrollController.jumpTo(clampedOffset);
      } else {
        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.lyricsFullscreen,
      ),
    );
    _freezeWhenUnfocused = freezeWhenUnfocused;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomPadding = constraints.maxHeight * 0.75;

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _userInteracting = true;
                _resumeAutoScrollTimer?.cancel();
              } else if (notification is UserScrollNotification) {
                if (notification.direction != ScrollDirection.idle) {
                  _userInteracting = true;
                  _resumeAutoScrollTimer?.cancel();
                } else if (_userInteracting) {
                  _userInteracting = false;
                  _resumeAutoScrollTimer?.cancel();
                  if (widget.lyricsRenderMode != LyricsSyncMode.unsynced) {
                    _resumeAutoScrollTimer = Timer(
                      const Duration(seconds: 4),
                      () {
                        if (!mounted ||
                            widget.lyricsRenderMode ==
                                LyricsSyncMode.unsynced) {
                          return;
                        }
                        final focusIndex = _lastFocusIndex >= 0
                            ? _lastFocusIndex
                            : 0;
                        _scrollToLine(focusIndex);
                      },
                    );
                  }
                }
              } else if (notification is ScrollEndNotification) {
                if (_userInteracting) {
                  _userInteracting = false;
                  _resumeAutoScrollTimer?.cancel();
                  if (widget.lyricsRenderMode != LyricsSyncMode.unsynced) {
                    _resumeAutoScrollTimer = Timer(
                      const Duration(seconds: 4),
                      () {
                        if (!mounted ||
                            widget.lyricsRenderMode ==
                                LyricsSyncMode.unsynced) {
                          return;
                        }
                        final focusIndex = _lastFocusIndex >= 0
                            ? _lastFocusIndex
                            : 0;
                        _scrollToLine(focusIndex);
                      },
                    );
                  }
                }
              }
              return false;
            },
            child: ListView.builder(
              key: _listKey,
              controller: _scrollController,
              scrollCacheExtent: ScrollCacheExtent.pixels(20000),
              itemCount: widget.lyrics.lines.length + 1,
              padding: EdgeInsets.fromLTRB(
                0,
                widget.topPadding,
                0,
                bottomPadding,
              ),
              itemBuilder: (context, index) {
                if (index == widget.lyrics.lines.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lyrics provided by ${widget.lyrics.providerLabel}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.left,
                        ),
                        if (widget.lyrics.attribution != null &&
                            widget.lyrics.attribution!.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _buildAttributionText(
                            widget.lyrics.attribution!,
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
                  );
                }
                return _FullPlayerLyricsLineItem(
                  key: _lineKeys[index],
                  line: widget.lyrics.lines[index],
                  index: index,
                  syncMode: widget.lyricsRenderMode,
                  frameListenable: _lineTimingNotifiers[index],
                  activeFontSize: widget.activeFontSize,
                  inactiveFontSize: widget.inactiveFontSize,
                  activeColor: widget.activeColor,
                  waitingDotColor: widget.waitingDotColor ?? Colors.white,
                  onSeek: (position) {
                    _resumeAutoScrollTimer?.cancel();
                    _userInteracting = false;
                    _lastFocusIndex = index;
                    _scrollToLine(index);
                    unawaited(
                      context.read<PlaybackCoordinator>().seek(position),
                    );
                  },
                );
              },
            ),
          ),
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
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: baseStyle,
          ),
        );
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
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: baseStyle));
    }

    return Text.rich(TextSpan(children: spans), textAlign: TextAlign.left);
  }
}

class _FullPlayerLyricsLineItem extends StatefulWidget {
  final LyricsLine line;
  final int index;
  final LyricsSyncMode syncMode;
  final ValueListenable<LyricsFrame> frameListenable;
  final ValueChanged<Duration> onSeek;
  final double activeFontSize;
  final double inactiveFontSize;
  final Color activeColor;
  final Color waitingDotColor;

  const _FullPlayerLyricsLineItem({
    super.key,
    required this.line,
    required this.index,
    required this.syncMode,
    required this.frameListenable,
    required this.onSeek,
    required this.activeFontSize,
    required this.inactiveFontSize,
    required this.activeColor,
    required this.waitingDotColor,
  });

  @override
  State<_FullPlayerLyricsLineItem> createState() =>
      _FullPlayerLyricsLineItemState();
}

class _FullPlayerLyricsLineItemState extends State<_FullPlayerLyricsLineItem> {
  late List<List<TextSelection>> _bgWordRanges;

  String _formatBgContent(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      return trimmed;
    }
    return '($trimmed)';
  }

  @override
  void initState() {
    super.initState();
    _initRanges();
  }

  @override
  void didUpdateWidget(_FullPlayerLyricsLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line != oldWidget.line) {
      _initRanges();
    }
  }

  void _initRanges() {
    _bgWordRanges = widget.line.background
        .map((bg) => resolveWordRanges(_formatBgContent(bg.content), bg.words))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LyricsFrame>(
      valueListenable: widget.frameListenable,
      builder: (context, frame, _) {
        final isSynced = widget.syncMode != LyricsSyncMode.unsynced;
        final timing = frame.timing;
        final anchorIndex = frame.activeIndex >= 0
            ? frame.activeIndex
            : (timing?.nextIndex ?? timing?.previousIndex ?? 0);
        final distance = (widget.index - anchorIndex).abs();
        final isLineActive =
            !isSynced ||
            frame.activeIndices.contains(widget.index) ||
            frame.activeIndex == widget.index;

        var opacity = (!isSynced || isLineActive)
            ? 1.0
            : (1.0 - (distance * 0.22)).clamp(0.16, 0.72);
        var fontSize = (!isSynced || isLineActive)
            ? widget.activeFontSize
            : widget.inactiveFontSize;
        var fontWeight = (!isSynced || isLineActive)
            ? FontWeight.w700
            : FontWeight.w600;
        var color = (!isSynced || isLineActive)
            ? widget.activeColor
            : Colors.grey[500]!;

        if (isSynced &&
            timing != null &&
            !isLineActive &&
            timing.shouldFadePreviousLine &&
            timing.previousIndex == widget.index &&
            timing.nextIndex != null) {
          opacity = lerpDouble(1.0, 0.72, timing.fadeOutProgress)!;
          fontSize = lerpDouble(
            widget.activeFontSize,
            widget.inactiveFontSize,
            timing.fadeOutProgress,
          )!;
          fontWeight = timing.fadeOutProgress < 0.55
              ? FontWeight.w700
              : FontWeight.w600;
          color = Color.lerp(
            widget.activeColor,
            Colors.grey[500],
            timing.fadeOutProgress,
          )!;
        }

        final baseStyle = TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.1,
        );
        final defaultTextStyle = DefaultTextStyle.of(context).style;
        final effectiveBaseStyle = defaultTextStyle.merge(baseStyle);

        final isRight = widget.line.isRightSpeaker;
        final textAlign = isRight ? TextAlign.right : TextAlign.left;
        final alignment = isRight
            ? Alignment.centerRight
            : Alignment.centerLeft;

        final Widget textContent;
        if (isLineActive &&
            widget.syncMode == LyricsSyncMode.word &&
            widget.line.hasWordTiming) {
          textContent = WordFillLyricsLine(
            line: widget.line,
            positionMs: frame.positionMs,
            textStyle: effectiveBaseStyle,
            activeColor: widget.activeColor.withValues(alpha: opacity),
            inactiveColor: widget.activeColor.withValues(alpha: 0.45 * opacity),
            textAlign: textAlign,
            enableTicker: false,
          );
        } else {
          textContent = Text(
            widget.line.content,
            style: effectiveBaseStyle,
            textAlign: textAlign,
          );
        }

        // Synchronized Background vocal lines rendering if present
        Widget? backgroundContent;
        if (widget.line.hasBackground) {
          final bgWidgets = <Widget>[];
          final baseBgFontSize = fontSize * 0.72;

          for (int bIdx = 0; bIdx < widget.line.background.length; bIdx++) {
            final bg = widget.line.background[bIdx];
            final bgRanges = (bIdx < _bgWordRanges.length)
                ? _bgWordRanges[bIdx]
                : <TextSelection>[];
            final bgFormattedText = _formatBgContent(bg.content);

            // Timing checks for this background vocal phrase
            final bgStart = bg.startTimeMs;
            int? resolvedBgEnd = bg.endTimeMs;
            if (resolvedBgEnd == null && bg.words.isNotEmpty) {
              final lastWord = bg.words.last;
              resolvedBgEnd =
                  lastWord.endTimeMs ?? (lastWord.startTimeMs + 800);
            }
            resolvedBgEnd ??= (widget.line.endTimeMs ?? (bgStart + 2000));

            final isBgActive =
                isSynced &&
                isLineActive &&
                frame.positionMs >= bgStart &&
                frame.positionMs < resolvedBgEnd;
            final isBgPast =
                isSynced &&
                (frame.positionMs >= resolvedBgEnd ||
                    (!isLineActive && frame.positionMs >= bgStart));
            final isBgUpcoming = isSynced && frame.positionMs < bgStart;

            double bgOpacity = opacity;
            if (isSynced) {
              if (isBgActive) {
                bgOpacity = 1.0;
              } else if (isBgPast) {
                bgOpacity = (opacity * 0.65).clamp(0.2, 0.7);
              } else if (isBgUpcoming) {
                bgOpacity = (opacity * 0.35).clamp(0.1, 0.4);
              }
            }

            final inactiveBgColor =
                Color.lerp(Colors.grey[500]!, Colors.black, 0.2) ??
                Colors.grey[600]!;
            final bgBaseStyle = effectiveBaseStyle.copyWith(
              fontSize: baseBgFontSize,
              fontStyle: FontStyle.italic,
              color: (isBgActive ? widget.activeColor : inactiveBgColor)
                  .withValues(
                    alpha:
                        (isBgActive ? bgOpacity : (inactiveBgColor.a * bgOpacity))
                            .clamp(0.0, 1.0),
                  ),
            );

            Widget phraseWidget;
            if (isBgActive && bg.hasWordTiming && bgRanges.isNotEmpty) {
              final activeWordColor =
                  widget.activeColor.withValues(alpha: bgOpacity);
              final inactiveWordColor = widget.activeColor.withValues(
                alpha: 0.45 * bgOpacity,
              );

              phraseWidget = WordFillLyricsLine(
                line: LyricsLine(
                  content: bgFormattedText,
                  startTimeMs: bgStart,
                  endTimeMs: resolvedBgEnd,
                  words: bg.words,
                  speaker: widget.line.speaker,
                ),
                positionMs: frame.positionMs,
                textStyle: bgBaseStyle,
                activeColor: activeWordColor,
                inactiveColor: inactiveWordColor,
                textAlign: textAlign,
                enableTicker: false,
              );
            } else {
              phraseWidget = Text(
                bgFormattedText,
                style: bgBaseStyle,
                textAlign: textAlign,
              );
            }

            bgWidgets.add(
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: phraseWidget,
              ),
            );
          }

          if (bgWidgets.isNotEmpty) {
            backgroundContent = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isRight
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: bgWidgets,
            );
          }
        }

        final canSeek = isSynced && widget.line.startTimeMs > 0;

        final fullContent = backgroundContent == null
            ? textContent
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isRight
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [textContent, backgroundContent],
              );

        final lineWidget = AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              mouseCursor: canSeek
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              onTap: canSeek
                  ? () => widget.onSeek(
                      Duration(
                        milliseconds: widget.line.startTimeMs + frame.delayMs,
                      ),
                    )
                  : null,
              child: Align(alignment: alignment, child: fullContent),
            ),
          ),
        );

        final showWaitingDots =
            isSynced &&
            timing != null &&
            timing.showWaitingDots &&
            timing.nextIndex == widget.index;

        if (!showWaitingDots) {
          return lineWidget;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [_buildWaitingDots(timing.progressToNext), lineWidget],
        );
      },
    );
  }

  Widget _buildWaitingDots(double progress) {
    const dotSize = 13.0;
    final dots = List<Widget>.generate(3, (index) {
      final start = index / 3;
      final end = (index + 1) / 3;
      final localProgress = ((progress - start) / (end - start)).clamp(
        0.0,
        1.0,
      );
      final opacity = lerpDouble(0.2, 1.0, localProgress)!;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: widget.waitingDotColor.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: dots),
      ),
    );
  }
}
