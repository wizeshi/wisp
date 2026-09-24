// Copyright © 2026 wizeshi

import 'package:flutter/widgets.dart';

import 'package:wisp/services/system/app_focus_service.dart';

/// Freezes a fast-changing, value-driven part of the UI while the app or
/// window is unfocused (backgrounded, minimized, or an inactive window).
///
/// This is meant for subtrees whose rebuild is triggered by something Flutter
/// dispatches straight to the dependent element (a `Provider`/`Selector`
/// value, a `ValueListenable`, an `AnimationController` tick, ...), where
/// simply not calling `setState` isn't enough to stop the rebuild. Instead,
/// [FocusFreezeBuilder] caches the last widget it built and, whenever
/// unfocused, hands that exact same widget instance back out. Flutter's
/// element tree treats an `identical` returned widget as a no-op, so the
/// child subtree's layout/paint work is skipped entirely until focus
/// returns, at which point the builder resumes and immediately catches up
/// to the latest [value].
///
/// Usage: wrap the part of a `Selector`/`ValueListenableBuilder` builder that
/// actually renders the volatile content, keyed by the value driving it:
///
/// ```dart
/// Selector<Player, Duration>(
///   selector: (_, player) => player.position,
///   builder: (context, position, _) {
///     return FocusFreezeBuilder<Duration>(
///       value: position,
///       builder: (context, position) => ProgressBar(position: position),
///     );
///   },
/// )
/// ```
class FocusFreezeBuilder<T> extends StatefulWidget {
  const FocusFreezeBuilder({
    super.key,
    required this.value,
    required this.builder,
  });

  /// The latest value driving this part of the UI. Changes to this value
  /// are ignored while unfocused; the widget built for the last value seen
  /// while focused keeps being shown.
  final T value;

  /// Builds the actual (potentially expensive) widget for [value]. Only
  /// invoked while the app/window is focused.
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<FocusFreezeBuilder<T>> createState() => _FocusFreezeBuilderState<T>();
}

class _FocusFreezeBuilderState<T> extends State<FocusFreezeBuilder<T>> {
  Widget? _cached;

  bool get _isFocused => AppFocusService.instance.isFocused.value;

  @override
  void initState() {
    super.initState();
    AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    if (_isFocused) {
      // Regained focus: rebuild so we catch up to the latest value.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cached = _cached;
    if (!_isFocused && cached != null) {
      return cached;
    }

    final built = widget.builder(context, widget.value);
    _cached = built;
    return built;
  }
}
