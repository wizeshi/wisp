/// Full-screen lyrics view
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/metadata_models.dart';
import '../providers/connect/connect_session_provider.dart';
import '../services/wisp_audio_handler.dart';
import '../providers/lyrics/provider.dart';
import '../utils/logger.dart';
import '../utils/lyrics_timing.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({super.key});

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
  bool _textCentered = true;
  bool _syncedLyricsAvailable = true;
  bool _didInitialCenter = false;

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
    final shouldScroll = _autoScrollEnabled &&
        timing.activeIndex >= 0 &&
        timing.activeIndex != _currentLineIndex;

    setState(() {
      _currentLineIndex = timing.activeIndex;
      _timingState = timing;
    });

    if (shouldScroll) {
      _scrollToLine(timing.activeIndex);
    }
  }

  void _ensurePositionTimer() {
    if (_positionTimer != null) return;
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final player = _playerRef;
      final lyrics = _activeLyrics;
      if (player == null || lyrics == null) return;
      final positionMs = _effectivePositionMs(player);
      _updateCurrentLine(lyrics, positionMs);
    });
  }

  int _effectivePositionMs(WispAudioHandler player) {
    final connect = context.read<ConnectSessionProvider>();
    if (connect.isLinked && connect.isHost) {
      return connect.linkedInterpolatedPosition.inMilliseconds;
    }
    return player.interpolatedPosition.inMilliseconds;
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
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _centerCurrentLineOnOpen(WispAudioHandler player, LyricsResult lyrics) {
    if (_didInitialCenter) return;
    _didInitialCenter = true;
    final timing = lyrics.synced
        ? resolveSyncedLyricsTiming(lyrics.lines, _effectivePositionMs(player))
        : null;
    final initialIndex = lyrics.synced ? timing!.activeIndex : 0;
    _currentLineIndex = initialIndex;
    _timingState = timing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initialIndex >= 0) {
        _scrollToLine(initialIndex);
      }
    });
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
        final positionMs = _effectivePositionMs(player);
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

  /// Save lyrics delay for current track to persistence
  Future<void> _saveLyricsDelay() async {
    final trackId = _trackId;
    if (trackId == null) return;
    final provider = context.read<LyricsProvider>();
    await provider.setDelaySeconds(trackId, _lyricsDelaySeconds);
  }

  @override
  Widget build(BuildContext context) {
    var color = Theme.of(context).colorScheme.primaryContainer;

    final content = _buildLyricsContent();

    if (_isDesktop) {
      return Material(color: color, child: content);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrics'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildLyricsControls()
          )
        ],
        backgroundColor: HSLColor.fromColor(color).withLightness(0.25).toColor(),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: color,
        ),
        child: content,
      ),
    );
  }

  Widget _buildLyricsContent() {
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
          lyricsProvider.ensureDelayLoaded(track.id);
          _loadLyricsDelay(lyricsProvider, track.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        }

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
                  _effectivePositionMs(player),
                )
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_isDesktop) Padding(
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
            if (!_isDesktop)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Lyrics provided by ${lyrics.provider.label}',
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                  textAlign: TextAlign.left,
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final edgeCenterPadding =
                          ((constraints.maxHeight - 56.0) / 2).clamp(24.0, double.infinity).toDouble();

                      return AnimatedAlign(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOutCubic,
                        alignment: _textCentered
                            ? Alignment.topCenter
                            : Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 920),
                          child: AnimatedPadding(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOutCubic,
                            padding: EdgeInsets.symmetric(
                              horizontal: _textCentered ? 0 : 56,
                            ),
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(
                                scrollbars: false,
                              ),
                              child: ListView.builder(
                                key: _listKey,
                                controller: _scrollController,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: edgeCenterPadding,
                                ),
                                itemCount: lyrics.lines.length,
                                itemBuilder: (context, index) {
                                  final line = lyrics.lines[index];
                                  final isSynced = lyrics.synced;
                                  final timing = syncedTiming;
                                  final anchorIndex = _currentLineIndex >= 0
                                      ? _currentLineIndex
                                      : (timing?.nextIndex ?? timing?.previousIndex ?? 0);
                                  final distance = isSynced
                                      ? (index - anchorIndex).abs()
                                      : 0;
                                  var blurSigma = isSynced
                                      ? (distance * 1.05).clamp(0, 8).toDouble()
                                      : 0.0;
                                  var opacity = isSynced
                                      ? (1 - (distance * 0.06)).clamp(0.35, 1.0)
                                      : 1.0;
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
                                    opacity = lerpDouble(1.0, 0.7, timing.fadeOutProgress)!;
                                    blurSigma = lerpDouble(0.0, 1.6, timing.fadeOutProgress)!;
                                  }

                                  final isActiveLine = isCurrent &&
                                      !(isSynced &&
                                          timing != null &&
                                          timing.shouldFadePreviousLine &&
                                        timing.fadeOutProgress > 0 &&
                                          timing.previousIndex == index);

                                  var fontSize = _isDesktop
                                      ? (isCurrent ? 32.0 : 26.0)
                                      : (isCurrent ? 25.0 : 20.0);

                                  if (isSynced &&
                                      timing != null &&
                                      timing.shouldFadePreviousLine &&
                                      timing.previousIndex == index &&
                                      timing.nextIndex != null) {
                                    final currentSize = _isDesktop ? 32.0 : 25.0;
                                    final inactiveSize = _isDesktop ? 26.0 : 20.0;
                                    fontSize = lerpDouble(
                                      currentSize,
                                      inactiveSize,
                                      timing.fadeOutProgress,
                                    )!;
                                  }

                                  final lineWidget = Padding(
                                    key: _lineKeys[index],
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Align(
                                      alignment: _textCentered
                                          ? Alignment.center
                                          : Alignment.centerLeft,
                                      child: MouseRegion(
                                        cursor: canSeek
                                            ? SystemMouseCursors.click
                                            : MouseCursor.defer,
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
                                          child: ImageFiltered(
                                            imageFilter: ImageFilter.blur(
                                              sigmaX: blurSigma,
                                              sigmaY: blurSigma,
                                            ),
                                            child: Opacity(
                                              opacity: opacity,
                                              child: AnimatedDefaultTextStyle(
                                                duration: const Duration(milliseconds: 250),
                                                style: TextStyle(
                                                  color: isActiveLine
                                                      ? Colors.white
                                                      : Colors.grey[200],
                                                  fontSize: fontSize,
                                                  fontWeight: isActiveLine
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  height: 1.4,
                                                ),
                                                child: Text(
                                                  line.content,
                                                  textAlign: _textCentered
                                                      ? TextAlign.center
                                                      : TextAlign.left,
                                                ),
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
                          ),
                        ),
                      );
                    },
                  ),
                  if (_isDesktop)
                    Positioned(
                      left: 24,
                      bottom: 10,
                      child: Text(
                        'Lyrics provided by ${lyrics.provider.label}',
                        style: TextStyle(color: Colors.grey[300], fontSize: 12),
                        textAlign: TextAlign.left,
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

  Widget _buildLyricsControls() {
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
                fillColor: Colors.black.withOpacity(0.35),
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
          const SizedBox(width: 12),
          ToggleButtons(
            isSelected: [
              _textCentered == false,
              _textCentered == true,
            ],
            onPressed: (index) {
              if (index == 0) {
                setState(() => _textCentered = false);
                return;
              }
              if (index == 1) {
                setState(() => _textCentered = true);
              }
            },
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            selectedColor: Colors.white,
            fillColor: Colors.black.withOpacity(0.1),
            constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
            children: const [
              Icon(
                Icons.format_align_left,
                size: 16,
              ),
              Icon(
                Icons.format_align_center,
                size: 16,
              )
            ],
          )
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
      fillColor: Colors.black.withOpacity(0.1),
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
    final horizontalPadding = _textCentered ? 0.0 : 8.0;

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
            color: Colors.white.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Align(
        alignment: _textCentered ? Alignment.center : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(left: horizontalPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: dots,
          ),
        ),
      ),
    );
  }
}
