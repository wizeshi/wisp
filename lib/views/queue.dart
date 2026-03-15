/// Queue view for managing the playback queue
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/wisp_audio_handler.dart';
import '../providers/library/library_state.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/library_item_context_menu.dart';
import '../widgets/hover_underline.dart';
import '../models/metadata_models.dart';
import '../services/app_navigation.dart';
import 'list_detail.dart';
import '../providers/navigation_state.dart';
import '../widgets/navigation.dart';

class QueueView extends StatefulWidget {
  /// If true, only returns the queue content without scaffold (for mobile bottom sheet)
  final bool contentOnly;

  const QueueView({super.key, this.contentOnly = false});

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  NavigationState get _navState => context.read<NavigationState>();
  LibraryView get _currentLibraryView => _navState.selectedLibraryView;
  int get _currentNavIndex => _navState.selectedNavIndex;
  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

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
                  player.clearQueue();
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
          color: const Color(0xFF121212),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                    player.clearQueue();
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

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: queue.length,
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        player.reorderQueue(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final track = queue[index];
        final isCurrentTrack = index == currentIndex;
        final isEven = index % 2 == 0;

        return _buildQueueItem(
          key: ValueKey('${track.id}_$index'),
          track: track,
          index: index,
          isCurrentTrack: isCurrentTrack,
          isEven: isEven,
          player: player,
          libraryState: libraryState,
        );
      },
    );
  }

  Widget _buildQueueItem({
    required Key key,
    required GenericSong track,
    required int index,
    required bool isCurrentTrack,
    required bool isEven,
    required WispAudioHandler player,
    required LibraryState libraryState,
  }) {
    final album = track.album;
    final primaryArtist = track.artists.isNotEmpty ? track.artists.first : null;
    return GestureDetector(
      key: key,
      onSecondaryTapDown: (details) {
        if (_isDesktop) {
          TrackContextMenu.show(
            context: context,
            track: track,
            position: details.globalPosition,
            playlists: libraryState.playlists,
            albums: libraryState.albums,
            artists: libraryState.artists,
            currentLibraryView: _currentLibraryView,
            currentNavIndex: _currentNavIndex,
          );
        }
      },
      onLongPress: _isDesktop
          ? null
          : () {
              TrackContextMenu.show(
                context: context,
                track: track,
                playlists: libraryState.playlists,
                albums: libraryState.albums,
                artists: libraryState.artists,
                currentLibraryView: _currentLibraryView,
                currentNavIndex: _currentNavIndex,
              );
            },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Play this track from queue
            player.playTrack(track, addToQueue: false);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isCurrentTrack
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                  : isEven
                  ? Colors.transparent
                  : Colors.black.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: isCurrentTrack
                  ? Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.3),
                    )
                  : null,
            ),
            child: Row(
              children: [
                // Drag handle or play indicator
                SizedBox(
                  width: 32,
                  child: isCurrentTrack
                      ? Icon(
                          Icons.play_arrow,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        )
                      : ReorderableDragStartListener(
                          index: index,
                          child: Icon(
                            Icons.drag_handle,
                            color: Colors.grey[600],
                            size: 24,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 40,
                    height: 40,
                    color: Colors.grey[900],
                    child: track.thumbnailUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: track.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                Icon(Icons.music_note, color: Colors.grey[700]),
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[800]),
                          )
                        : Icon(Icons.music_note, color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(width: 12),
                // Track info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      (_isDesktop && album != null && album.id.isNotEmpty)
                          ? HoverUnderline(
                              onTap: () => _openAlbum(album, libraryState),
                              builder: (isHovering) => Text(
                                track.title,
                                style: TextStyle(
                                  color: isCurrentTrack
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                  fontWeight: isCurrentTrack
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  decoration: isHovering
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : Text(
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
                                LibraryItemContextMenu.show(
                                  context: context,
                                  item: primaryArtist,
                                  position: details.globalPosition,
                                  playlists: libraryState.playlists,
                                  albums: libraryState.albums,
                                  artists: libraryState.artists,
                                  currentLibraryView: _currentLibraryView,
                                  currentNavIndex: _currentNavIndex,
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
                // Duration
                SizedBox(
                  width: 50,
                  child: Text(
                    _formatDuration(track.durationSecs),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8),
                // Remove button (only for non-current tracks)
                if (!isCurrentTrack)
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey[400], size: 20),
                    onPressed: () {
                      player.removeFromQueue(index);
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
                        if (player.queueTracks.isEmpty)
                          return const SizedBox.shrink();
                        return TextButton(
                          onPressed: () {
                            player.clearQueue();
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
