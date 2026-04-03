library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wisp/views/list_detail.dart';

import '../models/library_folder.dart';
import '../models/metadata_models.dart';
import '../providers/audio/youtube.dart';
import '../providers/connect/connect_session_provider.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/library_state.dart';
import '../providers/metadata/spotify_internal.dart';
import '../services/app_navigation.dart';
import '../services/cache_manager.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../views/youtube_alternatives.dart';
import 'adaptive_context_menu.dart';
import 'playlist_folder_modals.dart';

class EntityContextMenus {
  static bool _isSpotifySource(SongSource source) {
    return source == SongSource.spotify || source == SongSource.spotifyInternal;
  }

  static String _idWithoutPrefix(String id) {
    if (!id.contains(':')) return id;
    return id.split(':').last;
  }

  static Future<void> copySpotifyShareUrl(
    BuildContext context, {
    required SongSource source,
    required String type,
    required String id,
  }) async {
    if (!_isSpotifySource(source)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share is only available for Spotify sources')),
      );
      return;
    }
    final url = 'https://open.spotify.com/$type/${_idWithoutPrefix(id)}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  static IconData _sourceIcon(SongSource source) {
    switch (source) {
      case SongSource.youtube:
        return Icons.ondemand_video;
      case SongSource.soundcloud:
        return Icons.cloud;
      case SongSource.spotify:
      case SongSource.spotifyInternal:
      case SongSource.local:
        return Icons.music_note;
    }
  }

  static Future<List<GenericSong>> _resolvePlaylistTracks(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final fromModel = playlist.songs
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
      final spotify = context.read<SpotifyInternalProvider>();
      final full = await spotify.getPlaylistInfo(playlist.id);
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
      final spotify = context.read<SpotifyInternalProvider>();
      final full = await spotify.getAlbumInfo(album.id);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks available')),
      );
      return;
    }
    final player = context.read<global_audio_player.WispAudioHandler>();
    final connect = context.read<ConnectSessionProvider>();

    final mergedQueue = List<GenericSong>.from(player.queueTracks);
    final seen = mergedQueue
        .map((track) => '${track.source.name}:${track.id}')
        .toSet();

    var added = 0;
    for (final track in tracks) {
      final key = '${track.source.name}:${track.id}';
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
      final found = mergedQueue.indexWhere((track) => track.id == currentTrackId);
      if (found >= 0) startIndex = found;
    }

    await connect.requestSetQueue(
      mergedQueue,
      startIndex: startIndex,
      play: player.currentTrack != null ? player.isPlaying : false,
      contextType: player.playbackContextType,
      contextName: player.playbackContextName,
      contextID: player.playbackContextID,
      contextSource: player.playbackContextSource,
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
  }) async {
    final spotifyInternal = context.read<SpotifyInternalProvider>();
    await spotifyInternal.ensureLikedTracksLoaded();
    final activeIconColor = Theme.of(context).colorScheme.primary;

    final cacheManager = AudioCacheManager.instance;
    final isLiked = spotifyInternal.isTrackLiked(track.id);
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
        onSelected: (_) => spotifyInternal.toggleTrackLike(track),
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
            QueueDownloadResult.alreadyQueued => 'Track already in download queue',
            QueueDownloadResult.blockedByNetworkPolicy =>
              'Downloads blocked by your WiFi/Ethernet-only setting',
            QueueDownloadResult.blockedByNetworkOnlyMode =>
              'Downloads blocked because Network-only mode is enabled',
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
      ),
      ContextMenuAction(
        id: 'search-alternatives',
        label: 'Search Alternatives',
        icon: Icons.ondemand_video,
        onSelected: (_) async {
          final player = context.read<global_audio_player.WispAudioHandler>();
          final previousVideoId = YouTubeProvider.getCachedVideoId(track.id);
          final selectedVideoId = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => YouTubeAlternativesView(track: track)),
          );
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
                  AppNavigation.instance.openArtist(
                    context,
                    artistId: artist.id,
                    initialArtist: artist,
                  );
                },
              ),
          ],
        ),
    ];

    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: anchorRect,
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
                    placeholder: (context, url) => Container(color: Colors.grey[850]),
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
        onSelected: (_) => folderState.movePlaylistIntoFolder(playlist.id, null),
      ),
      for (final folder in folders)
        ContextMenuAction(
          id: 'move-${folder.id}',
          label: currentFolderId == folder.id ? '✓ ${folder.title}' : folder.title,
          icon: Icons.folder,
          onSelected: (_) => folderState.movePlaylistIntoFolder(playlist.id, folder.id),
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
        id: 'edit-details',
        label: 'Edit Details',
        icon: Icons.edit,
        onSelected: (_) => PlaylistFolderModals.showRenamePlaylistDialog(context, playlist),
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
                content: const Text('Delete confirmation is still a placeholder for now.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
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
                  const SnackBar(content: Text('No tracks available to download')),
                );
                return;
              }
              final player = context.read<global_audio_player.WispAudioHandler>();
              final results = await player.downloadTracks(tracks);
              if (!context.mounted) return;
              final queued = results[QueueDownloadResult.queued] ?? 0;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Queued $queued track${queued == 1 ? '' : 's'} for download'),
                ),
              );
            },
          ),
        ],
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

  static Future<void> showAlbumMenu(
    BuildContext context, {
    required GenericAlbum album,
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final libraryState = context.read<LibraryState>();
    final isSaved = libraryState.isAlbumSaved(album.id);
    final activeIconColor = Theme.of(context).colorScheme.primary;

    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'toggle-library',
        label: isSaved ? 'Remove from Library' : 'Add to Library',
        icon: isSaved ? Icons.bookmark_remove : Icons.bookmark_add,
        iconColor: isSaved ? activeIconColor : null,
        onSelected: (_) async {
          final spotifyInternal = context.read<SpotifyInternalProvider>();
          if (!spotifyInternal.isAuthenticated) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Spotify (Internal) is not connected.')),
            );
            return;
          }
          try {
            if (isSaved) {
              await spotifyInternal.unsaveAlbum(album.id);
              libraryState.removeAlbum(album.id);
            } else {
              await spotifyInternal.saveAlbum(album.id);
              libraryState.addAlbum(album);
            }
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(isSaved ? 'Album removed from library' : 'Album saved')),
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
          final tracks = await _resolveAlbumTracks(context, album);
          if (!context.mounted) return;
          await _appendTracksToQueue(context, tracks);
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
              final tracks = await _resolveAlbumTracks(context, album);
              if (!context.mounted) return;
              if (tracks.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No tracks available to download')),
                );
                return;
              }
              final player = context.read<global_audio_player.WispAudioHandler>();
              final results = await player.downloadTracks(tracks);
              if (!context.mounted) return;
              final queued = results[QueueDownloadResult.queued] ?? 0;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Queued $queued track${queued == 1 ? '' : 's'} for download'),
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
          source: album.source,
          type: 'album',
          id: album.id,
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
          final spotifyInternal = context.read<SpotifyInternalProvider>();
          if (!spotifyInternal.isAuthenticated) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Spotify (Internal) is not connected.')),
            );
            return;
          }
          try {
            if (isFollowed) {
              await spotifyInternal.unfollowArtist(artist.id);
              libraryState.removeArtist(artist.id);
            } else {
              await spotifyInternal.followArtist(artist.id);
              libraryState.addArtist(artist);
            }
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(isFollowed ? 'Unfollowed artist' : 'Followed artist')),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update artist follow state: $e')),
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
            await context.read<SpotifyInternalProvider>().getArtistInfo(artist.id);
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
        onSelected: (_) => PlaylistFolderModals.showRenameFolderDialog(context, folder),
      ),
      ContextMenuAction(
        id: 'change-thumbnail',
        label: 'Change thumbnail',
        icon: Icons.image_outlined,
        onSelected: (_) => PlaylistFolderModals.showChangeThumbnailDialog(context, folder),
      ),
      ContextMenuAction(
        id: 'delete',
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: (_) => context.read<LibraryFolderState>().deleteFolder(folder.id),
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