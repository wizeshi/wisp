import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';

import 'package:wisp/data/models/metadata_models.dart';

class FolderRow extends StatelessWidget {
  final PlaylistFolder folder;
  final double width;
  final EdgeInsetsGeometry padding;
  final GenericRowPlayPosition playPosition;

  const FolderRow({
    super.key,
    required this.folder,
    this.width = 160,
    this.padding = EdgeInsets.zero,
    this.playPosition = GenericRowPlayPosition.end,
  });

  Future<void> _toggleFolderState(BuildContext context) async {
    await context.read<LibraryFolderState>().toggleFolderCollapsed(folder.id);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<LibraryState, List<GenericPlaylist>>(
      selector: (context, state) => state.playlists,
      builder:
          (
            BuildContext context,
            List<GenericPlaylist> playlists,
            Widget? child,
          ) {
            final folderIdForPlaylist = context
                .select<LibraryFolderState, String? Function(String)>(
                  (value) => value.folderIdForPlaylist,
                );
            final isFolderCollapsed = context
                .select<LibraryFolderState, bool Function(String)>(
                  (value) => value.isFolderCollapsed,
                );

            final count = playlists
                .where((p) => folderIdForPlaylist(p.id) == folder.id)
                .length;
            final collapsed = isFolderCollapsed(folder.id);

            return GenericRow(
              width: width,
              padding: padding,
              playPosition: GenericRowPlayPosition.end,
              title: folder.title,
              subtitle: '$count playlist${count == 1 ? '' : 's'}',
              artwork: ArtworkThumbnail(
                source: const ArtworkSource.none(),
                size: ArtworkSize.small,
                fallbackIcon: collapsed ? Icons.folder : Icons.folder_open,
              ),
              // If isPlaying is false, we hide the play button overlay, which is what we want for folders.
              isPlaying: false,
              onTap: () => _toggleFolderState(context),
              onPlay: null,
              onSecondaryTapDown: (details) {
                EntityContextMenus.showFolderMenu(
                  context,
                  folder: folder,
                  globalPosition: details.globalPosition,
                );
              },
              onLongPress: () {
                EntityContextMenus.showFolderMenu(context, folder: folder);
              },
            );
          },
    );
  }
}
