import 'package:material_ui/material_ui.dart';

/// The icon used to represent a song source anywhere in the UI (row source
/// badges, context menus, the title bar "now playing" indicator, ...).
///
/// This used to be reimplemented per-screen as a private `_sourceIcon`
/// method (see search.dart, list_detail.dart, title_bar.dart and
/// entity_context_menus.dart) with the same switch duplicated four times.
/// New code — like [TrackRow]'s `showSource` column — should call this
/// instead of adding a fifth copy.
IconData songSourceIcon(String source) {
  final clean = source.toLowerCase();
  if (clean == 'youtube') {
    return Icons.ondemand_video;
  }
  if (clean == 'soundcloud') {
    return Icons.cloud;
  }
  return Icons.music_note;
}
