import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../providers/library/library_state.dart';
import '../providers/library/library_folders.dart';
import '../providers/navigation_state.dart';
import '../providers/search/search_state.dart';
import '../services/wisp_audio_handler.dart';
import '../services/navigation_history.dart';
import '../services/tab_routes.dart';
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

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool get _isDesktop => Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<int> _homeRefreshTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _libraryRefreshTick = ValueNotifier<int>(0);
  Timer? _searchAutoSwitchTimer;

  @override
  void initState() {
    super.initState();
    NavigationHistory.instance.currentRoute.addListener(_handleRouteChange);
  }

  @override
  void dispose() {
    _searchAutoSwitchTimer?.cancel();
    _searchFocusNode.dispose();
    _homeRefreshTick.dispose();
    _libraryRefreshTick.dispose();
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

  bool _isTextInputFocused() {
    if (_searchFocusNode.hasFocus) return true;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _handleSpacebarToggle() {
    if (_isTextInputFocused()) return;
    final player = context.read<WispAudioHandler>();
    if (player.isPlaying) {
      player.pause();
    } else if (player.currentTrack != null || player.queueTracks.isNotEmpty) {
      player.play();
    }
  }

  void _handleRefreshRequested() {
    if (!_isDesktop) return;
    final routeName = NavigationHistory.instance.currentRouteName;
    if (routeName == TabRoutes.home) {
      _homeRefreshTick.value = _homeRefreshTick.value + 1;
      return;
    }
    if (routeName == TabRoutes.library) {
      _libraryRefreshTick.value = _libraryRefreshTick.value + 1;
      return;
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
        final entries = <LibrarySidebarEntry>[];
        if (likedPlaylist != null) {
          entries.add(LibrarySidebarEntry.item(likedPlaylist));
        }
        final folderMap = {
          for (final folder in folderState.folders) folder.id: folder,
        };
        final assigned = <String, List<GenericPlaylist>>{};
        for (final playlist in filteredPlaylists) {
          final folderId = folderState.folderIdForPlaylist(playlist.id);
          if (folderId != null && folderMap.containsKey(folderId)) {
            assigned.putIfAbsent(folderId, () => []).add(playlist);
          }
        }
        final orderedPlaylists = folderState.sortPlaylists(filteredPlaylists);
        final orderedFolders = folderState.sortFolders(assigned);
        final addedFolders = <String>{};

        for (final playlist in orderedPlaylists) {
          final folderId = folderState.folderIdForPlaylist(playlist.id);
          if (folderId != null && folderMap.containsKey(folderId)) {
            if (!addedFolders.contains(folderId)) {
              final folder = folderMap[folderId]!;
              entries.add(LibrarySidebarEntry.item(folder));
              addedFolders.add(folderId);
            }
            if (!folderState.isFolderCollapsed(folderId)) {
              entries.add(
                LibrarySidebarEntry.item(
                  playlist,
                  folderId: folderId,
                ),
              );
            }
          } else {
            entries.add(LibrarySidebarEntry.item(playlist));
          }
        }

        for (final folder in orderedFolders) {
          if (addedFolders.contains(folder.id)) continue;
          entries.add(LibrarySidebarEntry.item(folder));
        }
        return entries;
      case LibraryView.albums:
        return library.albums;
      case LibraryView.artists:
        return library.artists;
      case LibraryView.all:
        break; // fall through to fallback handling below
    }
    // If the selected view produced no items (or the `all` view was selected),
    // fall back to the ordered `allOrganized` list (preserves the user's
    // library ordering from the internal API). Convert entries into sidebar
    // items where possible.
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
        // Fallback: attempt to convert map to a simple playlist/album/artist
        if (e['uri']?.toString().contains('playlist') == true) {
          // Construct a minimal playlist object if necessary
          final p = GenericPlaylist(
            id: e['uri'] as String? ?? e['id'] as String? ?? '',
            source: SongSource.spotifyInternal,
            title: e['name'] as String? ?? '',
            thumbnailUrl: e['image']?['url'] as String? ?? '',
            author: GenericSimpleUser(id: '', source: SongSource.spotifyInternal, displayName: '', avatarUrl: null, followerCount: null, profileUrl: null),
            songs: null,
            durationSecs: 0,
          );
          entries.add(LibrarySidebarEntry.item(p));
        }
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationState>();
    final libraryState = context.watch<LibraryState>();
    final folderState = context.watch<LibraryFolderState>();
    final searchState = context.read<SearchState>();
    final searchController = searchState.controller;

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
          if (_isDesktop)
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
                if (_isDesktop)
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
                if (_isDesktop)
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
                if (_isDesktop && navState.rightSidebarVisible)
                  RightSidebar(
                    width: navState.rightSidebarWidth,
                    onResize: navState.adjustRightSidebarWidth,
                  ),
              ],
            ),
          ),
          if (navState.selectedNavIndex != 3 && !_isDesktop) const WispPlayerBar(),
          if (_isDesktop)
            Stack(
              clipBehavior: Clip.none,
              children: const [
                WispPlayerBar(),
                Positioned(
                  left: 8,
                  bottom: 100,
                  child: DesktopNextUpPreviewOverlay(),
                ),
              ],
            ),
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

    final content = AnimatedBuilder(
      animation: FocusManager.instance,
      builder: (context, child) {
        final shortcuts = <LogicalKeySet, Intent>{};
        if (!_isTextInputFocused()) {
          shortcuts[LogicalKeySet(LogicalKeyboardKey.space)] =
              const ActivateIntent();
        }
        if (_isDesktop) {
          shortcuts[LogicalKeySet(LogicalKeyboardKey.f5)] =
              const RefreshIntent();
        }
        return Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (intent) {
                  _handleSpacebarToggle();
                  return null;
                },
              ),
              RefreshIntent: CallbackAction<RefreshIntent>(
                onInvoke: (intent) {
                  _handleRefreshRequested();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      child: shell,
    );

    if (!enableExitPrompt) {
      return content;
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handlePop(context, enableExitPrompt);
      },
      child: content,
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
              refreshSignal: _libraryRefreshTick,
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
          builder: (_) => HomePage(refreshSignal: _homeRefreshTick),
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
