/// Universal track context menu for mobile and desktop
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/metadata_models.dart';
import '../utils/logger.dart';
import '../views/list_detail.dart';
import '../views/artist_detail.dart';
import '../widgets/navigation.dart';
import '../providers/audio/player.dart';
import '../providers/audio/youtube.dart';
import '../services/cache_manager.dart';

/// Shows a context menu for a track
/// On mobile: bottom sheet drawer
/// On desktop: right-click context menu at cursor position
class TrackContextMenu {
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Show the context menu for a track
  /// [context] - BuildContext for navigation
  /// [track] - The track to show menu for
  /// [position] - For desktop, the cursor position to show menu at
  /// [playlistId] - Optional playlist ID if track is from a playlist
  /// [playlistName] - Optional playlist name for "Go to Playlist" option
  /// [playlists] - Playlists for navigation
  /// [albums] - Albums for navigation
  /// [artists] - Artists for navigation
  static void show({
    required BuildContext context,
    required GenericSong track,
    Offset? position,
    String? playlistId,
    String? playlistName,
    List<GenericPlaylist> playlists = const [],
    List<GenericAlbum> albums = const [],
    List<GenericSimpleArtist> artists = const [],
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  }) {
    if (_isMobile) {
      _showMobileMenu(
        context: context,
        track: track,
        playlistId: playlistId,
        playlistName: playlistName,
        playlists: playlists,
        albums: albums,
        artists: artists,
        currentLibraryView: currentLibraryView,
        currentNavIndex: currentNavIndex,
      );
    } else {
      _showDesktopMenu(
        context: context,
        track: track,
        position: position ?? Offset.zero,
        playlistId: playlistId,
        playlistName: playlistName,
        playlists: playlists,
        albums: albums,
        artists: artists,
        currentLibraryView: currentLibraryView,
        currentNavIndex: currentNavIndex,
      );
    }
  }

  static void _showMobileMenu({
    required BuildContext context,
    required GenericSong track,
    String? playlistId,
    String? playlistName,
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.7,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF282828),
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
                // Track info header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 56,
                          height: 56,
                          color: Colors.grey[900],
                          child: track.thumbnailUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: track.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Icon(Icons.music_note, color: Colors.grey[700]),
                                )
                              : Icon(Icons.music_note, color: Colors.grey[700]),
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
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artists.map((a) => a.name).join(', '),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: Colors.grey[700], height: 1),
                // Menu items
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _buildMobileMenuItem(
                        icon: Icons.share,
                        label: 'Share',
                        onTap: () {
                          Navigator.pop(context);
                          _handleShare(track);
                        },
                      ),
                      _buildDownloadMenuItem(context, track, isMobile: true),
                      _buildChangeVideoIdMenuItem(context, track, isMobile: true),
                      if (track.album != null)
                        _buildMobileMenuItem(
                          icon: Icons.album,
                          label: 'Go to Album',
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToAlbum(
                              context,
                              track.album!.id,
                              track.album!.title,
                              track.thumbnailUrl,
                              playlists,
                              albums,
                              artists,
                              currentLibraryView,
                              currentNavIndex,
                            );
                          },
                        ),
                      if (playlistId != null && playlistName != null)
                        _buildMobileMenuItem(
                          icon: Icons.playlist_play,
                          label: 'Go to Playlist',
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToPlaylist(
                              context,
                              playlistId,
                              playlistName,
                              null,
                              playlists,
                              albums,
                              artists,
                              currentLibraryView,
                              currentNavIndex,
                            );
                          },
                        ),
                      // Artists section
                      if (track.artists.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            'Artists',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ...track.artists.map((artist) => _buildMobileMenuItem(
                              icon: Icons.person,
                              label: artist.name,
                              onTap: () {
                                Navigator.pop(context);
                                _navigateToArtist(
                                  context,
                                  artist,
                                  playlists,
                                  albums,
                                  artists,
                                  currentLibraryView,
                                  currentNavIndex,
                                );
                              },
                            )),
                      ],
                    ],
                  ),
                ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static Widget _buildMobileMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? Colors.white, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showDesktopMenu({
    required BuildContext context,
    required GenericSong track,
    required Offset position,
    String? playlistId,
    String? playlistName,
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  }) {
    final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(position);
    const edgePadding = 8.0;
    const menuWidth = 260.0;
    const menuMaxHeight = 360.0;

    final maxDx = (overlay.size.width - menuWidth - edgePadding).clamp(0.0, double.infinity);
    final maxDy =
      (overlay.size.height - menuMaxHeight - edgePadding).clamp(0.0, double.infinity);

    final dx = localPosition.dx.clamp(edgePadding, maxDx);
    final dy = localPosition.dy.clamp(edgePadding, maxDy);

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              left: dx,
              top: dy,
              child: Material(
                color: const Color(0xFF282828),
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 220),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildDesktopMenuButton(
                            context: dialogContext,
                            child: _buildDesktopMenuItem(Icons.share, 'Share'),
                            onTap: () => _handleShare(track),
                          ),
                          const SizedBox(height: 4),
                          _buildDesktopMenuButton(
                            context: dialogContext,
                            child: _buildDownloadMenuItem(context, track, isMobile: false),
                            onTap: () => _handleDownload(context, track),
                          ),
                          const SizedBox(height: 4),
                          _buildDesktopMenuButton(
                            context: dialogContext,
                            child: _buildChangeVideoIdMenuItem(
                              context,
                              track,
                              isMobile: false,
                            ),
                            onTap: () => _showChangeVideoIdDialog(context, track),
                          ),
                          if (track.album != null) ...[
                            const SizedBox(height: 4),
                            _buildDesktopMenuButton(
                              context: dialogContext,
                              child: _buildDesktopMenuItem(Icons.album, 'Go to Album'),
                              onTap: () {
                                _navigateToAlbum(
                                  context,
                                  track.album!.id,
                                  track.album!.title,
                                  track.thumbnailUrl,
                                  playlists,
                                  albums,
                                  artists,
                                  currentLibraryView,
                                  currentNavIndex,
                                );
                              },
                            ),
                          ],
                          if (playlistId != null && playlistName != null) ...[
                            const SizedBox(height: 4),
                            _buildDesktopMenuButton(
                              context: dialogContext,
                              child: _buildDesktopMenuItem(
                                Icons.playlist_play,
                                'Go to Playlist',
                              ),
                              onTap: () {
                                _navigateToPlaylist(
                                  context,
                                  playlistId,
                                  playlistName,
                                  null,
                                  playlists,
                                  albums,
                                  artists,
                                  currentLibraryView,
                                  currentNavIndex,
                                );
                              },
                            ),
                          ],
                          if (track.artists.length == 1) ...[
                            const SizedBox(height: 4),
                            _buildDesktopMenuButton(
                              context: dialogContext,
                              child: _buildDesktopMenuItem(Icons.person, 'Go to Artist'),
                              onTap: () {
                                _navigateToArtist(
                                  context,
                                  track.artists.first,
                                  playlists,
                                  albums,
                                  artists,
                                  currentLibraryView,
                                  currentNavIndex,
                                );
                              },
                            ),
                          ],
                          if (track.artists.length > 1) ...[
                            const SizedBox(height: 6),
                            _buildDesktopMenuSectionHeader('Artists'),
                            const SizedBox(height: 2),
                            ...track.artists.map((artist) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildDesktopMenuButton(
                                    context: dialogContext,
                                    child: _buildDesktopMenuItem(
                                      Icons.person,
                                      artist.name,
                                    ),
                                    onTap: () {
                                      _navigateToArtist(
                                        context,
                                        artist,
                                        playlists,
                                        albums,
                                        artists,
                                        currentLibraryView,
                                        currentNavIndex,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildDesktopMenuItem(IconData icon, String label, {Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, color: iconColor ?? Colors.grey[300], size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }

  static Widget _buildDesktopMenuButton({
    required BuildContext context,
    required Widget child,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );
  }

  static Widget _buildDesktopMenuSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  static void _handleShare(GenericSong track) {
    logger.d('Track ID: ${track.id}');
  }

  static Future<void> _handleDownload(BuildContext context, GenericSong track) async {
    final cacheManager = AudioCacheManager.instance;
    final player = context.read<AudioPlayerProvider>();
    
    // Check if already cached
    if (cacheManager.isTrackCached(track.id)) {
      // Show option to remove from cache
      final shouldRemove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Remove from Cache', style: TextStyle(color: Colors.white)),
          content: Text(
            'This track is already cached. Would you like to remove it?',
            style: TextStyle(color: Colors.grey[400]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      
      if (shouldRemove == true) {
        await player.removeFromCache(track.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Track removed from cache'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      return;
    }
    
    // Check if already downloading
    if (cacheManager.isDownloading(track.id)) {
      // Cancel download
      player.cancelDownload(track.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download cancelled'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    // Start download
    try {
      await player.downloadTrack(track);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading "${track.title}"...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start download: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// Build download menu item with dynamic state
  static Widget _buildDownloadMenuItem(BuildContext context, GenericSong track, {required bool isMobile}) {
    final cacheManager = AudioCacheManager.instance;
    final isCached = cacheManager.isTrackCached(track.id);
    final isDownloading = cacheManager.isDownloading(track.id);
    final progress = cacheManager.getDownloadProgress(track.id);
    
    IconData icon;
    String label;
    Color? iconColor;
    
    if (isCached) {
      icon = Icons.download_done;
      label = 'Remove from Cache';
      iconColor = const Color(0xFF1DB954);
    } else if (isDownloading) {
      icon = Icons.downloading;
      label = progress != null ? 'Downloading ${(progress * 100).toInt()}%' : 'Downloading...';
      iconColor = const Color(0xFF1DB954);
    } else {
      icon = Icons.download_outlined;
      label = 'Download';
      iconColor = null;
    }
    
    if (isMobile) {
      return _buildMobileMenuItem(
        icon: icon,
        label: label,
        iconColor: iconColor,
        onTap: () {
          Navigator.pop(context);
          _handleDownload(context, track);
        },
      );
    } else {
      return _buildDesktopMenuItem(icon, label, iconColor: iconColor);
    }
  }

  static Widget _buildChangeVideoIdMenuItem(
    BuildContext context,
    GenericSong track, {
    required bool isMobile,
  }) {
    final hasOverride = YouTubeProvider.getCachedVideoId(track.id) != null;
    final label = hasOverride ? 'Change YouTube Video ID' : 'Set YouTube Video ID';
    final icon = Icons.video_settings;

    if (isMobile) {
      return _buildMobileMenuItem(
        icon: icon,
        label: label,
        onTap: () {
          Navigator.pop(context);
          _showChangeVideoIdDialog(context, track);
        },
      );
    }

    return _buildDesktopMenuItem(icon, label);
  }

  static Future<void> _showChangeVideoIdDialog(
    BuildContext context,
    GenericSong track,
  ) async {
    final existing = YouTubeProvider.getCachedVideoId(track.id) ?? '';
    final controller = TextEditingController(text: existing);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text(
          'YouTube Video ID',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set a custom YouTube video ID for this track. Leave empty to clear.',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g., dQw4w9WgXcQ',
                hintStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final input = controller.text.trim();
    if (input.isEmpty) {
      await YouTubeProvider.removeCachedVideoId(track.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cleared YouTube video ID override')),
        );
      }
      return;
    }

    await YouTubeProvider.setCachedVideoId(track.id, input);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube video ID updated')),
      );
    }
  }

  static void _navigateToAlbum(
    BuildContext context,
    String albumId,
    String title,
    String thumbnailUrl,
    List<GenericPlaylist> playlists,
    List<GenericAlbum> albums,
    List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  ) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            SharedListDetailView(
          id: albumId,
          type: SharedListType.album,
          initialTitle: title,
          initialThumbnailUrl: thumbnailUrl,
          playlists: playlists,
          albums: albums,
          artists: artists,
          initialLibraryView: currentLibraryView ?? LibraryView.albums,
          initialNavIndex: currentNavIndex ?? 0,
        ),
      ),
    );
  }

  static void _navigateToPlaylist(
    BuildContext context,
    String playlistId,
    String title,
    String? thumbnailUrl,
    List<GenericPlaylist> playlists,
    List<GenericAlbum> albums,
    List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  ) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            SharedListDetailView(
          id: playlistId,
          type: SharedListType.playlist,
          initialTitle: title,
          initialThumbnailUrl: thumbnailUrl,
          playlists: playlists,
          albums: albums,
          artists: artists,
          initialLibraryView: currentLibraryView ?? LibraryView.playlists,
          initialNavIndex: currentNavIndex ?? 0,
        ),
      ),
    );
  }

  static void _navigateToArtist(
    BuildContext context,
    GenericSimpleArtist artist,
    List<GenericPlaylist> playlists,
    List<GenericAlbum> albums,
    List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  ) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArtistDetailView(
          artistId: artist.id,
          initialArtist: artist,
          playlists: playlists,
          albums: albums,
          artists: artists,
          initialLibraryView: currentLibraryView ?? LibraryView.artists,
          initialNavIndex: currentNavIndex ?? 0,
        ),
      ),
    );
  }
}
