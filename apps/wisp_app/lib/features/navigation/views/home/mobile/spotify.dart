// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/layout/mobile_bottom_padding.dart';
import '../home_view_data.dart';
import '../home_widgets.dart';

class MobileSpotifyHome extends StatelessWidget {
  final HomeViewData data;
  final HomeViewActions actions;

  const MobileSpotifyHome({
    super.key,
    required this.data,
    required this.actions,
  });

  List<Widget> _buildQuickGridTiles(BuildContext context) {
    final sourceItems = <dynamic>[];

    final likedPlaylist = data.savedPlaylists.cast<GenericPlaylist?>().firstWhere(
      (p) => isLikedSongsPlaylistId(p?.id),
      orElse: () => null,
    );
    if (likedPlaylist != null) {
      sourceItems.add(likedPlaylist);
    }

    if (data.homeSections.isNotEmpty) {
      sourceItems.addAll(data.homeSections.entries.first.value);
    }

    final seen = <String>{};
    final tiles = <Widget>[];
    for (final item in sourceItems) {
      final key = _itemKey(item);
      if (key == null || seen.contains(key)) continue;
      seen.add(key);

      final tile = buildHomeQuickTile(item, isMobile: true, actions: actions);
      if (tile != null) {
        tiles.add(
          Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
        );
      }
      if (tiles.length >= 8) break;
    }

    if (tiles.isNotEmpty) {
      return tiles;
    }

    return [
      for (final playlist in data.savedPlaylists.take(4))
        if (buildHomeQuickTile(playlist, isMobile: true, actions: actions) case final tile?)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
      for (final album in data.savedAlbums.take(4))
        if (buildHomeQuickTile(album, isMobile: true, actions: actions) case final tile?)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
    ];
  }

  String? _itemKey(dynamic item) => switch (item) {
    GenericPlaylist(:final id) => 'playlist:$id',
    GenericAlbum(:final id) => 'album:$id',
    GenericSimpleArtist(:final id) => 'artist:$id',
    GenericSong(:final id) => 'song:$id',
    _ => null,
  };

  List<Widget> _buildDynamicSections() {
    if (data.homeSections.isEmpty) return const [];
    final widgets = <Widget>[];

    final entries = data.homeSections.entries.skip(1).toList(growable: false);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.value.isEmpty) continue;
      widgets.add(
        buildHomeSection(
          entry.key,
          entry.value,
          showTitle: true,
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final quickTiles = _buildQuickGridTiles(context);
    final leftQuickTiles = <Widget>[];
    final rightQuickTiles = <Widget>[];

    for (var i = 0; i < quickTiles.length; i++) {
      if (i.isEven) {
        leftQuickTiles.add(quickTiles[i]);
      } else {
        rightQuickTiles.add(quickTiles[i]);
      }
    }

    final dynamicSections = _buildDynamicSections();

    return SafeArea(
      bottom: false,
      child: WispCustomScrollView(
        key: const PageStorageKey('home_mobile_spotify'),
        controller: data.scrollController,
        slivers: [
          // Header with greeting & settings icon
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      data.greeting,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ...buildHomeMobileHeaderActions(context, actions, useAppleIcon: false),
                ],
              ),
            ),
          ),

          // 2-column grid for playlists and albums
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: leftQuickTiles)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(children: rightQuickTiles)),
                ],
              ),
            ),
          ),

          // Dynamic Sections
          ...dynamicSections.map(
            (section) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: section,
              ),
            ),
          ),

          // Bottom padding for persistent docked player and bottom nav bar
          const MobileBottomPaddingSliver(extra: 0),
        ],
      ),
    );
  }
}

