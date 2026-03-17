import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../providers/library/library_state.dart';
import '../providers/library/library_folders.dart';
import '../providers/navigation_state.dart';
import '../providers/search/search_state.dart';
import '../providers/connect/connect_session_provider.dart';
import '../services/connect/connect_models.dart';
import '../services/connect/lan_connect_service.dart';
import '../services/app_navigation.dart';
import '../services/desktop_notification_center.dart';
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
  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<int> _homeRefreshTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _libraryRefreshTick = ValueNotifier<int>(0);
  Timer? _searchAutoSwitchTimer;
  bool _isHandlingPop = false;
  ConnectSessionProvider? _connectProvider;
  String? _lastPendingPairEventId;
  String? _lastTrustPromptDeviceId;
  bool _isShowingIncomingPairDialog = false;
  static const int _handoffRequestNotificationId = 91011;

  void _debugNav(String message) {
    assert(() {
      debugPrint('[Nav/AppShell] $message');
      return true;
    }());
  }

  @override
  void initState() {
    super.initState();
    NavigationHistory.instance.currentRoute.addListener(_handleRouteChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindConnectProvider();
    });
  }

  @override
  void dispose() {
    _searchAutoSwitchTimer?.cancel();
    _searchFocusNode.dispose();
    _homeRefreshTick.dispose();
    _libraryRefreshTick.dispose();
    NavigationHistory.instance.currentRoute.removeListener(_handleRouteChange);
    _connectProvider?.removeListener(_handleConnectEvents);
    super.dispose();
  }

  void _bindConnectProvider() {
    final provider = context.read<ConnectSessionProvider>();
    if (identical(_connectProvider, provider)) {
      return;
    }
    _connectProvider?.removeListener(_handleConnectEvents);
    _connectProvider = provider;
    _connectProvider?.addListener(_handleConnectEvents);
    _handleConnectEvents();
  }

  void _handleConnectEvents() {
    final connect = _connectProvider;
    if (!mounted || connect == null) return;

    final pending = connect.pendingPairRequest;
    if (pending == null) {
      _lastPendingPairEventId = null;
    } else {
      final eventId =
          '${pending.fromDeviceId}:${pending.fromAddress}:${pending.requestedMode.toJson()}';
      if (_lastPendingPairEventId != eventId) {
        _lastPendingPairEventId = eventId;
        _handleIncomingPairRequest(connect, pending);
      }
    }

    if (!connect.hasPendingTrustPrompt) {
      _lastTrustPromptDeviceId = null;
      return;
    }
    final trustDeviceId = connect.pendingTrustPromptDeviceId;
    if (trustDeviceId == null || trustDeviceId == _lastTrustPromptDeviceId) {
      return;
    }
    _lastTrustPromptDeviceId = trustDeviceId;
    _showTrustDevicePrompt(connect);
  }

  void _handleIncomingPairRequest(
    ConnectSessionProvider connect,
    ConnectPairRequest request,
  ) {
    if (_isDesktop) {
      context.read<DesktopNotificationCenter>().showComplete(
        id: _handoffRequestNotificationId,
        title: 'Handoff request',
        body:
            '${request.fromDeviceName} wants to pair (${request.requestedMode == ConnectLinkMode.controlOnly ? 'Control only' : 'Full handoff'}). Open Handoff panel to accept or decline.',
      );
      return;
    }

    if (_isShowingIncomingPairDialog) return;
    _isShowingIncomingPairDialog = true;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Incoming Handoff request'),
            content: Text(
              '${request.fromDeviceName} wants to pair (${request.requestedMode == ConnectLinkMode.controlOnly ? 'Control only' : 'Full handoff'}).',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  connect.rejectIncomingPair();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Decline'),
              ),
              ElevatedButton(
                onPressed: () {
                  connect.acceptIncomingPair();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Accept'),
              ),
            ],
          );
        },
      ).whenComplete(() {
        _isShowingIncomingPairDialog = false;
      }),
    );
  }

  void _showTrustDevicePrompt(ConnectSessionProvider connect) {
    final deviceName = connect.pendingTrustPromptDeviceName;
    if (deviceName == null) return;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Trust this device?'),
            content: Text(
              'Automatically accept future Handoff requests from $deviceName on this device?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  connect.clearPendingTrustPrompt();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Not now'),
              ),
              ElevatedButton(
                onPressed: () {
                  unawaited(connect.trustPendingIncomingDevice());
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Trust device'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleRouteChange() {
    if (!mounted) return;
    final routeName = NavigationHistory.instance.currentRouteName;
    final navState = context.read<NavigationState>();
    _debugNav(
      'routeChange route=$routeName selected=${navState.selectedNavIndex} lastNonSettings=${navState.lastNonSettingsNavIndex}',
    );
    if (TabRoutes.isTabRoute(routeName)) {
      navState.setNavIndex(TabRoutes.indexForRoute(routeName));
      _debugNav(
        'setNavIndex from tab route -> ${TabRoutes.indexForRoute(routeName)}',
      );
      return;
    }

    if (navState.selectedNavIndex == 3) {
      navState.setNavIndex(navState.lastNonSettingsNavIndex);
      _debugNav(
        'left settings via non-tab route, restoring index=${navState.lastNonSettingsNavIndex}',
      );
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
    AppNavigation.instance.pushTab(index);
  }

  void _syncNavIndexFromCurrentRoute(NavigationState navState) {
    final routeName = NavigationHistory.instance.currentRouteName;
    if (TabRoutes.isTabRoute(routeName)) {
      final index = TabRoutes.indexForRoute(routeName);
      navState.setNavIndex(index);
      _debugNav('syncNavIndex route=$routeName -> $index');
    }
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
    if (_isHandlingPop) {
      _debugNav('back ignored because a previous pop is still processing');
      return;
    }
    _isHandlingPop = true;

    final navState = context.read<NavigationState>();
    final wasInSettings = navState.selectedNavIndex == 3;
    _debugNav(
      'back start route=${NavigationHistory.instance.currentRouteName} selected=${navState.selectedNavIndex} wasInSettings=$wasInSettings',
    );
    try {
      if (await AppNavigation.instance.maybePopOverlay(context)) {
        _debugNav('back consumed by root overlay pop');
        return;
      }

      if (await AppNavigation.instance.maybePopShell()) {
        _debugNav('back consumed by shell route pop');
        if (wasInSettings) {
          navState.setNavIndex(navState.lastNonSettingsNavIndex);
          _debugNav(
            'restored index after settings pop -> ${navState.lastNonSettingsNavIndex}',
          );
        }
        _syncNavIndexFromCurrentRoute(navState);
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
        _debugNav('exit confirmed by user');
        SystemNavigator.pop();
      }
    } finally {
      _isHandlingPop = false;
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
                LibrarySidebarEntry.item(playlist, folderId: folderId),
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
                  _LeftResizeHandle(onResize: navState.adjustLeftSidebarWidth),
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
          if (navState.selectedNavIndex != 3 && !_isDesktop)
            const WispPlayerBar(),
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
    AppNavigation.instance.openLibraryItem(context, item);
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
