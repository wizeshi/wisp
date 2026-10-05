// Copyright © 2026 wizeshi

library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wisp/features/details/views/list_detail_view.dart';

import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/services/system/listening_habits_service.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/core/utils/song_source_icon.dart';
import 'adaptive_context_menu.dart';
import 'playlist_folder_modals.dart';
import 'track_inspect_dialog.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

class EntityContextMenus {
  static String _idWithoutPrefix(String id) {
    if (!id.contains(':')) return id;
    return id.split(':').last;
  }

  static String? getShareUrl({
    required String source,
    required String type,
    required String id,
  }) {
    final cleanId = _idWithoutPrefix(id);
    final src = source.toLowerCase();
    if (src == 'spotify') {
      return 'https://open.spotify.com/$type/$cleanId';
    } else if (src == 'youtube') {
      if (type == 'track') return 'https://www.youtube.com/watch?v=$cleanId';
      if (type == 'playlist') return 'https://www.youtube.com/playlist?list=$cleanId';
    }
    return null;
  }

  static Future<void> copyShareUrl(
    BuildContext context, {
    required String source,
    required String type,
    required String id,
  }) async {
    final url = getShareUrl(source: source, type: type, id: id);
    if (url == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share is only available for supported sources'),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
  }

  static Future<void> copySpotifyShareUrl(
    BuildContext context, {
    required String source,
    required String type,
    required String id,
  }) => copyShareUrl(context, source: source, type: type, id: id);

  static IconData _sourceIcon(String source) => songSourceIcon(source);

  static Future<List<GenericSong>> _resolveAllPlaylistTracks(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    try {
      final metadataManager = context.read<MetadataManager>();
      final items = <PlaylistItem>[...?(playlist.songs)];

      if (items.isEmpty) {
        final firstPage = await metadataManager.getPlaylistInfo(
          playlist.id,
          offset: 0,
          limit: 50,
          source: playlist.source,
        );
        items.addAll(firstPage.songs ?? const []);
      }

      int offset = items.length;
      final total = playlist.total;
      while (total != null && offset < total) {
        final morePlaylist = await metadataManager.getPlaylistInfo(
          playlist.id,
          offset: offset,
          limit: 50,
          source: playlist.source,
        );
        final more = morePlaylist.songs ?? const <PlaylistItem>[];
        if (more.isEmpty) break;
        items.addAll(more);
        offset = items.length;
        if (more.length < 50) break;
      }

      return items
          .map(
            (item) => GenericSong(
              id: item.id,
              source: item.source,
              title: item.title,
              artists: item.artists,
              thumbnailUrl: item.thumbnailUrl,
              explicit: item.explicit,
              album: item.album,
              durationSecs: item.durationSecs,
            ),
          )
          .toList();
    } catch (_) {
      return playlist.songs
              ?.map(
                (item) => GenericSong(
                  id: item.id,
                  source: item.source,
                  title: item.title,
                  artists: item.artists,
                  thumbnailUrl: item.thumbnailUrl,
                  explicit: item.explicit,
                  album: item.album,
                  durationSecs: item.durationSecs,
                ),
              )
              .toList() ??
          const <GenericSong>[];
    }
  }

  static Future<List<GenericSong>> _resolvePlaylistTracks(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final fromModel =
        playlist.songs
            ?.map(
              (item) => GenericSong(
                id: item.id,
                source: item.source,
                title: item.title,
                artists: item.artists,
                thumbnailUrl: item.thumbnailUrl,
                explicit: item.explicit,
                album: item.album,
                durationSecs: item.durationSecs,
              ),
            )
            .toList() ??
        const <GenericSong>[];
    if (fromModel.isNotEmpty) return fromModel;
    try {
      final metadataManager = context.read<MetadataManager>();
      final full = await metadataManager.getPlaylistInfo(
        playlist.id,
        source: playlist.source,
      );
      return full.songs
              ?.map(
                (item) => GenericSong(
                  id: item.id,
                  source: item.source,
                  title: item.title,
                  artists: item.artists,
                  thumbnailUrl: item.thumbnailUrl,
                  explicit: item.explicit,
                  album: item.album,
                  durationSecs: item.durationSecs,
                ),
              )
              .toList() ??
          const <GenericSong>[];
    } catch (_) {
      return const <GenericSong>[];
    }
  }

  static Future<List<GenericSong>> _resolveAlbumTracks(
    BuildContext context,
    GenericAlbum album,
  ) async {
    final fromModel = album.songs ?? const <GenericSong>[];
    if (fromModel.isNotEmpty) return fromModel;
    try {
      final metadataManager = context.read<MetadataManager>();
      final full = await metadataManager.getAlbumInfo(
        album.id,
        source: album.source,
      );
      return full.songs ?? const <GenericSong>[];
    } catch (_) {
      return const <GenericSong>[];
    }
  }

  static Future<void> _appendTracksToQueue(
    BuildContext context,
    List<GenericSong> tracks,
  ) async {
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No tracks available')));
      return;
    }
    final player = context.read<global_audio_player.WispAudioHandler>();

    final mergedQueue = List<GenericSong>.from(player.queueTracks);
    final seen = mergedQueue
        .map((track) => '${track.source}:${track.id}')
        .toSet();

    var added = 0;
    for (final track in tracks) {
      final key = '${track.source}:${track.id}';
      if (seen.add(key)) {
        mergedQueue.add(track);
        added += 1;
      }
    }

    if (added == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All tracks are already in queue')),
      );
      return;
    }

    var startIndex = 0;
    final currentTrackId = player.currentTrack?.id;
    if (currentTrackId != null) {
      final found = mergedQueue.indexWhere(
        (track) => track.id == currentTrackId,
      );
      if (found >= 0) startIndex = found;
    }

    await context.read<PlaybackCoordinator>().setQueue(
      mergedQueue,
      startIndex: startIndex,
      play: player.currentTrack != null ? player.isPlaying : false,
      playbackContext: player.playbackContext,
      shuffleEnabled: player.shuffleEnabled,
      originalQueue: player.shuffleEnabled
          ? List<GenericSong>.from(player.originalQueueTracks)
          : null,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $added track${added == 1 ? '' : 's'} to queue'),
      ),
    );
  }

  static Future<void> showTrackMenu(
    BuildContext context, {
    required GenericSong track,
    Offset? globalPosition,
    Rect? anchorRect,
    List<ContextMenuAction> additionalActions = const [],
    Future<void> Function()? onBeforeNavigate,
  }) async {
    Rect? effectiveAnchorRect = anchorRect;
    if (effectiveAnchorRect == null && globalPosition == null) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final overlay =
            Overlay.maybeOf(context, rootOverlay: true)?.context.findRenderObject()
                as RenderBox?;
        if (overlay != null) {
          effectiveAnchorRect = Rect.fromPoints(
            box.localToGlobal(Offset.zero, ancestor: overlay),
            box.localToGlobal(
              box.size.bottomRight(Offset.zero),
              ancestor: overlay,
            ),
          );
        }
      }
    }

    final metadataManager = context.read<MetadataManager>();
    await metadataManager.ensureLikedTracksLoaded(source: track.source);
    if (!context.mounted) return;
    final activeIconColor = Theme.of(context).colorScheme.primary;
    final isDebugMode =
        context.read<PreferencesProvider>().debugModeEnabled;

    final cacheManager = AudioCacheManager.instance;
    final isLiked = metadataManager.isTrackLiked(track.id, source: track.source);
    final isCached = cacheManager.isTrackCached(track.id);
    final isDownloading = cacheManager.isDownloading(track.id);
    final progress = cacheManager.getDownloadProgress(track.id) ?? 0;
    final hasAlbum = track.album != null && track.album!.id.isNotEmpty;

    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'likes-toggle',
        label: isLiked ? 'Remove from Likes' : 'Add to Likes',
        icon: isLiked ? Icons.favorite : Icons.favorite_border,
        iconColor: isLiked ? activeIconColor : null,
        onSelected: (_) => metadataManager.toggleTrackLike(track),
      ),
      ContextMenuAction(
        id: 'playlist-add',
        label: 'Add to Playlist',
        icon: Icons.playlist_add,
        onSelected: (_) async {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add to playlist placeholder')),
          );
        },
      ),
      ContextMenuAction(
        id: 'cache-toggle',
        label: isDownloading
            ? 'Downloading (${(progress * 100).toStringAsFixed(0)}%)'
            : (isCached ? 'Remove from Audio Cache' : 'Add to Audio Cache'),
        icon: isCached ? Icons.delete_outline : Icons.download_outlined,
        iconColor: isCached ? activeIconColor : null,
        enabled: !isDownloading,
        onSelected: (_) async {
          if (isCached) {
            await cacheManager.removeFromCache(track.id);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Removed from audio cache')),
            );
            return;
          }
          final player = context.read<global_audio_player.WispAudioHandler>();
          final result = await player.downloadTrack(track);
          if (!context.mounted) return;
          final message = switch (result) {
            QueueDownloadResult.queued => 'Queued track for download',
            QueueDownloadResult.alreadyCached => 'Track already cached',
            QueueDownloadResult.alreadyQueued =>
              'Track already in download queue',
            QueueDownloadResult.blockedByNetworkPolicy =>
              'Downloads blocked by your WiFi/Ethernet-only setting',
            QueueDownloadResult.blockedByNetworkOnlyMode =>
              'Downloads blocked because Network-only mode is enabled',
            QueueDownloadResult.storageLimitReached =>
              'Download failed: Storage limit reached',
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
      ),
      ContextMenuAction(
        id: 'search-alternatives',
        label: 'Search Alternatives',
        icon: Icons.ondemand_video,
        onSelected: (_) async {
          final player = context.read<global_audio_player.WispAudioHandler>();
          final previousVideoId = YouTubeProvider.getCachedVideoId(track.id);
          final selectedVideoId = await AppNavigation.instance
              .openYouTubeAlternatives(track);
          if (!context.mounted || selectedVideoId == null) return;

          final hasChanged = selectedVideoId.isEmpty
              ? previousVideoId != null
              : previousVideoId != selectedVideoId;

          if (selectedVideoId.isEmpty) {
            await YouTubeProvider.removeCachedVideoId(track.id);
            if (hasChanged) {
              await player.onYouTubeAlternativeUpdated(
                track.id,
                previousVideoId: previousVideoId,
              );
            }
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('YouTube mapping cleared')),
            );
            return;
          }
          await YouTubeProvider.setCachedVideoId(track.id, selectedVideoId);
          if (hasChanged) {
            await player.onYouTubeAlternativeUpdated(
              track.id,
              previousVideoId: previousVideoId,
            );
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('YouTube alternative saved')),
          );
        },
      ),
      ...additionalActions,
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share,
        onSelected: (_) => copySpotifyShareUrl(
          context,
          source: track.source,
          type: 'track',
          id: track.id,
        ),
      ),
      if (hasAlbum)
        ContextMenuAction(
          id: 'go-album',
          label: 'Go to Album',
          icon: Icons.album,
          onSelected: (_) async {
            final album = track.album!;
            if (onBeforeNavigate != null) {
              await onBeforeNavigate();
              if (!context.mounted) return;
            }
            AppNavigation.instance.openSharedList(
              context,
              id: album.id,
              type: SharedListType.album,
              initialTitle: album.title,
              initialThumbnailUrl: album.thumbnailUrl,
            );
          },
        ),
      if (track.artists.length == 1)
        ContextMenuAction(
          id: 'go-artist',
          label: 'Go to Artist',
          icon: Icons.person,
          onSelected: (_) async {
            final artist = track.artists.first;
            if (onBeforeNavigate != null) {
              await onBeforeNavigate();
              if (!context.mounted) return;
            }
            AppNavigation.instance.openArtist(
              context,
              artistId: artist.id,
              initialArtist: artist,
            );
          },
        )
      else
        ContextMenuAction(
          id: 'artists-submenu',
          label: 'Artists',
          icon: Icons.groups,
          children: [
            for (final artist in track.artists)
              ContextMenuAction(
                id: 'artist-${artist.id}',
                label: artist.name,
                icon: Icons.person_outline,
                onSelected: (_) async {
                  if (onBeforeNavigate != null) {
                    await onBeforeNavigate();
                    if (!context.mounted) return;
                  }
                  AppNavigation.instance.openArtist(
                    context,
                    artistId: artist.id,
                    initialArtist: artist,
                  );
                },
              ),
          ],
        ),
      if (isDebugMode)
        ContextMenuAction(
          id: 'inspect-element',
          label: 'Inspect Element',
          icon: Icons.code,
          onSelected: (_) => TrackInspectDialog.show(context, track),
        ),
    ];


    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: effectiveAnchorRect,
      globalPosition: globalPosition,
      mobileHeaderBuilder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: CachedNetworkImage(
                    imageUrl: track.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[900],
                      child: Icon(Icons.music_note, color: Colors.grey[600]),
                    ),
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[850]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artists.map((artist) => artist.name).join(', '),
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(_sourceIcon(track.source), color: Colors.grey[300]),
            ],
          ),
        );
      },
    );
  }

  static Future<void> showPlaylistMenu(
    BuildContext context, {
    required GenericPlaylist playlist,
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final folderState = context.read<LibraryFolderState>();
    final folders = folderState.folders;
    final currentFolderId = folderState.folderIdForPlaylist(playlist.id);

    final moveChildren = <ContextMenuAction>[
      ContextMenuAction(
        id: 'move-none',
        label: currentFolderId == null ? '✓ No Folder' : 'No Folder',
        icon: Icons.folder_off_outlined,
        onSelected: (_) async {
          await folderState.movePlaylistIntoFolder(playlist.id, null);
          if (context.mounted && currentFolderId != null) {
            context.read<MetadataManager>().removePlaylistFromFolder(
              playlistId: playlist.id,
              source: playlist.source,
            );
          }
        },
      ),
      for (final folder in folders)
        ContextMenuAction(
          id: 'move-${folder.id}',
          label: currentFolderId == folder.id
              ? '✓ ${folder.title}'
              : folder.title,
          icon: Icons.folder,
          onSelected: (_) async {
            await folderState.movePlaylistIntoFolder(playlist.id, folder.id);
            if (context.mounted) {
              context.read<MetadataManager>().addPlaylistToFolder(
                playlistId: playlist.id,
                folderId: folder.id,
                source: playlist.source,
              );
            }
          },
        ),
    ];

    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'add-queue',
        label: 'Add to Queue',
        icon: Icons.queue_music,
        onSelected: (_) async {
          final tracks = await _resolvePlaylistTracks(context, playlist);
          if (!context.mounted) return;
          await _appendTracksToQueue(context, tracks);
        },
      ),
      ContextMenuAction(
        id: 'add-tastes',
        label: 'Add to Tastes',
        icon: Icons.auto_awesome,
        onSelected: (_) async {
          final tracks = await _resolveAllPlaylistTracks(context, playlist);
          if (tracks.isEmpty) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No tracks available in playlist')),
            );
            return;
          }
          await ListeningHabitsService.instance.enqueueTasteIngestion(
            tracks,
            sourceTitle: playlist.title,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Adding ${tracks.length} songs to your tastes in the background...',
              ),
            ),
          );
        },
      ),
      ContextMenuAction(
        id: 'edit-details',
        label: 'Edit Details',
        icon: Icons.edit,
        onSelected: (_) =>
            PlaylistFolderModals.showRenamePlaylistDialog(context, playlist),
      ),
      ContextMenuAction(
        id: 'delete',
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: (_) async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('Delete playlist?'),
                content: const Text(
                  'Delete confirmation is still a placeholder for now.',
                ),
                actions: [
                  GenericTextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  GenericFilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              );
            },
          );
          if (confirm != true || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delete playlist placeholder')),
          );
        },
      ),
      ContextMenuAction(
        id: 'download',
        label: 'Download',
        icon: Icons.download,
        children: [
          ContextMenuAction(
            id: 'download-meta',
            label: 'Download Metadata',
            icon: Icons.description_outlined,
            onSelected: (_) async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download metadata placeholder')),
              );
            },
          ),
          ContextMenuAction(
            id: 'download-cache',
            label: 'Download Audio',
            icon: Icons.download_outlined,
            onSelected: (_) async {
              final tracks = await _resolvePlaylistTracks(context, playlist);
              if (!context.mounted) return;
              if (tracks.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No tracks available to download'),
                  ),
                );
                return;
              }
              final player = context
                  .read<global_audio_player.WispAudioHandler>();
              final results = await player.downloadTracks(tracks);
              if (!context.mounted) return;
              final queued = results[QueueDownloadResult.queued] ?? 0;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Queued $queued track${queued == 1 ? '' : 's'} for download',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      if (currentFolderId != null)
        ContextMenuAction(
          id: 'remove-from-folder',
          label: 'Remove from Folder',
          icon: Icons.folder_off_outlined,
          onSelected: (_) async {
            await folderState.movePlaylistIntoFolder(playlist.id, null);
            if (context.mounted) {
              context.read<MetadataManager>().removePlaylistFromFolder(
                playlistId: playlist.id,
                source: playlist.source,
              );
            }
          },
        ),
      ContextMenuAction(
        id: 'move-folder',
        label: 'Move to Folder',
        icon: Icons.folder_open,
        children: moveChildren,
      ),
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share,
        onSelected: (_) => copySpotifyShareUrl(
          context,
          source: playlist.source,
          type: 'playlist',
          id: playlist.id,
        ),
      ),
    ];

    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: anchorRect,
      globalPosition: globalPosition,
    );
  }

  static GenericAlbum albumFrom(dynamic album) {
    if (album is GenericAlbum) return album;
    if (album is GenericSimpleAlbum) return album.toAlbum();
    throw ArgumentError.value(
      album,
      'album',
      'Expected GenericAlbum or GenericSimpleAlbum',
    );
  }

  static Future<void> showAlbumMenu(
    BuildContext context, {
    required dynamic album,
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final resolvedAlbum = albumFrom(album);
    final libraryState = context.read<LibraryState>();
    final isSaved = libraryState.isAlbumSaved(resolvedAlbum.id);
    final activeIconColor = Theme.of(context).colorScheme.primary;

    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'toggle-library',
        label: isSaved ? 'Remove from Library' : 'Add to Library',
        icon: isSaved ? Icons.bookmark_remove : Icons.bookmark_add,
        iconColor: isSaved ? activeIconColor : null,
        onSelected: (_) async {
          final metadataManager = context.read<MetadataManager>();
          if (!metadataManager.isAuthenticated) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Provider is not connected.'),
              ),
            );
            return;
          }
          try {
            if (isSaved) {
              await metadataManager.unsaveAlbum(resolvedAlbum.id, source: resolvedAlbum.source);
              libraryState.removeAlbum(resolvedAlbum.id);
            } else {
              await metadataManager.saveAlbum(resolvedAlbum.id, source: resolvedAlbum.source);
              libraryState.addAlbum(resolvedAlbum);
            }
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isSaved ? 'Album removed from library' : 'Album saved',
                ),
              ),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update album: $e')),
            );
          }
        },
      ),
      ContextMenuAction(
        id: 'add-queue',
        label: 'Add to Queue',
        icon: Icons.queue_music,
        onSelected: (_) async {
          final tracks = await _resolveAlbumTracks(context, resolvedAlbum);
          if (!context.mounted) return;
          await _appendTracksToQueue(context, tracks);
        },
      ),
      ContextMenuAction(
        id: 'add-tastes',
        label: 'Add to Tastes',
        icon: Icons.auto_awesome,
        onSelected: (_) async {
          final tracks = await _resolveAlbumTracks(context, resolvedAlbum);
          if (tracks.isEmpty) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No tracks available in album')),
            );
            return;
          }
          await ListeningHabitsService.instance.enqueueTasteIngestion(
            tracks,
            sourceTitle: resolvedAlbum.title,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Adding ${tracks.length} songs to your tastes in the background...',
              ),
            ),
          );
        },
      ),
      ContextMenuAction(
        id: 'download',
        label: 'Download',
        icon: Icons.download,
        children: [
          ContextMenuAction(
            id: 'download-meta',
            label: 'Download Metadata',
            icon: Icons.description_outlined,
            onSelected: (_) async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download metadata placeholder')),
              );
            },
          ),
          ContextMenuAction(
            id: 'download-cache',
            label: 'Download Audio',
            icon: Icons.download_outlined,
            onSelected: (_) async {
              final tracks = await _resolveAlbumTracks(context, resolvedAlbum);
              if (!context.mounted) return;
              if (tracks.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No tracks available to download'),
                  ),
                );
                return;
              }
              final player = context
                  .read<global_audio_player.WispAudioHandler>();
              final results = await player.downloadTracks(tracks);
              if (!context.mounted) return;
              final queued = results[QueueDownloadResult.queued] ?? 0;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Queued $queued track${queued == 1 ? '' : 's'} for download',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share,
        onSelected: (_) => copySpotifyShareUrl(
          context,
          source: resolvedAlbum.source,
          type: 'album',
          id: resolvedAlbum.id,
        ),
      ),
    ];

    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: anchorRect,
      globalPosition: globalPosition,
    );
  }

  static Future<void> showArtistMenu(
    BuildContext context, {
    required GenericSimpleArtist artist,
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final libraryState = context.read<LibraryState>();
    final isFollowed = libraryState.isArtistFollowed(artist.id);
    final activeIconColor = Theme.of(context).colorScheme.primary;

    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'follow-toggle',
        label: isFollowed ? 'Unfollow' : 'Follow',
        icon: isFollowed ? Icons.person_remove : Icons.person_add,
        iconColor: isFollowed ? activeIconColor : null,
        onSelected: (_) async {
          final metadataManager = context.read<MetadataManager>();
          if (!metadataManager.isAuthenticated) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Provider is not connected.'),
              ),
            );
            return;
          }
          try {
            if (isFollowed) {
              await metadataManager.unfollowArtist(artist.id, source: artist.source);
              libraryState.removeArtist(artist.id);
            } else {
              await metadataManager.followArtist(artist.id, source: artist.source);
              libraryState.addArtist(artist);
            }
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isFollowed ? 'Unfollowed artist' : 'Followed artist',
                ),
              ),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to update artist follow state: $e'),
              ),
            );
          }
        },
      ),
      ContextMenuAction(
        id: 'download-metadata',
        label: 'Download Metadata',
        icon: Icons.download_outlined,
        onSelected: (_) async {
          try {
            await context.read<MetadataManager>().getArtistInfo(
              artist.id,
              source: artist.source,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Artist metadata refreshed')),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to refresh artist metadata: $e')),
            );
          }
        },
      ),
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share,
        onSelected: (_) => copySpotifyShareUrl(
          context,
          source: artist.source,
          type: 'artist',
          id: artist.id,
        ),
      ),
    ];

    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: anchorRect,
      globalPosition: globalPosition,
    );
  }

  static Future<void> showFolderMenu(
    BuildContext context, {
    required PlaylistFolder folder,
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'rename',
        label: 'Rename',
        icon: Icons.edit,
        onSelected: (_) =>
            PlaylistFolderModals.showRenameFolderDialog(context, folder),
      ),
      ContextMenuAction(
        id: 'change-thumbnail',
        label: 'Change thumbnail',
        icon: Icons.image_outlined,
        onSelected: (_) =>
            PlaylistFolderModals.showChangeThumbnailDialog(context, folder),
      ),
      ContextMenuAction(
        id: 'delete',
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: (_) =>
            context.read<LibraryFolderState>().deleteFolder(folder.id),
      ),
    ];

    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: anchorRect,
      globalPosition: globalPosition,
    );
  }
}
