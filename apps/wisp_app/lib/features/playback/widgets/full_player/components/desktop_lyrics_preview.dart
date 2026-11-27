// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/playback/widgets/animated_lyrics_preview.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'package:wisp/shared/widgets/display/focus_freeze_builder.dart';

class DesktopLyricsPreviewWidget extends StatefulWidget {
  final global_audio_player.WispAudioHandler player;
  final LyricsProvider lyricsProvider;
  final Color bgColor;
  final Color? btnColor;
  final bool inCard;

  const DesktopLyricsPreviewWidget({
    super.key,
    required this.player,
    required this.lyricsProvider,
    required this.bgColor,
    required this.btnColor,
    this.inCard = false,
  });

  @override
  State<DesktopLyricsPreviewWidget> createState() =>
      _DesktopLyricsPreviewWidgetState();
}

class _DesktopLyricsPreviewWidgetState
    extends State<DesktopLyricsPreviewWidget> {
  LyricsResult? _cachedLyricsRef;
  List<LyricsLine> _cachedNonEmptyLines = const [];

  List<LyricsLine> _getNonEmptyLines(LyricsResult lyrics) {
    if (!identical(_cachedLyricsRef, lyrics)) {
      _cachedLyricsRef = lyrics;
      _cachedNonEmptyLines = nonEmptyLyricsLines(lyrics.lines);
    }
    return _cachedNonEmptyLines;
  }

  int _resolveStartIndex(
    LyricsResult lyrics,
    List<LyricsLine> lines,
    Duration basePosition,
    double delaySeconds,
  ) {
    if (lines.isEmpty || lyrics.syncMode == LyricsSyncMode.unsynced) {
      return 0;
    }
    final delayMs = (delaySeconds * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final timing = resolveSyncedLyricsTiming(lines, effectivePosition);
    return timing.activeIndex >= 0
        ? timing.activeIndex
        : (timing.nextIndex ?? timing.previousIndex ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = widget.player.currentTrack;
    if (currentTrack == null) return const SizedBox.shrink();

    final lyricsProvider = context.watch<LyricsProvider>();
    final wordState = lyricsProvider.getState(currentTrack, LyricsSyncMode.word);
    final lineState = lyricsProvider.getState(currentTrack, LyricsSyncMode.line);
    if (!wordState.isLoading && wordState.lyrics == null && wordState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.word);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final wordLyrics = wordState.lyrics;
    final lyrics = wordLyrics?.isWordSynced == true
        ? wordLyrics
        : wordState.hasFetched && !wordState.isLoading
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

    final delaySeconds = context.select<LyricsProvider, double>(
      (provider) => provider.getDelaySecondsCached(currentTrack.id),
    );
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.lyricsPreview,
      ),
    );

    final isLoading =
        wordState.isLoading || (wordState.lyrics == null && lineState.isLoading);
    final nonEmptyLines = lyrics == null ? const <LyricsLine>[] : _getNonEmptyLines(lyrics);

    if (!isLoading && (lyrics == null || nonEmptyLines.isEmpty)) {
      return const SizedBox.shrink();
    }

    final coordinator = context.read<PlaybackCoordinator>();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoading && lyrics == null)
          const Text(
            'Loading lyrics…',
            style: TextStyle(color: Colors.white, fontSize: 13),
          )
        else
          ValueListenableBuilder<Duration>(
            valueListenable: coordinator.effectivePositionListenable,
            builder: (context, basePosition, _) {
              final startIndex = _resolveStartIndex(
                lyrics!,
                nonEmptyLines,
                basePosition,
                delaySeconds,
              );

              Widget buildPreview(int index) {
                final previewLines = lyrics.syncMode == LyricsSyncMode.unsynced
                    ? nonEmptyLines.take(5).toList()
                    : nonEmptyLines.skip(index).take(5).toList();
                return AnimatedLyricsPreviewList(
                  lines: previewLines,
                  resetKey: currentTrack.id,
                  textStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }

              if (freezeWhenUnfocused) {
                return FocusFreezeBuilder<int>(
                  value: startIndex,
                  builder: (context, frozenIndex) => buildPreview(frozenIndex),
                );
              }
              return buildPreview(startIndex);
            },
          ),
        const SizedBox(height: 6),
        Text(
          lyrics == null ? '' : 'Lyrics provided by ${lyrics.providerLabel}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );

    if (widget.inCard) return content;

    return Container(
      decoration: BoxDecoration(
        color: widget.bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (widget.btnColor ?? Colors.white).withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: content,
    );
  }
}
