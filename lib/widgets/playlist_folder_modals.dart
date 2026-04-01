/// Playlist folder dialogs and menus
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/models/local_playlist.dart';

import '../models/library_folder.dart';
import '../models/metadata_models.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/local_playlists.dart';
import '../providers/metadata/spotify.dart';
import '../providers/metadata/spotify_internal.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/navigation_history.dart';

class PlaylistFolderModals {
  static OverlayEntry? _activeSubmenu;
  static BuildContext? _submenuParentContext;

  static void _showSnack(BuildContext context, SnackBar snackBar) {
    if (!context.mounted) return;
    final localMessenger = ScaffoldMessenger.maybeOf(context);
    if (localMessenger != null) {
      try {
        localMessenger.showSnackBar(snackBar);
        return;
      } catch (_) {
        // Fall through to root messenger.
      }
    }

    final rootContext = NavigationHistory.instance.navigatorKey.currentContext;
    final rootMessenger = rootContext == null
        ? null
        : ScaffoldMessenger.maybeOf(rootContext);
    if (rootMessenger == null) return;
    try {
      rootMessenger.showSnackBar(snackBar);
    } catch (_) {
      // No scaffold available, ignore.
    }
  }

  static void _showWriteBlockedSnack(BuildContext context) {
    _showSnack(
      context,
      const SnackBar(
        content: Text('Spotify writing is disabled in Preferences.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static void _showSyncErrorSnack(BuildContext context, String message) {
    _showSnack(
      context,
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static Future<void> _syncRenameToProvider(
    BuildContext context,
    LocalPlaylist localPlaylist,
    String name,
  ) async {
    if (!localPlaylist.isLinked) return;
    if (!context.read<PreferencesProvider>().allowWriting) {
      _showWriteBlockedSnack(context);
      return;
    }
    final linkedId = localPlaylist.linkedId;
    if (linkedId == null || linkedId.isEmpty) return;
    if (localPlaylist.linkedSource != SongSource.spotifyInternal) {
      _showSyncErrorSnack(
        context,
        'Playlist is not linked to Spotify (Internal).',
      );
      return;
    }
    try {
      await context.read<SpotifyInternalProvider>().renamePlaylist(
            linkedId,
            name,
          );
    } catch (e) {
      _showSyncErrorSnack(context, 'Failed to rename on Spotify: $e');
    }
  }

  static Future<void> _syncDeleteToProvider(
    BuildContext context,
    LocalPlaylist localPlaylist,
  ) async {
    if (!localPlaylist.isLinked) return;
    if (!context.read<PreferencesProvider>().allowWriting) {
      _showWriteBlockedSnack(context);
      return;
    }
    final linkedId = localPlaylist.linkedId;
    if (linkedId == null || linkedId.isEmpty) return;
    if (localPlaylist.linkedSource != SongSource.spotifyInternal) {
      _showSyncErrorSnack(
        context,
        'Playlist is not linked to Spotify (Internal).',
      );
      return;
    }
    try {
      await context.read<SpotifyInternalProvider>().deletePlaylist(linkedId);
    } catch (e) {
      _showSyncErrorSnack(context, 'Failed to delete on Spotify: $e');
    }
  }

  static Future<void> _syncCreateToProvider(
    BuildContext context,
    LocalPlaylist localPlaylist,
  ) async {
    if (!context.read<PreferencesProvider>().allowWriting) {
      _showWriteBlockedSnack(context);
      return;
    }
    final spotifyInternal = context.read<SpotifyInternalProvider>();
    if (!spotifyInternal.isAuthenticated) {
      _showSyncErrorSnack(
        context,
        'Spotify (Internal) is not connected.',
      );
      return;
    }
    String? linkedId;
    try {
      linkedId = await spotifyInternal.createPlaylist(
        name: localPlaylist.title,
      );
    } catch (e) {
      _showSyncErrorSnack(context, 'Failed to create on Spotify: $e');
      return;
    }
    if (linkedId == null || linkedId.isEmpty) {
      _showSyncErrorSnack(context, 'Failed to create Spotify playlist.');
      return;
    }
    await context.read<LocalPlaylistState>().linkToProvider(
          id: localPlaylist.id,
          provider: SongSource.spotifyInternal,
          providerId: linkedId,
        );
  }

  static Future<void> deletePlaylistWithSync(
    BuildContext context,
    String playlistId,
  ) async {
    final localState = context.read<LocalPlaylistState>();
    final localPlaylist = localState.getById(playlistId);
    await localState.deletePlaylist(playlistId);
    if (localPlaylist != null) {
      await _syncDeleteToProvider(context, localPlaylist);
    }
  }

  static void hideAddToFolderSubmenu() {
    _activeSubmenu?.remove();
    _activeSubmenu = null;
    final parentContext = _submenuParentContext;
    _submenuParentContext = null;
    if (parentContext != null) {
      Navigator.of(parentContext).pop();
    }
  }

  static void showAddToFolderSubmenu(
    BuildContext context, {
    required GenericPlaylist playlist,
    required Offset position,
    required BuildContext parentMenuContext,
  }) {
    hideAddToFolderSubmenu();
    _submenuParentContext = parentMenuContext;
    final folderState = context.read<LibraryFolderState>();
    final folders = folderState.folders;
    final currentFolderId = folderState.folderIdForPlaylist(playlist.id);
    final overlay = Overlay.of(context, rootOverlay: true);

    _activeSubmenu = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          left: position.dx,
          top: position.dy,
          child: Material(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 220,
                maxWidth: 280,
              ),
              child: IntrinsicWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (currentFolderId != null)
                        _buildMenuButton(
                          overlayContext,
                          icon: Icons.folder_off_outlined,
                          label: 'Remove from folder',
                          closeMenu: false,
                          onTap: () => folderState.movePlaylistIntoFolder(
                            playlist.id,
                            null,
                          ),
                        ),
                      for (final folder in folders)
                        _buildMenuButton(
                          overlayContext,
                          icon: Icons.folder,
                          label: folder.title,
                          trailing: currentFolderId == folder.id
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.greenAccent,
                                  size: 18,
                                )
                              : null,
                          closeMenu: false,
                          onTap: () => folderState.movePlaylistIntoFolder(
                            playlist.id,
                            folder.id,
                          ),
                        ),
                      _buildMenuButton(
                        overlayContext,
                        icon: Icons.create_new_folder_outlined,
                        label: 'Create folder…',
                        closeMenu: false,
                        onTap: () => showCreateFolderDialog(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_activeSubmenu!);
  }

  static Future<void> showCreateFolderDialog(BuildContext context) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final controller = TextEditingController();
    File? selectedFile;

    Future<void> pickThumbnail(StateSetter setModalState) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final filePath = result?.files.single.path;
      if (filePath == null) return;
      setModalState(() {
        selectedFile = File(filePath);
      });
    }

    Future<void> save(BuildContext modalContext) async {
      final title = controller.text.trim();
      if (title.isEmpty) return;
      await modalContext.read<LibraryFolderState>().createFolder(
            title: title,
            thumbnailFile: selectedFile,
          );
      Navigator.pop(modalContext);
    }

    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1B1B1B),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create folder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Folder title',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _ThumbnailPreview(file: selectedFile),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickThumbnail(setModalState),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Choose thumbnail'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => save(modalContext),
                            child: const Text('Create'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
      return;
    }

    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B1B),
          title: const Text('Create folder', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Folder title',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _ThumbnailPreview(file: selectedFile),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickThumbnail(setModalState),
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choose thumbnail'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            ElevatedButton(
              onPressed: () => save(dialogContext),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> showCreatePlaylistDialog(BuildContext context) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final controller = TextEditingController();
    File? selectedFile;

    Future<void> pickThumbnail(StateSetter setModalState) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final filePath = result?.files.single.path;
      if (filePath == null) return;
      setModalState(() {
        selectedFile = File(filePath);
      });
    }

    Future<void> save(BuildContext modalContext) async {
      final name = controller.text.trim();
      if (name.isEmpty) return;
      final localPlaylist = await modalContext
          .read<LocalPlaylistState>()
          .createPlaylist(title: name, thumbnailFile: selectedFile);
      await _syncCreateToProvider(modalContext, localPlaylist);
      if (modalContext.mounted) {
        Navigator.of(modalContext).pop();
      }
    }

    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1B1B1B),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create playlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Playlist name',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _ThumbnailPreview(file: selectedFile),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickThumbnail(setModalState),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Choose thumbnail'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => save(modalContext),
                            child: const Text('Create'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B1B),
          title: const Text(
            'Create playlist',
            style: TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Playlist name',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _ThumbnailPreview(file: selectedFile),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickThumbnail(setModalState),
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choose thumbnail'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => save(dialogContext),
              child: Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  static Future<void> showRenamePlaylistDialog(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final controller = TextEditingController(text: playlist.title);

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B1B),
          title: const Text(
            'Rename playlist',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final localState = context.read<LocalPlaylistState>();
                final localPlaylist = localState.getById(playlist.id);
                await localState.renamePlaylist(playlist.id, name);
                if (localPlaylist != null) {
                  await _syncRenameToProvider(context, localPlaylist, name);
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  static Future<void> showRenameFolderDialog(
    BuildContext context,
    PlaylistFolder folder,
  ) async {
    final controller = TextEditingController(text: folder.title);
    final isMobile = Platform.isAndroid || Platform.isIOS;

    Future<void> submit(BuildContext modalContext) async {
      final title = controller.text.trim();
      if (title.isEmpty) return;
      await modalContext.read<LibraryFolderState>().renameFolder(folder.id, title);
      Navigator.pop(modalContext);
    }

    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1B1B1B),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Rename folder', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Folder title',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(modalContext),
                        child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => submit(modalContext),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B1B),
          title: const Text('Rename folder', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Folder title',
              hintStyle: TextStyle(color: Colors.grey[500]),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            ElevatedButton(
              onPressed: () => submit(dialogContext),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> showChangeThumbnailDialog(
    BuildContext context,
    PlaylistFolder folder,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final filePath = result?.files.single.path;
    if (filePath == null) return;
    await context.read<LibraryFolderState>().changeFolderThumbnail(
          folder.id,
          File(filePath),
        );
  }

  static Future<void> showChangePlaylistThumbnailDialog(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final filePath = result?.files.single.path;
    if (filePath == null) return;
    await context
        .read<LocalPlaylistState>()
        .updateThumbnail(playlist.id, File(filePath));
  }

  static Future<void> showAddToFolderMenu(
    BuildContext context, {
    required GenericPlaylist playlist,
    Offset? position,
  }) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final folderState = context.read<LibraryFolderState>();
    final folders = folderState.folders;
    final currentFolderId = folderState.folderIdForPlaylist(playlist.id);

    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        backgroundColor: const Color(0xFF1B1B1B),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (currentFolderId != null)
                  ListTile(
                    leading: const Icon(Icons.folder_off_outlined, color: Colors.white),
                    title: const Text('Remove from folder', style: TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(modalContext);
                      await folderState.movePlaylistIntoFolder(playlist.id, null);
                    },
                  ),
                ...folders.map(
                  (folder) => ListTile(
                    leading: const Icon(Icons.folder, color: Colors.white),
                    title: Text(folder.title, style: const TextStyle(color: Colors.white)),
                    trailing: currentFolderId == folder.id
                        ? const Icon(Icons.check, color: Colors.greenAccent)
                        : null,
                    onTap: () async {
                      Navigator.pop(modalContext);
                      await folderState.movePlaylistIntoFolder(playlist.id, folder.id);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined, color: Colors.white),
                  title: const Text('Create folder…', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(modalContext);
                    await showCreateFolderDialog(context);
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final positionOffset = position ?? const Offset(0, 0);
    final menuPosition = overlay.globalToLocal(positionOffset);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (dialogContext) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Stack(
            children: [
              Positioned(
                left: menuPosition.dx,
                top: menuPosition.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
                  child: Material(
                color: const Color(0xFF282828),
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 220,
                    maxWidth: 280,
                  ),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (currentFolderId != null)
                            _buildMenuButton(
                              dialogContext,
                              icon: Icons.folder_off_outlined,
                              label: 'Remove from folder',
                              onTap: () => folderState.movePlaylistIntoFolder(
                                playlist.id,
                                null,
                              ),
                            ),
                          for (final folder in folders)
                            _buildMenuButton(
                              dialogContext,
                              icon: Icons.folder,
                              label: folder.title,
                              trailing: currentFolderId == folder.id
                                  ? const Icon(Icons.check, color: Colors.greenAccent, size: 18)
                                  : null,
                              onTap: () => folderState.movePlaylistIntoFolder(
                                playlist.id,
                                folder.id,
                              ),
                            ),
                          _buildMenuButton(
                            dialogContext,
                            icon: Icons.create_new_folder_outlined,
                            label: 'Create folder…',
                            onTap: () => showCreateFolderDialog(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
              ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    bool closeMenu = true,
  }) {
    return InkWell(
      onTap: () {
        if (closeMenu) {
          Navigator.of(context).pop();
        }
        hideAddToFolderSubmenu();
        final parentContext = _submenuParentContext;
        if (parentContext != null) {
          Navigator.of(parentContext).pop();
          _submenuParentContext = null;
        }
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey[300], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

class _ThumbnailPreview extends StatelessWidget {
  final File? file;

  const _ThumbnailPreview({this.file});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 56,
        color: Colors.grey[850],
        child: file == null
            ? const Icon(Icons.folder, color: Colors.grey)
            : Image.file(file!, fit: BoxFit.cover),
      ),
    );
  }
}
