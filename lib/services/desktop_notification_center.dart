import 'dart:async';
import 'package:flutter/foundation.dart';

class DesktopNotification {
  final int id;
  final String title;
  final String body;
  final int progress;
  final int maxProgress;
  final bool isComplete;
  final DateTime updatedAt;

  const DesktopNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.progress,
    required this.maxProgress,
    required this.isComplete,
    required this.updatedAt,
  });

  DesktopNotification copyWith({
    String? title,
    String? body,
    int? progress,
    int? maxProgress,
    bool? isComplete,
    DateTime? updatedAt,
  }) {
    return DesktopNotification(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      progress: progress ?? this.progress,
      maxProgress: maxProgress ?? this.maxProgress,
      isComplete: isComplete ?? this.isComplete,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DesktopNotificationCenter extends ChangeNotifier {
  static final DesktopNotificationCenter instance = DesktopNotificationCenter._();

  DesktopNotificationCenter._();

  final List<DesktopNotification> _items = [];
  final Map<int, Timer> _dismissTimers = {};
  bool _collapsed = false;

  List<DesktopNotification> get items => List.unmodifiable(_items);
  bool get collapsed => _collapsed;

  void toggleCollapsed() {
    _collapsed = !_collapsed;
    notifyListeners();
  }

  void showProgress({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) {
    _dismissTimers[id]?.cancel();
    final index = _items.indexWhere((n) => n.id == id);
    final next = DesktopNotification(
      id: id,
      title: title,
      body: body,
      progress: progress,
      maxProgress: maxProgress,
      isComplete: false,
      updatedAt: DateTime.now(),
    );
    if (index == -1) {
      _items.insert(0, next);
    } else {
      _items[index] = next;
    }
    notifyListeners();
  }

  void showComplete({
    required int id,
    required String title,
    required String body,
  }) {
    final index = _items.indexWhere((n) => n.id == id);
    final next = DesktopNotification(
      id: id,
      title: title,
      body: body,
      progress: 1,
      maxProgress: 1,
      isComplete: true,
      updatedAt: DateTime.now(),
    );
    if (index == -1) {
      _items.insert(0, next);
    } else {
      _items[index] = next;
    }
    notifyListeners();

    _dismissTimers[id]?.cancel();
    _dismissTimers[id] = Timer(const Duration(seconds: 6), () {
      dismiss(id);
    });
  }

  void dismiss(int id) {
    _dismissTimers[id]?.cancel();
    _dismissTimers.remove(id);
    _items.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clearAll() {
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();
    _items.clear();
    notifyListeners();
  }
}
