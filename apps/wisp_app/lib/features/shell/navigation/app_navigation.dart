// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:wisp/core/theme/app_theme.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'package:wisp/features/playback/widgets/full_player.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/navigation/shell/navigation_state.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/navigation/views/list/view.dart' show SharedListType;
import 'package:wisp/features/navigation/views/alternatives/audio_alternatives_view.dart'
    show AudioAlternativeSelection;

enum FullPlayerDesktopMode { artwork, canvas, lyrics, queue }

class AppNavigation {
  AppNavigation._();

  static final AppNavigation instance = AppNavigation._();

  final ValueNotifier<bool> fullPlayerLyricsMode = ValueNotifier<bool>(false);
  final ValueNotifier<FullPlayerDesktopMode> fullPlayerDesktopMode =
      ValueNotifier<FullPlayerDesktopMode>(FullPlayerDesktopMode.artwork);
  final ValueNotifier<FullPlayerDesktopMode?> fullPlayerDesktopPreviousMode =
      ValueNotifier<FullPlayerDesktopMode?>(null);

  void setFullPlayerDesktopMode(
    FullPlayerDesktopMode mode, {
    bool rememberPrevious = true,
  }) {
    final currentMode = fullPlayerDesktopMode.value;
    if (rememberPrevious && currentMode != mode) {
      fullPlayerDesktopPreviousMode.value = currentMode;
    }
    fullPlayerDesktopMode.value = mode;
  }

  void restorePreviousFullPlayerDesktopMode() {
    final previousMode = fullPlayerDesktopPreviousMode.value;
    if (previousMode != null) {
      fullPlayerDesktopMode.value = previousMode;
    }
  }

  NavigatorState? get _shellNavigator =>
      NavigationHistory.instance.navigatorKey.currentState;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  NavigationState? get _navState {
    final shellNavigator = _shellNavigator;
    if (shellNavigator == null) {
      return null;
    }
    try {
      return shellNavigator.context.read<NavigationState>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _setWindowFullscreen(bool enabled) async {
    if (!_isDesktop) return;
    try {
      await windowManager.setFullScreen(enabled);
    } catch (_) {}
  }

  Future<void> _enterFullPlayerDesktopMode() async {
    _navState?.enterDesktopImmersiveMode();
    await _setWindowFullscreen(true);
  }

  Future<void> _exitFullPlayerDesktopMode() async {
    await _setWindowFullscreen(false);
    _navState?.exitDesktopImmersiveMode();
  }

  Future<bool> maybePopOverlay(BuildContext context) {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (!rootNavigator.canPop()) {
      return Future.value(false);
    }
    return rootNavigator.maybePop();
  }

  Future<bool> maybePopShell() async {
    if (NavigationService.instance.canPop()) {
      NavigationService.instance.pop();
      return true;
    }
    if (NavigationHistory.instance.canGoBack) {
      NavigationHistory.instance.goBack();
      return true;
    }
    return false;
  }

  void pushTab(int index) {
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

  void openSettings() {
    NavigationService.instance.pushSettings();
  }

  void openLibraryItem(BuildContext context, dynamic item) {
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
      NavigationService.instance.pushArtist(id: item.id, source: item.source);
      return;
    }

    if (item is GenericSimpleUser) {
      NavigationService.instance.pushUser(id: item.id, source: item.source);
    }
  }

  void navigateToDJView(BuildContext context) {
    NavigationService.instance.pushDJ();
  }

  void openSharedList(
    BuildContext context, {
    required String id,
    required SharedListType type,
    String? initialTitle,
    String? initialThumbnailUrl,
  }) {
    NavigationService.instance.pushList(
      id: id,
      type: type == SharedListType.album ? 'album' : 'playlist',
    );
  }

  void openDebug(BuildContext context) {
    NavigationService.instance.pushDebug();
  }

  void openArtist(
    BuildContext context, {
    required String artistId,
    GenericSimpleArtist? initialArtist,
    String? fallbackName,
  }) {
    NavigationService.instance.pushArtist(id: artistId);
  }

  void openUser(
    BuildContext context, {
    required String userId,
    GenericUser? initialUser,
    AppStyle? style,
  }) {
    NavigationService.instance.pushUser(id: userId);
  }

  void openPlaybackContext(
    BuildContext context, {
    required PlaybackContextType contextType,
    required String contextId,
    String? contextName,
  }) {
    if (contextType == PlaybackContextType.artist) {
      openArtist(context, artistId: contextId, fallbackName: contextName);
      return;
    }

    final type = contextType == PlaybackContextType.album
        ? SharedListType.album
        : SharedListType.playlist;

    openSharedList(
      context,
      id: contextId,
      type: type,
      initialTitle: contextName,
    );
  }

  /// Opens YouTube alternatives inside the shell navigator so desktop
  /// navigation chrome remains visible regardless of where it was launched.
  Future<String?> openYouTubeAlternatives(GenericSong track) {
    return NavigationService.instance.pushYouTubeAlternatives<String>(track.id);
  }

  Future<AudioAlternativeSelection?> openAudioAlternatives(GenericSong track) {
    return NavigationService.instance.pushAudioAlternatives<AudioAlternativeSelection>(track.id);
  }

  Future<void> openFullPlayer() async {
    fullPlayerLyricsMode.value = false;
    fullPlayerDesktopMode.value = FullPlayerDesktopMode.artwork;
    fullPlayerDesktopPreviousMode.value = null;
    AppleMusicFullScreenPlayer.resetTemporaryOptions();
    if (_isDesktop) {
      await _enterFullPlayerDesktopMode();
    }
    await NavigationService.instance.openPlayer();
  }

  Future<void> closeFullPlayer() async {
    fullPlayerLyricsMode.value = false;
    fullPlayerDesktopMode.value = FullPlayerDesktopMode.artwork;
    fullPlayerDesktopPreviousMode.value = null;
    NavigationService.instance.closePlayer();
    if (_isDesktop) {
      await _exitFullPlayerDesktopMode();
    }
  }

  Future<void> disableFullPlayerDesktopMode() async {
    if (_isDesktop) {
      await _exitFullPlayerDesktopMode();
    }
  }

  Future<void> minimizeWindow() async {
    if (!_isDesktop) return;
    try {
      await windowManager.minimize();

      final minimized = await windowManager.isMinimized();
      if (minimized) {
        return;
      }

      final isFullScreen = await windowManager.isFullScreen();
      if (isFullScreen) {
        await windowManager.setFullScreen(false);
        await windowManager.minimize();
      }
    } catch (_) {}
  }

  Future<void> onFullPlayerPopped() async {
    if (_isDesktop) {
      await _exitFullPlayerDesktopMode();
    }
  }

  void openLyrics() {
    if (NavigationHistory.instance.currentRouteName == '/lyrics') {
      return;
    }
    fullPlayerLyricsMode.value = false;
    fullPlayerDesktopMode.value = FullPlayerDesktopMode.artwork;
    fullPlayerDesktopPreviousMode.value = null;
    NavigationService.instance.pushLyrics();
  }

  void openQueue([BuildContext? context]) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      final ctx = context ??
          NavigationHistory.instance.navigatorKey.currentContext ??
          NavigationHistory.instance.rootNavigatorKey.currentContext;
      if (ctx != null) {
        showMobileQueueSheet(ctx);
      }
      return;
    }

    if (NavigationHistory.instance.currentRouteName == '/queue') {
      return;
    }
    fullPlayerLyricsMode.value = false;
    fullPlayerDesktopMode.value = FullPlayerDesktopMode.artwork;
    fullPlayerDesktopPreviousMode.value = null;
    NavigationService.instance.pushQueue();
  }
}
