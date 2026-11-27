// Copyright © 2026 wizeshi

/// Queue view for managing the playback queue
library;

import 'dart:io' show Platform;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/navigation/views/list/view.dart' show SharedListType;
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';

class QueueView extends StatefulWidget {
  /// If true, only returns the queue content without scaffold (for mobile bottom sheet)
  final bool contentOnly;
  final bool hideHeader;
  final Color? backgroundColor;
  final EdgeInsets? listPadding;

  const QueueView({
    super.key,
    this.contentOnly = false,
    this.hideHeader = false,
    this.backgroundColor,
    this.listPadding,
  });

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  List<int> _buildWrappedQueueIndices(int queueLength, int currentIndex) {
    if (queueLength <= 0) return const <int>[];
    if (currentIndex < 0 || currentIndex >= queueLength) {
      return List<int>.generate(queueLength, (index) => index);
    }

    return List<int>.generate(
      queueLength,
      (index) => (currentIndex + index) % queueLength,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    if (widget.contentOnly) {
      return _buildQueueContent();
    }

    if (isDesktop) {
      return _buildQueueContent();
    }

    final colors = context.colors;
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? colors.canvas,
      appBar: AppBar(
        backgroundColor: widget.backgroundColor ?? colors.canvas,
        elevation: 0,
        leading: GenericIconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Queue',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          Selector<WispAudioHandler, bool>(
            selector: (context, player) => player.queueTracks.isNotEmpty,
            builder: (context, hasTracks, child) {
              if (!hasTracks) return const SizedBox.shrink();
              return GenericTextButton(
                onPressed: () {
                  context.read<PlaybackCoordinator>().clearQueue();
                },
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _buildQueueContent(),
    );
  }

  Widget _buildQueueContent() {
    return Selector<WispAudioHandler, (String, List<GenericSong>, int)>(
      selector: (context, player) => (
        player.playbackContext?.name ?? '',
        player.queueTracks,
        player.currentIndex,
      ),
      builder: (context, data, child) {
        final (contextName, queue, currentIndex) = data;
        final player = context.read<WispAudioHandler>();

        return Container(
          width: double.infinity,
          color: widget.backgroundColor ?? Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.hideHeader)
                _buildHeader(contextName, queue.length, player),
              // Queue list or empty state
              Expanded(
                child: queue.isEmpty
                    ? _buildEmptyState()
                    : _buildQueueList(player, queue, currentIndex),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    String? contextName,
    int queueLength,
    WispAudioHandler player,
  ) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contextName != null && contextName.isNotEmpty
                          ? 'Next up from:'
                          : 'Next up',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    if (contextName != null && contextName.isNotEmpty)
                      Text(
                        contextName,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else
                      Text(
                        'Queue',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              if (_isDesktop && queueLength > 0)
                GenericTextButton.icon(
                  onPressed: () {
                    context.read<PlaybackCoordinator>().clearQueue();
                  },
                  icon: const Icon(Icons.delete_outline, size: 20),
                  label: const Text('Clear queue'),
                  foregroundColor: colors.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$queueLength ${queueLength == 1 ? 'track' : 'tracks'}',
            style: TextStyle(color: colors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music, size: 64, color: colors.textMuted),
          const SizedBox(height: 16),
          Text(
            'queue is empty',
            style: TextStyle(color: colors.textMuted, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Play some music to start your queue',
            style: TextStyle(color: colors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(
    WispAudioHandler player,
    List<GenericSong> queue,
    int currentIndex,
  ) {
    final libraryState = context.read<LibraryState>();
    final visibleQueueIndices = _buildWrappedQueueIndices(
      queue.length,
      currentIndex,
    );

    return WispReorderableListView.builder(
      padding: widget.listPadding ?? const EdgeInsets.symmetric(horizontal: 24),
      itemCount: visibleQueueIndices.length,
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        if (visibleQueueIndices.isEmpty || oldIndex == newIndex) return;

        final queueOldIndex = visibleQueueIndices[oldIndex];
        final queueNewIndex =
            visibleQueueIndices[newIndex.clamp(
              0,
              visibleQueueIndices.length - 1,
            )];
        context.read<PlaybackCoordinator>().reorderQueue(
          queueOldIndex,
          queueNewIndex,
        );
      },
      proxyDecorator: (child, index, animation) {
        final colors = context.colors;
        return Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: colors.shadow.withValues(
            alpha: colors.isDark ? 0.5 : 0.18,
          ),
          borderRadius: BorderRadius.circular(8),
          child: child,
        );
      },
      itemBuilder: (context, listIndex) {
        final queueIndex = visibleQueueIndices[listIndex];
        final track = queue[queueIndex];
        final isCurrentTrack = queueIndex == currentIndex;

        return _buildQueueItem(
          key: ValueKey('${track.id}_$queueIndex'),
          track: track,
          queueIndex: queueIndex,
          listIndex: listIndex,
          isCurrentTrack: isCurrentTrack,
          player: player,
          libraryState: libraryState,
        );
      },
    );
  }

  Widget _buildQueueItem({
    required Key key,
    required GenericSong track,
    required int queueIndex,
    required int listIndex,
    required bool isCurrentTrack,
    required WispAudioHandler player,
    required LibraryState libraryState,
  }) {
    final album = track.album;
    final primaryArtist = track.artists.isNotEmpty ? track.artists.first : null;

    // Desktop: drag starts immediately on any pointer-down.
    // Mobile: Flutter's built-in 500 ms delay lets scroll gestures win first;
    // the 2 s LongPressGestureRecognizer (context menu) fires later if the
    // user keeps holding without moving, so the two delays never collide.
    Widget makeDragListener({required Widget child}) {
      if (_isDesktop) {
        return ReorderableDragStartListener(
          key: key,
          index: listIndex,
          child: child,
        );
      }
      return ReorderableDelayedDragStartListener(
        key: key,
        index: listIndex,
        child: child,
      );
    }

    return makeDragListener(
      child: Container(
        decoration: BoxDecoration(
          color: isCurrentTrack
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isCurrentTrack
              ? Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                )
              : null,
        ),
        child: TrackRow(
          track: track,
          isCurrentOverride: isCurrentTrack,
          isPlayingOverride: isCurrentTrack && player.isPlaying,
          playIconLocation: PlayIconLocation.art,
          showAlbumName: _isDesktop && album != null,
          showDuration: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          height: 44,
          onTap: () {
            if (isCurrentTrack) {
              player.isPlaying ? player.pause() : player.play();
            } else {
              context.read<PlaybackCoordinator>().playQueueIndex(queueIndex);
            }
          },
          onPlayPause: () {
            if (isCurrentTrack) {
              player.isPlaying ? player.pause() : player.play();
            } else {
              context.read<PlaybackCoordinator>().playQueueIndex(queueIndex);
            }
          },
          onSecondaryTapDown: (details) {
            EntityContextMenus.showTrackMenu(
              context,
              track: track,
              globalPosition: details.globalPosition,
            );
          },
          onLongPress: () {
            EntityContextMenus.showTrackMenu(context, track: track);
          },
          onAlbumTap: album != null && album.id.isNotEmpty
              ? () => _openAlbum(album, libraryState)
              : null,
          onAlbumSecondaryTapDown: (details) {
            EntityContextMenus.showTrackMenu(
              context,
              track: track,
              globalPosition: details.globalPosition,
            );
          },
          onArtistTap: primaryArtist != null
              ? (artist) => _openArtist(artist, libraryState)
              : null,
          onArtistSecondaryTapDown: (artist, details) {
            EntityContextMenus.showTrackMenu(
              context,
              track: track,
              globalPosition: details.globalPosition,
            );
          },
          trailing: !isCurrentTrack
              ? GenericIconButton(
                  icon: Icon(
                    Icons.close,
                    color: context.colors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () {
                    context.read<PlaybackCoordinator>().removeFromQueue(
                      queueIndex,
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                )
              : const SizedBox(width: 32),
        ),
      ),
    );
  }

  void _openAlbum(GenericSimpleAlbum album, LibraryState libraryState) {
    AppNavigation.instance.openSharedList(
      context,
      id: album.id,
      type: SharedListType.album,
      initialTitle: album.title,
      initialThumbnailUrl: album.thumbnailUrl,
    );
  }

  void _openArtist(GenericSimpleArtist artist, LibraryState libraryState) {
    AppNavigation.instance.openArtist(
      context,
      artistId: artist.id,
      initialArtist: artist,
    );
  }
}

/// Helper function to show mobile queue as a bottom sheet
void showMobileQueueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final colors = context.colors;
        return Container(
          decoration: BoxDecoration(
            color: colors.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Close button row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GenericIconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        color: colors.textPrimary,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Selector<WispAudioHandler, bool>(
                      selector: (context, player) =>
                          player.queueTracks.isNotEmpty,
                      builder: (context, hasTracks, child) {
                        if (!hasTracks) {
                          return const SizedBox.shrink();
                        }
                        return GenericTextButton(
                          onPressed: () {
                            context.read<PlaybackCoordinator>().clearQueue();
                          },
                          child: Text(
                            'Clear',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Queue content
              const Expanded(child: QueueView(contentOnly: true)),
            ],
          ),
        );
      },
    ),
  );
}
