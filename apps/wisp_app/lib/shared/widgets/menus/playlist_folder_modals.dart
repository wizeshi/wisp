// Copyright © 2026 wizeshi

/// Playlist folder dialogs and menus
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/local_playlist.dart';

import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert_extensions.dart';

class PlaylistFolderModals {
  static OverlayEntry? _activeSubmenu;
  static BuildContext? _submenuParentContext;

  static void _showWriteBlockedSnack(BuildContext context) {
    if (!context.mounted) return;
    context.showWarningAlert('Spotify writing is disabled in Preferences.');
  }

  static void _showSyncErrorSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    context.showErrorAlert(message);
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
    try {
      await context.read<MetadataManager>().renamePlaylist(
        linkedId,
        name,
        source: localPlaylist.linkedSource,
      );
    } catch (e) {
      if (context.mounted) {
        _showSyncErrorSnack(context, 'Failed to rename on provider: $e');
      }
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
    try {
      await context.read<MetadataManager>().deletePlaylist(
        linkedId,
        source: localPlaylist.linkedSource,
      );
    } catch (e) {
      if (context.mounted) {
        _showSyncErrorSnack(context, 'Failed to delete on provider: $e');
      }
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
    final metadataManager = context.read<MetadataManager>();
    if (!metadataManager.isAuthenticated) {
      _showSyncErrorSnack(context, 'Active provider is not connected.');
      return;
    }
    String? linkedId;
    final activeSource = metadataManager.activeCatalogProvider?.providerId ?? 'spotify';
    try {
      linkedId = await metadataManager.createPlaylist(
        name: localPlaylist.title,
      );
    } catch (e) {
      if (context.mounted) {
        _showSyncErrorSnack(context, 'Failed to create playlist: $e');
      }
      return;
    }
    if (linkedId.isEmpty) {
      if (context.mounted) {
        _showSyncErrorSnack(context, 'Failed to create remote playlist.');
      }
      return;
    }
    if (context.mounted) {
      await context.read<LocalPlaylistState>().linkToProvider(
        id: localPlaylist.id,
        provider: activeSource,
        providerId: linkedId,
      );
    }
  }

  static Future<void> deletePlaylistWithSync(
    BuildContext context,
    String playlistId,
  ) async {
    final localState = context.read<LocalPlaylistState>();
    final localPlaylist = localState.getById(playlistId);
    await localState.deletePlaylist(playlistId);
    if (localPlaylist != null) {
      if (context.mounted) {
        await _syncDeleteToProvider(context, localPlaylist);
      }
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
            color: overlayContext.colors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: overlayContext.colors.borderSubtle),
            ),
            elevation: 10,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
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
      final result = await FilePicker.pickFiles(type: FileType.image);
      final filePath = result.first.path;
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
      if (modalContext.mounted) {
        Navigator.pop(modalContext);
      }
    }

    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: context.colors.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final colors = context.colors;
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
                    Text(
                      'Create folder',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Folder title',
                        hintStyle: TextStyle(color: colors.textMuted),
                        filled: true,
                        fillColor: colors.inputFill,
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
                          child: GenericOutlinedButton.icon(
                            onPressed: () => pickThumbnail(setModalState),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Choose thumbnail'),
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.border),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: GenericTextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GenericElevatedButton(
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
        final colors = dialogContext.colors;
        return AlertDialog(
          backgroundColor: colors.surfaceElevated,
          title: Text(
            'Create folder',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Folder title',
                      hintStyle: TextStyle(color: colors.textMuted),
                      filled: true,
                      fillColor: colors.inputFill,
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
                        child: GenericOutlinedButton.icon(
                          onPressed: () => pickThumbnail(setModalState),
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choose thumbnail'),
                          foregroundColor: colors.textPrimary,
                          side: BorderSide(color: colors.border),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            GenericTextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            GenericElevatedButton(
              onPressed: () => save(dialogContext),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  static Future<LocalPlaylist?> showCreatePlaylistDialog(BuildContext context) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final controller = TextEditingController();
    File? selectedFile;

    Future<void> pickThumbnail(StateSetter setModalState) async {
      final result = await FilePicker.pickFiles(type: FileType.image);
      final filePath = result.first.path;
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

      if (modalContext.mounted) {
        await _syncCreateToProvider(modalContext, localPlaylist);
      }

      if (modalContext.mounted) {
        Navigator.of(modalContext).pop(localPlaylist);
      }
    }

    if (isMobile) {
      return await showModalBottomSheet<LocalPlaylist>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: context.colors.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final colors = context.colors;
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
                    Text(
                      'Create playlist',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Playlist name',
                        hintStyle: TextStyle(color: colors.textMuted),
                        filled: true,
                        fillColor: colors.inputFill,
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
                          child: GenericOutlinedButton.icon(
                            onPressed: () => pickThumbnail(setModalState),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Choose thumbnail'),
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.border),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: GenericTextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GenericElevatedButton(
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
    }

    return await showDialog<LocalPlaylist>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final colors = dialogContext.colors;
        return AlertDialog(
          backgroundColor: colors.surfaceElevated,
          title: Text(
            'Create playlist',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Playlist name',
                      hintStyle: TextStyle(color: colors.textMuted),
                      filled: true,
                      fillColor: colors.inputFill,
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
                        child: GenericOutlinedButton.icon(
                          onPressed: () => pickThumbnail(setModalState),
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choose thumbnail'),
                          foregroundColor: colors.textPrimary,
                          side: BorderSide(color: colors.border),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            GenericTextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            GenericTextButton(
              onPressed: () => save(dialogContext),
              child: Text('Create', style: TextStyle(color: colors.textPrimary)),
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
        final colors = dialogContext.colors;
        return AlertDialog(
          backgroundColor: colors.surfaceElevated,
          title: Text(
            'Rename playlist',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: colors.textMuted),
              filled: true,
              fillColor: colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            GenericTextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            GenericTextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final localState = context.read<LocalPlaylistState>();
                final localPlaylist = localState.getById(playlist.id);
                await localState.renamePlaylist(playlist.id, name);
                if (localPlaylist != null && dialogContext.mounted) {
                  await _syncRenameToProvider(context, localPlaylist, name);
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text('Save', style: TextStyle(color: colors.textPrimary)),
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
      await modalContext.read<LibraryFolderState>().renameFolder(
        folder.id,
        title,
      );

      if (modalContext.mounted) {
        Navigator.pop(modalContext);
      }
    }

    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: context.colors.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          final colors = modalContext.colors;
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
                Text(
                  'Rename folder',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Folder title',
                    hintStyle: TextStyle(color: colors.textMuted),
                    filled: true,
                    fillColor: colors.inputFill,
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
                      child: GenericTextButton(
                        onPressed: () => Navigator.pop(modalContext),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GenericElevatedButton(
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
        final colors = dialogContext.colors;
        return AlertDialog(
          backgroundColor: colors.surfaceElevated,
          title: Text(
            'Rename folder',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Folder title',
              hintStyle: TextStyle(color: colors.textMuted),
              filled: true,
              fillColor: colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            GenericTextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            GenericElevatedButton(
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
    final result = await FilePicker.pickFiles(type: FileType.image);
    final filePath = result.first.path;
    if (filePath == null) return;
    if (context.mounted) {
      await context.read<LibraryFolderState>().changeFolderThumbnail(
        folder.id,
        File(filePath),
      );
    }
  }

  static Future<void> showChangePlaylistThumbnailDialog(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final filePath = result.first.path;
    if (filePath == null) return;
    if (context.mounted) {
      await context.read<LocalPlaylistState>().updateThumbnail(
        playlist.id,
        File(filePath),
      );
    }
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
        backgroundColor: context.colors.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
          final colors = modalContext.colors;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (currentFolderId != null)
                  ListTile(
                    leading: Icon(
                      Icons.folder_off_outlined,
                      color: colors.textPrimary,
                    ),
                    title: Text(
                      'Remove from folder',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    onTap: () async {
                      Navigator.pop(modalContext);
                      await folderState.movePlaylistIntoFolder(
                        playlist.id,
                        null,
                      );
                    },
                  ),
                ...folders.map(
                  (folder) => ListTile(
                    leading: Icon(Icons.folder, color: colors.textPrimary),
                    title: Text(
                      folder.title,
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    trailing: currentFolderId == folder.id
                        ? Icon(
                            Icons.check,
                            color: colors.isDark
                                ? Colors.greenAccent
                                : Theme.of(modalContext).colorScheme.primary,
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(modalContext);
                      await folderState.movePlaylistIntoFolder(
                        playlist.id,
                        folder.id,
                      );
                    },
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.create_new_folder_outlined,
                    color: colors.textPrimary,
                  ),
                  title: Text(
                    'Create folder…',
                    style: TextStyle(color: colors.textPrimary),
                  ),
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
                    color: dialogContext.colors.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: dialogContext.colors.borderSubtle),
                    ),
                    elevation: 10,
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
                                  onTap: () =>
                                      folderState.movePlaylistIntoFolder(
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
                                      ? Icon(
                                          Icons.check,
                                          color: dialogContext.colors.isDark
                                              ? Colors.greenAccent
                                              : Theme.of(
                                                  dialogContext,
                                                ).colorScheme.primary,
                                          size: 18,
                                        )
                                      : null,
                                  onTap: () =>
                                      folderState.movePlaylistIntoFolder(
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
            Icon(icon, color: context.colors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: context.colors.textPrimary),
              ),
            ),
            ?trailing,
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
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 56,
        color: colors.surfaceSubtle,
        child: file == null
            ? Icon(Icons.folder, color: colors.textMuted)
            : Image.file(
                file!,
                fit: BoxFit.cover,
                cacheWidth: 112,
                cacheHeight: 112,
              ),
      ),
    );
  }
}
