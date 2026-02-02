class TabRoutes {
  static const String home = '/home';
  static const String search = '/search';
  static const String library = '/library';
  static const String settings = '/settings';

  static String routeForIndex(int index) {
    switch (index) {
      case 1:
        return search;
      case 2:
        return library;
      case 3:
        return settings;
      case 0:
      default:
        return home;
    }
  }

  static int indexForRoute(String? routeName) {
    switch (routeName) {
      case search:
        return 1;
      case library:
        return 2;
      case settings:
        return 3;
      case home:
      default:
        return 0;
    }
  }

  static bool isTabRoute(String? routeName) {
    return routeName == home ||
        routeName == search ||
        routeName == library ||
        routeName == settings;
  }
}
