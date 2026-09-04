// Copyright © 2026 wizeshi

/// Queue view for managing the playback queue
library;

import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/wisp_audio_handler.dart';
import '../providers/library/library_state.dart';
import '../widgets/hover_underline.dart';
import '../models/metadata_models.dart';
import '../services/app_navigation.dart';
import '../services/playback/playback_coordinator.dart';
import 'list_detail.dart';
import '../widgets/entity_context_menus.dart';

class QueueView extends StatefulWidget {
  /// If true, only returns the queue content without scaffold (for mobile bottom sheet)
  final bool contentOnly;
  final bool hideHeader;
  final Color backgroundColor;

  const QueueView({
    super.key,
    this.contentOnly = false,
    this.hideHeader = false,
    this.backgroundColor = const Color(0xFF121212),
  });

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  final Set<String> _hoveredTrackKeys = {};

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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Queue',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Consumer<WispAudioHandler>(
            builder: (context, player, child) {
              if (player.queueTracks.isEmpty) return const SizedBox.shrink();
              return TextButton(
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
    return Consumer<WispAudioHandler>(
      builder: (context, player, child) {
        final contextName = player.playbackContextName;
        final queue = player.queueTracks;
        final currentIndex = player.currentIndex;

        return Container(
          color: widget.backgroundColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                    if (contextName != null && contextName.isNotEmpty)
                      Text(
                        contextName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else
                      const Text(
                        'Queue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              if (_isDesktop && queueLength > 0)
                TextButton.icon(
                  onPressed: () {
                    context.read<PlaybackCoordinator>().clearQueue();
                  },
                  icon: const Icon(Icons.delete_outline, size: 20),
                  label: const Text('Clear queue'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[400],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$queueLength ${queueLength == 1 ? 'track' : 'tracks'}',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            'queue is empty',
            style: TextStyle(color: Colors.grey[500], fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Play some music to start your queue',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
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

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
        return Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.5),
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
    final trackKey = '${track.id}_$queueIndex';
    final isHovering = _hoveredTrackKeys.contains(trackKey);
    final showOverlay = isCurrentTrack || isHovering;

    // Desktop: drag starts immediately on any pointer-down.
    // Mobile: Flutter's built-in 500 ms delay lets scroll gestures win first;
    // the 2 s LongPressGestureRecognizer (context menu) fires later if the
    // user keeps holding without moving, so the two delays never collide.
    Widget makeDragListener({required Widget child}) {
      if (_isDesktop) {
        return ReorderableDragStartListener(index: listIndex, child: child);
      }
      return ReorderableDelayedDragStartListener(
        index: listIndex,
        child: child,
      );
    }

    return MouseRegion(
      key: key,
      cursor: SystemMouseCursors.click,
      onEnter: _isDesktop
          ? (_) => setState(() => _hoveredTrackKeys.add(trackKey))
          : null,
      onExit: _isDesktop
          ? (_) => setState(() => _hoveredTrackKeys.remove(trackKey))
          : null,
      child: RawGestureDetector(
        gestures: {
          if (_isDesktop)
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(),
                  (TapGestureRecognizer instance) {
                    instance.onSecondaryTapDown = (details) {
                      EntityContextMenus.showTrackMenu(
                        context,
                        track: track,
                        globalPosition: details.globalPosition,
                      );
                    };
                  },
                ),
          if (!_isDesktop)
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: const Duration(seconds: 2),
                  ),
                  (LongPressGestureRecognizer instance) {
                    instance.onLongPress = () {
                      EntityContextMenus.showTrackMenu(context, track: track);
                    };
                  },
                ),
        },
        child: makeDragListener(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (isCurrentTrack) {
                  player.isPlaying ? player.pause() : player.play();
                } else {
                  context.read<PlaybackCoordinator>().playQueueIndex(
                    queueIndex,
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isCurrentTrack
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1)
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
                child: Row(
                  children: [
                    // Thumbnail with play/pause overlay
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              color: Colors.grey[900],
                              child: track.thumbnailUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: track.thumbnailUrl,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.medium,
                                      errorWidget: (context, url, error) =>
                                          Icon(
                                            Icons.music_note,
                                            color: Colors.grey[700],
                                          ),
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[800]),
                                    )
                                  : Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                            ),
                            AnimatedOpacity(
                              opacity: showOverlay ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 120),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.5),
                              ),
                            ),
                            AnimatedOpacity(
                              opacity: showOverlay ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 120),
                              child: Center(
                                child: Icon(
                                  isCurrentTrack && player.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title + artist
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: TextStyle(
                              color: isCurrentTrack
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
                              fontWeight: isCurrentTrack
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          (_isDesktop && primaryArtist != null)
                              ? HoverUnderline(
                                  onTap: () =>
                                      _openArtist(primaryArtist, libraryState),
                                  onSecondaryTapDown: (details) {
                                    EntityContextMenus.showTrackMenu(
                                      context,
                                      track: track,
                                      globalPosition: details.globalPosition,
                                    );
                                  },
                                  builder: (isHovering) => Text(
                                    track.artists.map((a) => a.name).join(', '),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                      decoration: isHovering
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : Text(
                                  track.artists.map((a) => a.name).join(', '),
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ],
                      ),
                    ),
                    // Album column (desktop only)
                    if (_isDesktop && album != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: album.id.isNotEmpty
                            ? HoverUnderline(
                                onTap: () => _openAlbum(album, libraryState),
                                builder: (isHovering) => Text(
                                  album.title,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                    decoration: isHovering
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : Text(
                                album.title,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                    // Duration
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 50,
                      child: Text(
                        _formatDuration(track.durationSecs),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Remove button or spacer
                    if (!isCurrentTrack)
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: Colors.grey[400],
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
                    else
                      const SizedBox(width: 32),
                  ],
                ),
              ),
            ),
          ),
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
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
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
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
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Consumer<WispAudioHandler>(
                      builder: (context, player, child) {
                        if (player.queueTracks.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return TextButton(
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
