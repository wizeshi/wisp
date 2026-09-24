// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/playback/widgets/animated_lyrics_preview.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;

class DesktopLyricsPreviewWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final currentTrack = player.currentTrack;
    if (currentTrack == null) return const SizedBox.shrink();

    final state = lyricsProvider.getState(currentTrack, LyricsSyncMode.word);
    if (!state.isLoading && state.lyrics == null && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.word);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final lyrics = state.lyrics;
    final delaySeconds = context.select<LyricsProvider, double>(
      (provider) => provider.getDelaySecondsCached(currentTrack.id),
    );
    final basePosition = context.select<PlaybackCoordinator, Duration>(
      (coordinator) => coordinator.effectiveThrottledPosition,
    );
    final delayMs = (delaySeconds * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;

    final previewLines = lyrics == null
        ? const <LyricsLine>[]
        : (() {
            final lines = nonEmptyLyricsLines(lyrics.lines);
            if (lines.isEmpty) return const <LyricsLine>[];
            if (lyrics.syncMode != LyricsSyncMode.line) {
              return lines.take(5).toList();
            }
            final timing = resolveSyncedLyricsTiming(lines, effectivePosition);
            final startIndex = timing.activeIndex >= 0
                ? timing.activeIndex
                : (timing.nextIndex ?? timing.previousIndex ?? 0);
            return lines.skip(startIndex).take(5).toList();
          })();

    if (!state.isLoading && (lyrics == null || previewLines.isEmpty)) {
      return const SizedBox.shrink();
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isLoading && lyrics == null)
          const Text(
            'Loading lyrics…',
            style: TextStyle(color: Colors.white, fontSize: 13),
          )
        else
          AnimatedLyricsPreviewList(
            lines: previewLines,
            resetKey: currentTrack.id,
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          lyrics == null ? '' : 'Lyrics provided by ${lyrics.provider.label}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );

    if (inCard) return content;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (btnColor ?? Colors.white).withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: content,
    );
  }
}
