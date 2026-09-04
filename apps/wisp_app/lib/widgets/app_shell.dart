// Copyright © 2026 wizeshi

import 'dart:io' show Platform;
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp/providers/preferences/preferences_provider.dart';

import '../providers/library/library_state.dart';
import '../providers/navigation_state.dart';
import '../providers/search/search_state.dart';
import '../services/app_navigation.dart';
import '../services/navigation_history.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/tab_routes.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../widgets/navigation.dart';
import '../widgets/player_bar.dart';
import '../widgets/right_sidebar.dart';
import '../widgets/title_bar.dart';
import '../models/metadata_models.dart';
import '../views/home.dart';
import '../views/library.dart';
import '../views/search.dart';
import '../views/settings.dart';
import '../views/list_detail.dart';
import '../views/artist_detail.dart';

class AppShell extends StatefulWidget {
  final AppLinks appLinks;

  const AppShell({super.key, required this.appLinks});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchAutoSwitchTimer;
  String _lastWindowTitle = 'wisp';
  final GlobalKey<ScaffoldMessengerState> _contentMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Displays a snackbar within the active navigation page rather than across
  /// the whole app shell.
  late final void Function(String) showSnackBar = _showContentSnackBar;

  void _showContentSnackBar(String message) {
    final messenger = _contentMessengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    NavigationHistory.instance.currentRoute.addListener(_handleRouteChange);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _searchAutoSwitchTimer?.cancel();
    _searchFocusNode.dispose();
    NavigationHistory.instance.currentRoute.removeListener(_handleRouteChange);
    super.dispose();
  }

  final _allowedDebugKeys = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];
  final _debugKeySequence = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];
  List<LogicalKeyboardKey> _lastKeysPressed = [];

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final logicalKey = event.logicalKey;

    final isEditingText = _isEditingText();

    if (logicalKey == LogicalKeyboardKey.space) {
      // Don't intercept space when the user is typing in a text field.
      if (isEditingText) return false;
      final coordinator = context.read<PlaybackCoordinator>();
      if (coordinator.effectiveIsPlaying) {
        unawaited(coordinator.pause());
      } else {
        unawaited(coordinator.play());
      }
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.escape) {
      if (NavigationHistory.instance.currentRouteName == '/fullplayer') {
        unawaited(AppNavigation.instance.closeFullPlayer());
        return true;
      }
    }

    // Code for detecting the debug key sequence (Konami code)
    if (!isEditingText && _allowedDebugKeys.contains(logicalKey)) {
      _lastKeysPressed.add(logicalKey);
      if (_lastKeysPressed.length > _debugKeySequence.length) {
        _lastKeysPressed.removeAt(0);
      }
      if (_lastKeysPressed.length == _debugKeySequence.length) {
        bool isMatch = true;
        for (int i = 0; i < _debugKeySequence.length; i++) {
          if (_lastKeysPressed[i] != _debugKeySequence[i]) {
            isMatch = false;
            break;
          }
        }
        if (isMatch) {
          final prefs = context.read<PreferencesProvider>();
          prefs.setDebugModeEnabled(true).then((newMode) {
            if (mounted) {
              showSnackBar('Debug mode enabled');
            }
          });
          _lastKeysPressed.clear();
        }
      }
    }

    return false;
  }

  bool _isEditingText() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null) return false;
    final focusContext = primaryFocus.context;
    if (focusContext == null) return false;
    // The focus node is attached to the inner Focus widget inside EditableText,
    // not to EditableText itself — so check the focused widget and its ancestors.
    if (focusContext.widget is EditableText) return true;
    bool found = false;
    focusContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
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

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationState>();
    final searchState = context.read<SearchState>();
    final searchController = searchState.controller;
    final isDesktopImmersive = _isDesktop && navState.desktopImmersiveMode;

    final enableExitPrompt = !_isDesktop;

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
                    onLibraryItemSelected: _handleLibraryItemSelected,
                    expandedWidth: navState.leftSidebarWidth,
                  ),
                if (_isDesktop && !isDesktopImmersive)
                  _LeftResizeHandle(onResize: navState.adjustLeftSidebarWidth),
                Expanded(
                  child: ScaffoldMessenger(
                    key: _contentMessengerKey,
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Navigator(
                        key: NavigationHistory.instance.navigatorKey,
                        observers: [NavigationHistory.instance.observer],
                        initialRoute: TabRoutes.home,
                        onGenerateRoute: _onGenerateRoute,
                      ),
                    ),
                  ),
                ),
                if (_isDesktop &&
                    !isDesktopImmersive &&
                    navState.rightSidebarVisible)
                  RightSidebar(
                    width: navState.rightSidebarWidth,
                    onResize: navState.adjustRightSidebarWidth,
                  ),
              ],
            ),
          ),
          if (navState.selectedNavIndex != 3 && !_isDesktop)
            const WispPlayerBar(),
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
