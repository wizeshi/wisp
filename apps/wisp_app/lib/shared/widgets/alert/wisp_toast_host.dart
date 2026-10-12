// Copyright © 2026 wizeshi

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert.dart';

/// Controller interface to show and dismiss toasts from any context.
abstract class WispToastManager {
  void show({
    required String message,
    String? title,
    AlertSeverity severity = AlertSeverity.info,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
  });

  void dismissAll();
}

/// Global host widget placed at the root of the widget tree (via [MaterialApp.builder])
/// so that alert toasts render above all Navigator routes, dialogs, and sheets.
class WispToastHost extends StatefulWidget {
  final Widget child;

  const WispToastHost({super.key, required this.child});

  /// Finds the [WispToastManager] in the nearest ancestor or falls back to
  /// the root navigator context.
  static WispToastManager? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_WispToastScope>();
    if (scope != null) return scope.manager;

    // Fallback to navigatorKey context if available and different
    final rootContext = NavigationHistory.instance.navigatorKey.currentContext;
    if (rootContext != null && rootContext != context) {
      final rootScope = rootContext.dependOnInheritedWidgetOfExactType<_WispToastScope>();
      if (rootScope != null) return rootScope.manager;
    }
    return _activeHostState;
  }

  static WispToastManager of(BuildContext context) {
    final manager = maybeOf(context);
    assert(manager != null, 'No WispToastHost found in context hierarchy.');
    return manager!;
  }

  @override
  State<WispToastHost> createState() => _WispToastHostState();
}

_WispToastHostState? _activeHostState;

class _WispToastHostState extends State<WispToastHost>
    with TickerProviderStateMixin
    implements WispToastManager {
  static const int _maxVisibleToasts = 3;
  final List<_ActiveToast> _toasts = [];
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _activeHostState = this;
  }

  @override
  void dispose() {
    if (_activeHostState == this) {
      _activeHostState = null;
    }
    for (final toast in _toasts) {
      toast.dispose();
    }
    _toasts.clear();
    super.dispose();
  }

  @override
  void show({
    required String message,
    String? title,
    AlertSeverity severity = AlertSeverity.info,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    if (!mounted) return;

    // If max reached, dismiss the oldest
    if (_toasts.length >= _maxVisibleToasts) {
      _dismissToast(_toasts.first);
    }

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    final activeToast = _ActiveToast(
      id: UniqueKey().toString(),
      message: message,
      title: title,
      severity: severity,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      remainingDuration: duration,
      controller: controller,
    );

    setState(() {
      _toasts.add(activeToast);
    });

    controller.forward();

    if (!_isHovering) {
      _startTimer(activeToast);
    }
  }

  void _startTimer(_ActiveToast toast) {
    toast.timer?.cancel();
    toast.startTime = DateTime.now();
    toast.timer = Timer(toast.remainingDuration, () {
      _dismissToast(toast);
    });
  }

  void _pauseTimers() {
    _isHovering = true;
    final now = DateTime.now();
    for (final toast in _toasts) {
      if (toast.timer != null && toast.startTime != null) {
        toast.timer?.cancel();
        final elapsed = now.difference(toast.startTime!);
        final remaining = toast.remainingDuration - elapsed;
        toast.remainingDuration = remaining.isNegative ? Duration.zero : remaining;
      }
    }
  }

  void _resumeTimers() {
    _isHovering = false;
    for (final toast in _toasts) {
      _startTimer(toast);
    }
  }

  void _dismissToast(_ActiveToast toast) {
    if (!mounted || toast.isDismissing) return;
    toast.isDismissing = true;
    toast.timer?.cancel();

    toast.controller.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _toasts.remove(toast);
      });
      toast.dispose();
    });
  }

  @override
  void dismissAll() {
    if (!mounted) return;
    for (final toast in List<_ActiveToast>.from(_toasts)) {
      _dismissToast(toast);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width >= 600;

    return _WispToastScope(
      manager: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_toasts.isNotEmpty)
            Positioned(
              top: isDesktop
                  ? 44
                  : mediaQuery.padding.top + 12,
              right: 16,
              left: isDesktop ? null : 16,
              width: isDesktop ? 380 : null,
              child: MouseRegion(
                onEnter: (_) => _pauseTimers(),
                onExit: (_) => _resumeTimers(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: isDesktop
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.stretch,
                  children: [
                    for (final toast in _toasts)
                      Padding(
                        key: ValueKey(toast.id),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ToastItemView(
                          toast: toast,
                          isDesktop: isDesktop,
                          onDismiss: () => _dismissToast(toast),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToastItemView extends StatelessWidget {
  final _ActiveToast toast;
  final bool isDesktop;
  final VoidCallback onDismiss;

  const _ToastItemView({
    required this.toast,
    required this.isDesktop,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final slideBegin = isDesktop ? const Offset(0.3, 0.0) : const Offset(0.0, -0.4);

    return SlideTransition(
      position: Tween<Offset>(
        begin: slideBegin,
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: toast.controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: FadeTransition(
        opacity: toast.controller,
        child: Dismissible(
          key: ValueKey(toast.id),
          direction: isDesktop ? DismissDirection.endToStart : DismissDirection.up,
          onDismissed: (_) => onDismiss(),
          child: WispAlert(
            message: toast.message,
            title: toast.title,
            severity: toast.severity,
            icon: toast.icon,
            actionLabel: toast.actionLabel,
            onAction: toast.onAction != null
                ? () {
                    toast.onAction!();
                    onDismiss();
                  }
                : null,
            onClose: onDismiss,
          ),
        ),
      ),
    );
  }
}

class _ActiveToast {
  final String id;
  final String message;
  final String? title;
  final AlertSeverity severity;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  Duration remainingDuration;
  final AnimationController controller;
  Timer? timer;
  DateTime? startTime;
  bool isDismissing = false;

  _ActiveToast({
    required this.id,
    required this.message,
    this.title,
    required this.severity,
    this.icon,
    this.actionLabel,
    this.onAction,
    required this.duration,
    required this.remainingDuration,
    required this.controller,
  });

  void dispose() {
    timer?.cancel();
    controller.dispose();
  }
}

class _WispToastScope extends InheritedWidget {
  final WispToastManager manager;

  const _WispToastScope({
    required this.manager,
    required super.child,
  });

  @override
  bool updateShouldNotify(covariant _WispToastScope oldWidget) =>
      manager != oldWidget.manager;
}

