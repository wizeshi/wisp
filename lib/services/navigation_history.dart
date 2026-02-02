import 'package:flutter/material.dart';

class NavigationHistory {
  NavigationHistory._();

  static final NavigationHistory instance = NavigationHistory._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final NavigationHistoryObserver observer = NavigationHistoryObserver(this);
  final ValueNotifier<Route<dynamic>?> currentRoute = ValueNotifier<Route<dynamic>?>(null);

  final List<Route<dynamic>> _history = [];
  int _index = -1;
  bool _isRestoring = false;

  bool get canGoBack => _index > 0;
  bool get canGoForward => _index + 1 < _history.length;
  String? get currentRouteName => currentRoute.value?.settings.name;

  void goBack() {
    navigatorKey.currentState?.maybePop();
  }

  void goForward() {
    if (!canGoForward) return;
    final next = _history[_index + 1];
    final cloned = _cloneRoute(next);
    if (cloned == null) return;
    _isRestoring = true;
    navigatorKey.currentState?.push(cloned);
  }

  void _handlePush(Route<dynamic> route) {
    if (_isRestoring) {
      _isRestoring = false;
      if (_index + 1 < _history.length) {
        _history[_index + 1] = route;
        _index++;
      } else {
        _history.add(route);
        _index = _history.length - 1;
      }
      currentRoute.value = route;
      return;
    }

    if (_index < _history.length - 1) {
      _history.removeRange(_index + 1, _history.length);
    }
    _history.add(route);
    _index = _history.length - 1;
    currentRoute.value = route;
  }

  void _handlePop(Route<dynamic> route) {
    if (_index > 0) {
      _index--;
    }
    currentRoute.value = _index >= 0 ? _history[_index] : null;
  }

  void _handleRemove(Route<dynamic> route) {
    final removeIndex = _history.indexOf(route);
    if (removeIndex == -1) return;
    _history.removeAt(removeIndex);
    if (_index >= removeIndex) {
      _index = (_index - 1).clamp(-1, _history.length - 1);
    }
    currentRoute.value = _index >= 0 ? _history[_index] : null;
  }

  void _handleReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null || newRoute == null) return;
    final replaceIndex = _history.indexOf(oldRoute);
    if (replaceIndex == -1) return;
    _history[replaceIndex] = newRoute;
    if (_index == replaceIndex) {
      currentRoute.value = newRoute;
    }
  }

  Route<dynamic>? _cloneRoute(Route<dynamic> route) {
    if (route is MaterialPageRoute) {
      return MaterialPageRoute(
        builder: route.builder,
        settings: route.settings,
      );
    }
    if (route is PageRouteBuilder) {
      return PageRouteBuilder(
        pageBuilder: route.pageBuilder,
        transitionsBuilder: route.transitionsBuilder,
        transitionDuration: route.transitionDuration,
        reverseTransitionDuration: route.reverseTransitionDuration,
        settings: route.settings,
      );
    }
    return null;
  }
}

class NavigationHistoryObserver extends NavigatorObserver {
  final NavigationHistory _history;

  NavigationHistoryObserver(this._history);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _history._handlePush(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _history._handlePop(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _history._handleRemove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _history._handleReplace(newRoute: newRoute, oldRoute: oldRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
