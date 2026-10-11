// Copyright © 2026 wizeshi

import 'dart:io' show Platform;
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

import 'package:wisp/features/navigation/shell/navigation_state.dart';
import 'package:wisp/features/search/state/search_state.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'package:wisp/features/navigation/shell/navigation_bar/widget.dart';
import 'package:wisp/features/playback/widgets/player_bar.dart';
import 'package:wisp/features/navigation/shell/right_sidebar/widget.dart';
import 'package:wisp/features/navigation/shell/title_bar/widget.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/models/metadata_models.dart';

class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

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
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _searchAutoSwitchTimer?.cancel();
    _searchFocusNode.dispose();
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
  final List<LogicalKeyboardKey> _lastKeysPressed = [];

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final logicalKey = event.logicalKey;
    final isEditingText = _isEditingText();

    if (logicalKey == LogicalKeyboardKey.space) {
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
      NavigationService.instance.closePlayer();
      return true;
    }

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

  void _pushTab(int index) {
    final navState = context.read<NavigationState>();
    navState.setNavIndex(index);
    switch (index) {
      case 0:
        NavigationService.instance.goHome();
        break;
      case 1:
        NavigationService.instance.goSearch();
        break;
      case 2:
        NavigationService.instance.goLibrary();
        break;
      case 3:
        NavigationService.instance.pushSettings();
        break;
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

  String _buildWindowTitle(GenericSong? track) {
    if (track == null || track.title.trim().isEmpty) {
      return 'wisp';
    }
    final artistName = track.artists.isNotEmpty
        ? track.artists.map((a) => a.name.trim()).join(', ')
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
    if (NavigationService.instance.canPop()) {
      NavigationService.instance.pop();
      return;
    }
    if (NavigationHistory.instance.canGoBack) {
      NavigationHistory.instance.goBack();
      return;
    }
    if (!enableExitPrompt) return;

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App'),
        content: const Text('Do you want to exit wisp?'),
        actions: [
          GenericTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          GenericTextButton(
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
    final selectedSource = context.select<SearchState, String>(
      (s) => s.selectedSource,
    );
    final searchController = context.read<SearchState>().controller;
    final availableSources = context.select<MetadataManager, List<String>>(
      (m) => m.availableProviders.map((p) => p.displayName).toList(),
    );
    final effectiveSource = availableSources.contains(selectedSource)
        ? selectedSource
        : (availableSources.isNotEmpty ? availableSources.first : 'Spotify');
    final isDesktopImmersive = _isDesktop && navState.desktopImmersiveMode;
    final enableExitPrompt = !_isDesktop;

    final keyboardVisible =
        !_isDesktop && MediaQuery.viewInsetsOf(context).bottom > 0;

    final contentWidget = ScaffoldMessenger(
      key: _contentMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: widget.child,
      ),
    );

    final Widget shellBody;
    if (_isDesktop) {
      shellBody = Column(
        children: [
          _buildWindowTitleSync(),
          if (!isDesktopImmersive)
            RepaintBoundary(
              child: WispTitleBar(
                onHomeTap: () => _pushTab(0),
                onSettingsTap: () => _pushTab(3),
                searchController: searchController,
                searchFocusNode: _searchFocusNode,
                onSearchChanged: _scheduleSearchAutoSwitch,
                onSearchSubmitted: () {
                  _pushTab(1);
                  context.read<SearchState>().submit();
                },
                onSearchCleared: () => context.read<SearchState>().clear(),
                availableSources: availableSources,
                selectedSource: effectiveSource,
                onSourceChanged: (source) {
                  final search = context.read<SearchState>();
                  search.setSelectedSource(source);
                  search.submit();
                },
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isDesktopImmersive)
                  RepaintBoundary(
                    child: WispNavigation(
                      selectedView: navState.selectedLibraryView,
                      onViewChanged: navState.setLibraryView,
                      selectedIndex: navState.selectedNavIndex,
                      onDestinationSelected: (index) {
                        _pushTab(index);
                      },
                      onLibraryItemSelected: _handleLibraryItemSelected,
                      expandedWidth: navState.leftSidebarWidth,
                    ),
                  ),
                if (!isDesktopImmersive)
                  _LeftResizeHandle(onResize: navState.adjustLeftSidebarWidth),
                Expanded(
                  child: RepaintBoundary(child: contentWidget),
                ),
                if (!isDesktopImmersive && navState.rightSidebarVisible)
                  RightSidebar(
                    width: navState.rightSidebarWidth,
                    onResize: navState.adjustRightSidebarWidth,
                  ),
              ],
            ),
          ),
          if (!isDesktopImmersive)
            const RepaintBoundary(
              child: WispPlayerBar(),
            ),
        ],
      );
    } else {
      shellBody = Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: contentWidget),
          ),
          if (navState.selectedNavIndex != 3 && !keyboardVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: RepaintBoundary(
                      child: WispPlayerBar(),
                    ),
                  ),
                  RepaintBoundary(
                    child: WispNavigation(
                      selectedView: navState.selectedLibraryView,
                      onViewChanged: navState.setLibraryView,
                      selectedIndex: navState.selectedNavIndex,
                      onDestinationSelected: (index) {
                        _pushTab(index);
                      },
                      onLibraryItemSelected: _handleLibraryItemSelected,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final shell = Material(
      color: const Color(0xFF121212),
      child: shellBody,
    );

    if (!enableExitPrompt) {
      return shell;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handlePop(context, enableExitPrompt);
      },
      child: shell,
    );
  }

  void _handleLibraryItemSelected(dynamic item) {
    if (item is GenericPlaylist) {
      NavigationService.instance.pushList(
        id: item.id,
        type: 'playlist',
        source: item.source,
      );
      return;
    }

    if (item is GenericAlbum) {
      NavigationService.instance.pushList(
        id: item.id,
        type: 'album',
        source: item.source,
      );
      return;
    }

    if (item is GenericSimpleArtist) {
      NavigationService.instance.pushArtist(
        id: item.id,
        source: item.source,
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
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
      ),
    );
  }
}

