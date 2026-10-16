// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/cards/album_card.dart';
import 'package:wisp/shared/widgets/cards/artist_card.dart';
import 'package:wisp/shared/widgets/cards/playlist_card.dart';
import 'package:wisp/shared/widgets/rails/card_rail.dart';
import 'package:wisp/shared/widgets/rows/album_row.dart';
import 'package:wisp/shared/widgets/rows/artist_row.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';
import 'package:wisp/shared/widgets/rows/playlist_row.dart';
import 'package:wisp/shared/widgets/rows/song_row.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'home_view_data.dart';

Widget? buildHomeCard(dynamic item, {bool useSpecialCardStyle = false}) =>
    switch (item) {
      GenericPlaylist playlist => PlaylistCard(playlist: playlist),
      GenericAlbum album => AlbumCard(album: album),
      GenericSimpleArtist artist => ArtistCard(artist: artist),
      _ => null,
    };

Widget buildHomeSection(
  String title,
  List<dynamic> items, {
  bool showTitle = true,
  bool expandCardsToRowWidth = false,
  bool useSpecialCardStyle = false,
}) {
  return CardRail<dynamic>(
    title: title,
    items: items,
    showTitle: showTitle,
    expandItemsToRailWidth: expandCardsToRowWidth,
    itemWidth: 200,
    itemHeight: useSpecialCardStyle ? 168 : null,
    itemBuilder: (context, item) =>
        buildHomeCard(item, useSpecialCardStyle: useSpecialCardStyle) ??
        const SizedBox.shrink(),
  );
}

Widget? buildHomeQuickTile(
  dynamic item, {
  bool isMobile = false,
  required HomeViewActions actions,
}) {
  const tileBg = Color(0x0DFFFFFF);
  final height = isMobile ? 56.0 : 48.0;
  final playPosition =
      isMobile ? GenericRowPlayPosition.none : GenericRowPlayPosition.end;

  return switch (item) {
    GenericPlaylist playlist => PlaylistRow(
      playlist: playlist,
      height: height,
      backgroundColor: tileBg,
      showSubtitle: !isMobile,
      playPosition: playPosition,
    ),
    GenericAlbum album => AlbumRow(
      album: album,
      height: height,
      backgroundColor: tileBg,
      showSubtitle: !isMobile,
      playPosition: playPosition,
    ),
    GenericSimpleArtist artist => ArtistRow(
      artist: artist,
      height: height,
      backgroundColor: tileBg,
      showSubtitle: !isMobile,
      playPosition: playPosition,
    ),
    GenericSong song => SongRow(
      song: song,
      height: height,
      backgroundColor: tileBg,
      showSubtitle: !isMobile,
      playPosition: playPosition,
      onTap: () => actions.onPlaySong(song),
      onLongPress: () => actions.onShowTrackMenu(song),
    ),
    _ => null,
  };
}

List<Widget> buildHomeMobileHeaderActions(
  BuildContext context,
  HomeViewActions actions, {
  bool useAppleIcon = false,
}) {
  return [
    GenericIconButton(
      icon: const Icon(
        Symbols.headphones,
        color: Colors.white,
        size: 24,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: actions.onOpenDJ,
    ),
    Selector<PreferencesProvider, bool>(
      selector: (context, prefs) => prefs.debugModeEnabled,
      builder: (context, debugModeEnabled, child) {
        if (!debugModeEnabled) {
          return const SizedBox.shrink();
        }
        return GenericIconButton(
          icon: const Icon(
            Icons.bug_report_outlined,
            color: Colors.white,
            size: 24,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: actions.onOpenDebug,
        );
      },
    ),
    GenericIconButton(
      icon: Icon(
        useAppleIcon ? CupertinoIcons.settings : Icons.settings_outlined,
        color: Colors.white,
        size: useAppleIcon ? 26 : 24,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: actions.onOpenSettings,
    ),
  ];
}

