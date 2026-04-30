import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/library/library_state.dart';
import '../providers/library/library_folders.dart';
import '../providers/navigation_state.dart';
import '../providers/search/search_state.dart';
import '../services/navigation_history.dart';
import '../services/tab_routes.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../widgets/navigation.dart';
import '../widgets/player_bar.dart';
import '../widgets/right_sidebar.dart';
import '../widgets/title_bar.dart';
import '../models/metadata_models.dart';
import '../models/library_folder.dart';
import '../views/home.dart';
import '../views/library.dart';
import '../views/search.dart';
import '../views/settings.dart';
import '../views/list_detail.dart';
import '../views/artist_detail.dart';
import '../utils/liked_songs.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool get _isDesktop => Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchAutoSwitchTimer;
  String _lastWindowTitle = 'wisp';

  @override
  void initState() {
    super.initState();
    NavigationHistory.instance.currentRoute.addListener(_handleRouteChange);
  }

  @override
  void dispose() {
    _searchAutoSwitchTimer?.cancel();
    _searchFocusNode.dispose();
    NavigationHistory.instance.currentRoute.removeListener(_handleRouteChange);
    super.dispose();
  }

  void _handleRouteChange() {
    if (!mounted) return;
    final routeName = NavigationHistory.instance.currentRouteName;
    final navState = context.read<NavigationState>();
    if (TabRoutes.isTabRoute(routeName)) {
      navState.setNavIndex(TabRoutes.indexForRoute(routeName));
    }
  }

  void _pushTab(int index) {
    final routeName = TabRoutes.routeForIndex(index);
    if (NavigationHistory.instance.currentRouteName == routeName) return;
    NavigationHistory.instance.navigatorKey.currentState?.pushNamed(routeName);
  }

  void _scheduleSearchAutoSwitch(String value) {
    _searchAutoSwitchTimer?.cancel();
    if (value.trim().isEmpty) return;

    _searchAutoSwitchTimer = Timer(const Duration(milliseconds: 250), () {
      _pushTab(1);
      if (_searchFocusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _searchFocusNode.requestFocus();
          }
        });
      }
    });
  }

  String _buildWindowTitle(GenericSong? track) {
    if (track == null || track.title.trim().isEmpty) {
      return 'wisp';
    }
    final artistName = track.artists.isNotEmpty
        ? track.artists.first.name.trim()
        : '';
    if (artistName.isEmpty) {
      return track.title.trim();
    }
    return '$artistName - ${track.title.trim()}';
  }

  Widget _buildWindowTitleSync() {
    if (!_isDesktop) {
      return const SizedBox.shrink();
    }

    return Selector<global_audio_player.WispAudioHandler, GenericSong?>(
      selector: (context, player) => player.currentTrack,
      builder: (context, track, child) {
        final title = _buildWindowTitle(track);
        if (title != _lastWindowTitle) {
          _lastWindowTitle = title;
          unawaited(windowManager.setTitle(title));
        }
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _handlePop(BuildContext context, bool enableExitPrompt) async {
    final navigator = NavigationHistory.instance.navigatorKey.currentState;
    if (navigator?.canPop() == true) {
      navigator?.maybePop();
      return;
    }
    if (!enableExitPrompt) return;

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App'),
        content: const Text('Do you want to exit wisp?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      SystemNavigator.pop();
    }
  }

  List<dynamic> _getLibraryItems(
    LibraryState library,
    LibraryFolderState folderState,
    LibraryView view,
  ) {
    switch (view) {
      case LibraryView.playlists:
        GenericPlaylist? likedPlaylist;
        for (final playlist in library.playlists) {
          if (isLikedSongsPlaylistId(playlist.id)) {
            likedPlaylist = playlist;
            break;
          }
        }
        final filteredPlaylists = library.playlists
            .where((p) => !isLikedSongsPlaylistId(p.id))
            .toList();
        final groups = folderState.buildPlaylistGroups(filteredPlaylists);
        final entries = <LibrarySidebarEntry>[];
        if (likedPlaylist != null) {
          entries.add(LibrarySidebarEntry.item(likedPlaylist));
        }
        for (final group in groups.folders) {
          entries.add(LibrarySidebarEntry.item(group.folder));
          if (!folderState.isFolderCollapsed(group.folder.id)) {
            for (final playlist in group.playlists) {
              entries.add(
                LibrarySidebarEntry.item(
                  playlist,
                  folderId: group.folder.id,
                ),
              );
            }
          }
        }
        if (groups.folders.isNotEmpty) {
          entries.add(const LibrarySidebarEntry.unassigned());
        }
        for (final playlist in groups.unassigned) {
          entries.add(LibrarySidebarEntry.item(playlist, folderId: null));
        }
        return entries;
      case LibraryView.albums:
        return library.albums;
      case LibraryView.artists:
        return library.artists;
      case LibraryView.all:
        // If the selected view produced no items (or the `all` view was
        // selected), fall back to the ordered `allOrganized` list (preserves
        // the user's library ordering from the internal API). Convert entries
        // into sidebar items where possible.
        final ordered = library.allOrganized;
        if (ordered == null || ordered.isEmpty) return [];
        final entries = <LibrarySidebarEntry>[];
        for (final e in ordered) {
          if (e is LibrarySidebarEntry) {
            if (e.type == LibrarySidebarEntryType.unassignedHeader) {
              continue;
            }
            entries.add(e);
            continue;
          }
          if (e is PlaylistFolder) {
            entries.add(LibrarySidebarEntry.item(e));
            continue;
          }
          if (e is GenericPlaylist) {
            final folderId = folderState.folderIdForPlaylist(e.id);
            if (folderId != null && folderState.isFolderCollapsed(folderId)) {
              continue;
            }
            entries.add(LibrarySidebarEntry.item(e, folderId: folderId));
            continue;
          }
          if (e is GenericAlbum) {
            entries.add(LibrarySidebarEntry.item(e));
            continue;
          }
          if (e is GenericSimpleArtist) {
            entries.add(LibrarySidebarEntry.item(e));
            continue;
          }
          if (e is Map<String, dynamic>) {
            final t = e['__typename'] as String? ?? e['type'] as String?;
            if (t == 'Folder') {
              final uri = e['uri'] as String? ?? e['id'] as String? ?? '';
              final id = uri.isNotEmpty ? uri : (e['id'] as String? ?? '');
              final folder = folderState.getFolderById(id);
              if (folder != null) {
                entries.add(LibrarySidebarEntry.item(folder));
                continue;
              }
            }
            // Fallback: attempt to convert map to a simple playlist.
            if (e['uri']?.toString().contains('playlist') == true) {
              final p = GenericPlaylist(
                id: e['uri'] as String? ?? e['id'] as String? ?? '',
                source: SongSource.spotifyInternal,
                title: e['name'] as String? ?? '',
                thumbnailUrl: e['image']?['url'] as String? ?? '',
                author: GenericSimpleUser(
                  id: '',
                  source: SongSource.spotifyInternal,
                  displayName: '',
                  avatarUrl: null,
                  followerCount: null,
                  profileUrl: null,
                ),
                songs: null,
                durationSecs: 0,
              );
              entries.add(LibrarySidebarEntry.item(p));
            }
          }
        }
        return entries;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationState>();
    final libraryState = context.watch<LibraryState>();
    final folderState = context.watch<LibraryFolderState>();
    final searchState = context.read<SearchState>();
    final searchController = searchState.controller;
    final isDesktopImmersive = _isDesktop && navState.desktopImmersiveMode;

    final enableExitPrompt = !_isDesktop;
    final libraryItems = _getLibraryItems(
      libraryState,
      folderState,
      navState.selectedLibraryView,
    );

    final shell = Material(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          _buildWindowTitleSync(),
          if (_isDesktop && !isDesktopImmersive)
            WispTitleBar(
              onHomeTap: () => _pushTab(0),
              onSettingsTap: () => _pushTab(3),
              searchController: searchController,
              searchFocusNode: _searchFocusNode,
              onSearchChanged: _scheduleSearchAutoSwitch,
              onSearchSubmitted: () {
                _pushTab(1);
                searchState.submit();
              },
              onSearchCleared: searchState.clear,
            ),
          Expanded(
            child: Row(
              children: [
                if (_isDesktop && !isDesktopImmersive)
                  WispNavigation(
                    selectedView: navState.selectedLibraryView,
                    onViewChanged: navState.setLibraryView,
                    selectedIndex: navState.selectedNavIndex,
                    onDestinationSelected: (index) {
                      navState.setNavIndex(index);
                      _pushTab(index);
                    },
                    libraryItems: libraryItems,
                    onLibraryItemSelected: _handleLibraryItemSelected,
                    expandedWidth: navState.leftSidebarWidth,
                  ),
                if (_isDesktop && !isDesktopImmersive)
                  _LeftResizeHandle(
                    onResize: navState.adjustLeftSidebarWidth,
                  ),
                Expanded(
                  child: Navigator(
                    key: NavigationHistory.instance.navigatorKey,
                    observers: [NavigationHistory.instance.observer],
                    initialRoute: TabRoutes.home,
                    onGenerateRoute: _onGenerateRoute,
                  ),
                ),
                if (_isDesktop && !isDesktopImmersive && navState.rightSidebarVisible)
                  RightSidebar(
                    width: navState.rightSidebarWidth,
                    onResize: navState.adjustRightSidebarWidth,
                  ),
              ],
            ),
          ),
          if (navState.selectedNavIndex != 3 && !_isDesktop) const WispPlayerBar(),
          if (_isDesktop && !isDesktopImmersive) const WispPlayerBar(),
          if (!_isDesktop && navState.selectedNavIndex != 3)
            WispNavigation(
              selectedView: navState.selectedLibraryView,
              onViewChanged: navState.setLibraryView,
              selectedIndex: navState.selectedNavIndex,
              onDestinationSelected: (index) {
                navState.setNavIndex(index);
                _pushTab(index);
              },
              libraryItems: libraryItems,
              onLibraryItemSelected: _handleLibraryItemSelected,
            ),
        ],
      ),
    );

    if (!enableExitPrompt) {
      return shell;
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handlePop(context, enableExitPrompt);
      },
      child: shell,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case TabRoutes.search:
        return MaterialPageRoute(
          settings: settings,
          builder: (context) {
            final library = context.read<LibraryState>();
            final navState = context.read<NavigationState>();
            return SearchView(
              playlists: library.playlists,
              albums: library.albums,
              artists: library.artists,
              initialLibraryView: navState.selectedLibraryView,
              currentNavIndex: navState.selectedNavIndex,
              onOpenSettings: () => _pushTab(3),
            );
          },
        );
      case TabRoutes.library:
        return MaterialPageRoute(
          settings: settings,
          builder: (context) {
            final library = context.read<LibraryState>();
            return LibraryTabView(
              initialPlaylists: library.playlists,
              initialAlbums: library.albums,
              initialArtists: library.artists,
            );
          },
        );
      case TabRoutes.settings:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SettingsPage(),
        );
      case TabRoutes.home:
      default:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HomePage(),
        );
    }
  }

  void _handleLibraryItemSelected(dynamic item) {
    final libraryState = context.read<LibraryState>();
    final navState = context.read<NavigationState>();

    if (item is GenericPlaylist) {
      NavigationHistory.instance.navigatorKey.currentState?.push(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              SharedListDetailView(
            id: item.id,
            type: SharedListType.playlist,
            initialTitle: item.title,
            initialThumbnailUrl: item.thumbnailUrl,
            playlists: libraryState.playlists,
            albums: libraryState.albums,
            artists: libraryState.artists,
            initialLibraryView: navState.selectedLibraryView,
            initialNavIndex: navState.selectedNavIndex,
          ),
        ),
      );
      return;
    }

    if (item is GenericAlbum) {
      NavigationHistory.instance.navigatorKey.currentState?.push(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              SharedListDetailView(
            id: item.id,
            type: SharedListType.album,
            initialTitle: item.title,
            initialThumbnailUrl: item.thumbnailUrl,
            playlists: libraryState.playlists,
            albums: libraryState.albums,
            artists: libraryState.artists,
            initialLibraryView: navState.selectedLibraryView,
            initialNavIndex: navState.selectedNavIndex,
          ),
        ),
      );
      return;
    }

    if (item is GenericSimpleArtist) {
      NavigationHistory.instance.navigatorKey.currentState?.push(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              ArtistDetailView(
            artistId: item.id,
            initialArtist: item,
            playlists: libraryState.playlists,
            albums: libraryState.albums,
            artists: libraryState.artists,
            initialLibraryView: navState.selectedLibraryView,
            initialNavIndex: navState.selectedNavIndex,
          ),
        ),
      );
    }
  }
}

class _LeftResizeHandle extends StatelessWidget {
  final ValueChanged<double> onResize;

  const _LeftResizeHandle({required this.onResize});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
        child: SizedBox(
          width: 6,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 2,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
