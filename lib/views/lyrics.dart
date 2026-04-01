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
  int _currentLineIndex = 0;
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
    final newIndex = _findCurrentLineIndex(lyrics, effectivePosition);
    if (newIndex != _currentLineIndex) {
      setState(() => _currentLineIndex = newIndex);
      if (_autoScrollEnabled) {
        _scrollToLine(newIndex);
      }
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

  int _findCurrentLineIndex(LyricsResult lyrics, int positionMs) {
    if (!lyrics.synced || lyrics.lines.isEmpty) return 0;
    var index = 0;
    for (var i = 0; i < lyrics.lines.length; i++) {
      if (lyrics.lines[i].startTimeMs <= positionMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _scrollToLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    final context = _lineKeys[index].currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _centerCurrentLineOnOpen(WispAudioHandler player, LyricsResult lyrics) {
    if (_didInitialCenter) return;
    _didInitialCenter = true;
    final initialIndex = lyrics.synced
        ? _findCurrentLineIndex(lyrics, _effectivePositionMs(player))
        : 0;
    _currentLineIndex = initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToLine(initialIndex);
    });
  }

  void _onSyncModeChanged(LyricsSyncMode mode) {
    if (_syncMode == mode) return;
    setState(() {
      _syncMode = mode;
      _currentLineIndex = 0;
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
        final positionMs = _effectivePositionMs(player);
        final index = _findCurrentLineIndex(syncedLyrics, positionMs);
        setState(() => _currentLineIndex = index);
        _scrollToLine(index);
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
          _currentLineIndex = 0;
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

        final lyrics = state.lyrics;
        if (lyrics == null || lyrics.lines.isEmpty) {
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
                                  final displayContent = line.content.trim().isEmpty
                                      ? '♪'
                                      : line.content;
                                  final isSynced = lyrics.synced;
                                  final distance = isSynced
                                      ? (index - _currentLineIndex).abs()
                                      : 0;
                                  final blurSigma = isSynced
                                      ? (distance * 1.05).clamp(0, 8).toDouble()
                                      : 0.0;
                                  final opacity = isSynced
                                      ? (1 - (distance * 0.06)).clamp(0.35, 1.0)
                                      : 1.0;
                                  final isCurrent =
                                      isSynced && index == _currentLineIndex;
                                  final canSeek = line.startTimeMs > 0;
                                  final delayMs =
                                      (_lyricsDelaySeconds * 1000).round();

                                  final fontSize = _isDesktop
                                      ? (isCurrent ? 32.0 : 26.0)
                                      : (isCurrent ? 25.0 : 20.0);

                                  return Padding(
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
                                                  color: isCurrent
                                                      ? Colors.white
                                                      : Colors.grey[200],
                                                  fontSize: fontSize,
                                                  fontWeight: isCurrent
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  height: 1.4,
                                                ),
                                                child: Text(
                                                  displayContent,
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
            color: Colors.grey[400],
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
            color: Colors.grey[400],
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
      color: Colors.grey[400],
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
}
