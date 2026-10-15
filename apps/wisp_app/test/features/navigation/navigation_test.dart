// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'package:wisp/features/navigation/router/app_router.dart';
import 'package:wisp/features/navigation/router/app_routes.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';

void main() {
  group('AppRoutes', () {
    test('defines correct path constants', () {
      expect(AppRoutes.home, '/home');
      expect(AppRoutes.search, '/search');
      expect(AppRoutes.library, '/library');
      expect(AppRoutes.settings, '/settings');
      expect(AppRoutes.list, '/list');
      expect(AppRoutes.artist, '/artist');
      expect(AppRoutes.user, '/user');
      expect(AppRoutes.dj, '/dj');
      expect(AppRoutes.debug, '/debug');
      expect(AppRoutes.player, '/player');
      expect(AppRoutes.lyrics, '/lyrics');
      expect(AppRoutes.queue, '/queue');
      expect(AppRoutes.audioAlternatives, '/audio-alternatives');
    });

    test('query parameters match expected structure', () {
      final listUri = Uri(
        path: AppRoutes.list,
        queryParameters: {
          AppRoutes.paramId: '123',
          AppRoutes.paramType: 'playlist',
          AppRoutes.paramSource: 'spotify',
        },
      );

      expect(listUri.toString(), '/list?id=123&type=playlist&source=spotify');
      expect(listUri.queryParameters[AppRoutes.paramId], '123');
      expect(listUri.queryParameters[AppRoutes.paramType], 'playlist');
      expect(listUri.queryParameters[AppRoutes.paramSource], 'spotify');
    });
  });

  group('NavigationHistory', () {
    test('tracks route stack and forward/back availability', () {
      final history = NavigationHistory.instance;
      history.recordLocation(AppRoutes.home);
      expect(history.currentRouteName, AppRoutes.home);
      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);

      history.recordLocation(AppRoutes.search);
      expect(history.currentRouteName, AppRoutes.search);
      expect(history.canGoBack, isTrue);
      expect(history.canGoForward, isFalse);

      history.recordLocation(AppRoutes.lyrics);
      expect(history.currentRouteName, AppRoutes.lyrics);
      expect(history.canGoBack, isTrue);
      expect(history.canGoForward, isFalse);

      // Popping to previous route
      history.recordLocation(AppRoutes.search);
      expect(history.currentRouteName, AppRoutes.search);
      expect(history.canGoBack, isTrue);
      expect(history.canGoForward, isTrue);
    });
  });

  group('NavigationService', () {
    test('requires initialization before router access', () {
      // In isolated tests before initialize is called
      expect(
        () => NavigationService.instance.router,
        throwsStateError,
      );
    });

    test('initializes with GoRouter instance', () {
      final mockRouter = GoRouter(
        routes: [
          GoRoute(path: AppRoutes.home, builder: (c, s) => const Placeholder()),
        ],
      );

      NavigationService.instance.initialize(mockRouter);
      expect(NavigationService.instance.router, same(mockRouter));
    });
  });

  group('AppRouter', () {
    testWidgets('createRouter builds router without sub-route assertion failure', (tester) async {
      final router = AppRouter.createRouter(appLinks: AppLinks());
      expect(router, isNotNull);
      expect(router.configuration.routes, isNotEmpty);
    });
  });
}
