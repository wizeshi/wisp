import 'package:flutter/material.dart';

import 'package:wisp/data/models/metadata_models.dart';

/// The icon used to represent a [SongSource] anywhere in the UI (row source
/// badges, context menus, the title bar "now playing" indicator, ...).
///
/// This used to be reimplemented per-screen as a private `_sourceIcon`
/// method (see search.dart, list_detail.dart, title_bar.dart and
/// entity_context_menus.dart) with the same switch duplicated four times.
/// New code — like [TrackRow]'s `showSource` column — should call this
/// instead of adding a fifth copy.
IconData songSourceIcon(SongSource source) {
  switch (source) {
    case SongSource.youtube:
      return Icons.ondemand_video;
    case SongSource.soundcloud:
      return Icons.cloud;
    case SongSource.local:
    case SongSource.spotify:
    case SongSource.spotifyInternal:
      return Icons.music_note;
  }
}
