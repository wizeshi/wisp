// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:wisp/data/models/metadata_models.dart';

class HomeViewData {
  final bool isLoading;
  final bool isRefreshing;
  final List<GenericAlbum> savedAlbums;
  final List<GenericPlaylist> savedPlaylists;
  final List<GenericSimpleArtist> followedArtists;
  final Map<String, List<dynamic>> homeSections;
  final String greeting;
  final ScrollController scrollController;
  final bool hasEnabledProviders;
  final bool supportsHome;
  final bool isAuthenticated;
  final String activeProviderName;

  const HomeViewData({
    required this.isLoading,
    required this.isRefreshing,
    required this.savedAlbums,
    required this.savedPlaylists,
    required this.followedArtists,
    required this.homeSections,
    required this.greeting,
    required this.scrollController,
    required this.hasEnabledProviders,
    required this.supportsHome,
    required this.isAuthenticated,
    required this.activeProviderName,
  });
}

class HomeViewActions {
  final Future<void> Function() onRefresh;
  final void Function(GenericPlaylist) onPlaylistTap;
  final void Function(GenericAlbum) onAlbumTap;
  final void Function(GenericSimpleArtist) onArtistTap;
  final void Function(dynamic item) onItemTap;
  final void Function(GenericSong) onPlaySong;
  final void Function(GenericSong) onShowTrackMenu;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDJ;
  final VoidCallback onOpenDebug;

  const HomeViewActions({
    required this.onRefresh,
    required this.onPlaylistTap,
    required this.onAlbumTap,
    required this.onArtistTap,
    required this.onItemTap,
    required this.onPlaySong,
    required this.onShowTrackMenu,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onOpenDJ,
    required this.onOpenDebug,
  });
}

