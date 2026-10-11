// Copyright © 2026 wizeshi

import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'app_routes.dart';
import 'navigation_service.dart';
import '../shell/app_shell.dart';

import '../views/home/view.dart';
import '../views/search/view.dart';
import '../views/library/view.dart';
import '../views/list/view.dart';
import '../views/artist/view.dart';
import '../views/user/view.dart';
import '../views/settings/view.dart';
import '../views/dj/view.dart';
import '../views/debug/view.dart';
import '../views/player/full_player_view.dart';
import '../views/alternatives/audio_alternatives_view.dart';
import '../views/alternatives/youtube_alternatives_view.dart';
import 'package:wisp/features/playback/views/lyrics_view.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/features/onboarding/views/mobile_welcome_view.dart';

class AppRouter {
  AppRouter._();

  static final GlobalKey<NavigatorState> rootNavigatorKey =
      NavigationHistory.instance.rootNavigatorKey;
  static final GlobalKey<NavigatorState> shellNavigatorKey =
      NavigationHistory.instance.navigatorKey;

  static Page<dynamic> _buildAdaptivePage({
    required GoRouterState state,
    required Widget child,
    bool isTab = false,
  }) {
    final wrappedChild = Material(
      color: const Color(0xFF121212),
      child: child,
    );
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final pageKey = ValueKey(state.uri.toString());
    if (isDesktop || isTab) {
      return NoTransitionPage(
        key: pageKey,
        name: state.name ?? state.uri.toString(),
        child: wrappedChild,
      );
    }
    if (Platform.isIOS) {
      return CupertinoPage(
        key: pageKey,
        name: state.name ?? state.uri.toString(),
        child: wrappedChild,
      );
    }
    return MaterialPage(
      key: pageKey,
      name: state.name ?? state.uri.toString(),
      child: wrappedChild,
    );
  }

  static GoRouter createRouter({
    required AppLinks appLinks,
    PreferencesProvider? preferences,
  }) {
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.home,
      refreshListenable: preferences,
      observers: [NavigationHistory.instance.observer],
      redirect: (context, state) {
        if (preferences == null) return null;
        final isMobile = Platform.isAndroid || Platform.isIOS;
        if (!isMobile) return null;

        // If preferences haven't finished loading from storage yet, do not redirect
        if (!preferences.isLoaded) return null;

        if (!preferences.isFirstBootCompleted && state.matchedLocation != AppRoutes.onboarding) {
          return AppRoutes.onboarding;
        }
        if (preferences.isFirstBootCompleted && state.matchedLocation == AppRoutes.onboarding) {
          return AppRoutes.home;
        }
        return null;
      },
      routes: [
        ShellRoute(
          navigatorKey: shellNavigatorKey,
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutes.home,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: true,
                child: const HomePage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.search,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: true,
                child: SearchPageView(
                  query: state.uri.queryParameters[AppRoutes.paramQuery],
                  source: state.uri.queryParameters[AppRoutes.paramSource],
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.library,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: true,
                child: LibraryPageView(
                  filter: state.uri.queryParameters[AppRoutes.paramFilter],
                  folderId: state.uri.queryParameters[AppRoutes.paramFolderId],
                ),
              ),
            ),
            // Detail routes inside the shell (keeping navbar & playerbar docked)
            GoRoute(
              path: AppRoutes.list,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: false,
                child: ListDetailView(
                  id: state.uri.queryParameters[AppRoutes.paramId] ?? '',
                  type: state.uri.queryParameters[AppRoutes.paramType] ?? 'playlist',
                  source: state.uri.queryParameters[AppRoutes.paramSource],
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.artist,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: false,
                child: ArtistView(
                  id: state.uri.queryParameters[AppRoutes.paramId] ?? '',
                  source: state.uri.queryParameters[AppRoutes.paramSource],
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.user,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: false,
                child: UserView(
                  id: state.uri.queryParameters[AppRoutes.paramId] ?? '',
                  source: state.uri.queryParameters[AppRoutes.paramSource],
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.dj,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: false,
                child: const DJView(),
              ),
            ),
            GoRoute(
              path: AppRoutes.debug,
              pageBuilder: (context, state) => _buildAdaptivePage(
                state: state,
                isTab: false,
                child: const DebugView(),
              ),
            ),
            if (!(Platform.isAndroid || Platform.isIOS)) ...[
              GoRoute(
                path: AppRoutes.settings,
                pageBuilder: (context, state) => _buildAdaptivePage(
                  state: state,
                  isTab: false,
                  child: const SettingsView(),
                ),
              ),
              GoRoute(
                path: AppRoutes.lyrics,
                pageBuilder: (context, state) => _buildAdaptivePage(
                  state: state,
                  isTab: false,
                  child: const LyricsView(),
                ),
              ),
              GoRoute(
                path: AppRoutes.queue,
                pageBuilder: (context, state) => _buildAdaptivePage(
                  state: state,
                  isTab: false,
                  child: const QueueView(),
                ),
              ),
            ],
          ],
        ),

        // Routes that cover the entire shell
        if (Platform.isAndroid || Platform.isIOS) ...[
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: AppRoutes.settings,
            pageBuilder: (context, state) => _buildAdaptivePage(
              state: state,
              isTab: false,
              child: const SettingsView(),
            ),
          ),
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: AppRoutes.lyrics,
            pageBuilder: (context, state) => _buildAdaptivePage(
              state: state,
              isTab: false,
              child: const LyricsView(),
            ),
          ),
        ],
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          path: AppRoutes.audioAlternatives,
          pageBuilder: (context, state) => _buildAdaptivePage(
            state: state,
            isTab: false,
            child: AudioAlternativesPageView(
              trackId: state.uri.queryParameters[AppRoutes.paramId] ?? '',
            ),
          ),
        ),
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          path: AppRoutes.youtubeAlternatives,
          pageBuilder: (context, state) => _buildAdaptivePage(
            state: state,
            isTab: false,
            child: YouTubeAlternativesPageView(
              trackId: state.uri.queryParameters[AppRoutes.paramId] ?? '',
            ),
          ),
        ),
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          path: AppRoutes.player,
          pageBuilder: (context, state) => _buildAdaptivePage(
            state: state,
            isTab: false,
            child: const FullScreenPlayer(),
          ),
        ),
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          path: '/fullplayer',
          pageBuilder: (context, state) => _buildAdaptivePage(
            state: state,
            isTab: false,
            child: const FullScreenPlayer(),
          ),
        ),
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          path: AppRoutes.onboarding,
          pageBuilder: (context, state) => _buildAdaptivePage(
            state: state,
            isTab: true,
            child: MobileWelcomeView(appLinks: appLinks),
          ),
        ),
      ],
    );

    NavigationService.instance.initialize(router);
    return router;
  }
}
