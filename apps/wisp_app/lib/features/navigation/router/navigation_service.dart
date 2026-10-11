// Copyright © 2026 wizeshi

import 'dart:io' show Platform;
import 'package:go_router/go_router.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'app_routes.dart';

class NavigationService {
  NavigationService._();

  static final NavigationService instance = NavigationService._();

  late GoRouter _router;
  bool _isInitialized = false;

  void initialize(GoRouter router) {
    _router = router;
    _isInitialized = true;

    final initialUri = router.routerDelegate.currentConfiguration.uri.toString();
    NavigationHistory.instance.recordLocation(initialUri);

    router.routerDelegate.addListener(() {
      final uri = router.routerDelegate.currentConfiguration.uri.toString();
      NavigationHistory.instance.recordLocation(uri);
    });
  }

  GoRouter get router {
    if (!_isInitialized) {
      throw StateError('NavigationService has not been initialized with a GoRouter instance');
    }
    return _router;
  }

  void goHome() {
    while (router.canPop()) {
      router.pop();
    }
    router.go(AppRoutes.home);
  }

  void goSearch({String? query, String? source}) {
    final params = <String, String>{};
    if (query != null && query.isNotEmpty) params[AppRoutes.paramQuery] = query;
    if (source != null && source.isNotEmpty) params[AppRoutes.paramSource] = source;

    final uri = Uri(path: AppRoutes.search, queryParameters: params.isNotEmpty ? params : null);
    router.go(uri.toString());
  }

  void goLibrary({String? filter, String? folderId}) {
    final params = <String, String>{};
    if (filter != null && filter.isNotEmpty) params[AppRoutes.paramFilter] = filter;
    if (folderId != null && folderId.isNotEmpty) params[AppRoutes.paramFolderId] = folderId;

    final uri = Uri(path: AppRoutes.library, queryParameters: params.isNotEmpty ? params : null);
    router.go(uri.toString());
  }

  void pushList({
    required String id,
    required String type,
    String? source,
  }) {
    final params = <String, String>{
      AppRoutes.paramId: id,
      AppRoutes.paramType: type,
    };
    if (source != null && source.isNotEmpty) {
      params[AppRoutes.paramSource] = source;
    }
    final uri = Uri(path: AppRoutes.list, queryParameters: params);
    router.go(uri.toString());
  }

  void pushArtist({
    required String id,
    String? source,
  }) {
    final params = <String, String>{
      AppRoutes.paramId: id,
    };
    if (source != null && source.isNotEmpty) {
      params[AppRoutes.paramSource] = source;
    }
    final uri = Uri(path: AppRoutes.artist, queryParameters: params);
    router.go(uri.toString());
  }

  void pushUser({
    required String id,
    String? source,
  }) {
    final params = <String, String>{
      AppRoutes.paramId: id,
    };
    if (source != null && source.isNotEmpty) {
      params[AppRoutes.paramSource] = source;
    }
    final uri = Uri(path: AppRoutes.user, queryParameters: params);
    router.go(uri.toString());
  }

  Future<T?> pushSettings<T>({String? section}) {
    final params = <String, String>{};
    if (section != null && section.isNotEmpty) {
      params[AppRoutes.paramSection] = section;
    }
    final uri = Uri(
      path: AppRoutes.settings,
      queryParameters: params.isNotEmpty ? params : null,
    );
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      return router.push<T>(uri.toString());
    } else {
      router.go(uri.toString());
      return Future.value(null);
    }
  }

  void pushDJ() {
    router.go(AppRoutes.dj);
  }

  void pushDebug() {
    router.go(AppRoutes.debug);
  }

  void pushLyrics() {
    router.go(AppRoutes.lyrics);
  }

  void pushQueue() {
    router.go(AppRoutes.queue);
  }

  Future<T?> openPlayer<T>() {
    return router.push<T>(AppRoutes.player);
  }

  void closePlayer() {
    if (router.canPop()) {
      router.pop();
    }
  }

  Future<T?> pushAudioAlternatives<T>(String trackId) {
    final uri = Uri(
      path: AppRoutes.audioAlternatives,
      queryParameters: {AppRoutes.paramId: trackId},
    );
    return router.push<T>(uri.toString());
  }

  Future<T?> pushYouTubeAlternatives<T>(String trackId) {
    final uri = Uri(
      path: AppRoutes.youtubeAlternatives,
      queryParameters: {AppRoutes.paramId: trackId},
    );
    return router.push<T>(uri.toString());
  }

  bool canPop() => router.canPop();

  void pop<T>([T? result]) {
    if (router.canPop()) {
      router.pop(result);
    }
  }
}

