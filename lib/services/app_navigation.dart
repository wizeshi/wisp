import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metadata_models.dart';
import '../providers/library/library_state.dart';
import '../providers/navigation_state.dart';
import '../services/navigation_history.dart';
import '../services/tab_routes.dart';
import '../views/lyrics.dart';
import '../views/queue.dart';
import '../views/artist_detail.dart';
import '../views/list_detail.dart';
import '../widgets/full_player.dart';

class AppNavigation {
  AppNavigation._();

  static final AppNavigation instance = AppNavigation._();

  NavigatorState? get _shellNavigator =>
      NavigationHistory.instance.navigatorKey.currentState;

  Future<bool> maybePopOverlay(BuildContext context) {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (!rootNavigator.canPop()) {
      return Future.value(false);
    }
    return rootNavigator.maybePop();
  }

  Future<bool> maybePopShell() async {
    final shellNavigator = _shellNavigator;
    if (shellNavigator == null) {
      return false;
    }
    return shellNavigator.maybePop();
  }

  void pushTab(int index) {
    final routeName = TabRoutes.routeForIndex(index);
    if (NavigationHistory.instance.currentRouteName == routeName) {
      return;
    }
    _shellNavigator?.pushNamed(routeName);
  }

  void openSettings() {
    if (NavigationHistory.instance.currentRouteName == TabRoutes.settings) {
      return;
    }
    _shellNavigator?.pushNamed(TabRoutes.settings);
  }

  void openLibraryItem(BuildContext context, dynamic item) {
    if (item is GenericPlaylist) {
      openSharedList(
        context,
        id: item.id,
        type: SharedListType.playlist,
        initialTitle: item.title,
        initialThumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    if (item is GenericAlbum) {
      openSharedList(
        context,
        id: item.id,
        type: SharedListType.album,
        initialTitle: item.title,
        initialThumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    if (item is GenericSimpleArtist) {
      openArtist(
        context,
        artistId: item.id,
        initialArtist: item,
      );
    }
  }

  void openSharedList(
    BuildContext context, {
    required String id,
    required SharedListType type,
    String? initialTitle,
    String? initialThumbnailUrl,
  }) {
    final libraryState = context.read<LibraryState>();
    final navState = context.read<NavigationState>();

    _shellNavigator?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: RouteSettings(
          name: type == SharedListType.playlist ? '/playlist/$id' : '/album/$id',
        ),
        pageBuilder: (context, animation, secondaryAnimation) =>
            SharedListDetailView(
          id: id,
          type: type,
          initialTitle: initialTitle,
          initialThumbnailUrl: initialThumbnailUrl,
          playlists: libraryState.playlists,
          albums: libraryState.albums,
          artists: libraryState.artists,
          initialLibraryView: navState.selectedLibraryView,
          initialNavIndex: navState.selectedNavIndex,
        ),
      ),
    );
  }

  void openArtist(
    BuildContext context, {
    required String artistId,
    GenericSimpleArtist? initialArtist,
    String? fallbackName,
  }) {
    final libraryState = context.read<LibraryState>();
    final navState = context.read<NavigationState>();

    _shellNavigator?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: RouteSettings(name: '/artist/$artistId'),
        pageBuilder: (context, animation, secondaryAnimation) => ArtistDetailView(
          artistId: artistId,
          initialArtist:
              initialArtist ??
              GenericSimpleArtist(
                id: artistId,
                source: SongSource.spotifyInternal,
                name: fallbackName ?? 'Artist',
                thumbnailUrl: '',
              ),
          playlists: libraryState.playlists,
          albums: libraryState.albums,
          artists: libraryState.artists,
          initialLibraryView: navState.selectedLibraryView,
          initialNavIndex: navState.selectedNavIndex,
        ),
      ),
    );
  }

  void openPlaybackContext(
    BuildContext context, {
    required String contextType,
    required String contextId,
    String? contextName,
  }) {
    if (contextType == 'artist') {
      openArtist(
        context,
        artistId: contextId,
        fallbackName: contextName,
      );
      return;
    }

    final type = contextType == 'album'
        ? SharedListType.album
        : SharedListType.playlist;

    openSharedList(
      context,
      id: contextId,
      type: type,
      initialTitle: contextName,
    );
  }

  void openFullPlayer() {
    if (NavigationHistory.instance.currentRouteName == '/fullplayer') {
      return;
    }
    _shellNavigator?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: const RouteSettings(name: '/fullplayer'),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const FullScreenPlayer(),
      ),
    );
  }

  void openLyrics() {
    if (NavigationHistory.instance.currentRouteName == '/lyrics') {
      return;
    }
    _shellNavigator?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: const RouteSettings(name: '/lyrics'),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LyricsView(),
      ),
    );
  }

  void openQueue() {
    if (NavigationHistory.instance.currentRouteName == '/queue') {
      return;
    }
    _shellNavigator?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: const RouteSettings(name: '/queue'),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const QueueView(),
      ),
    );
  }
}
