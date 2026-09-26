// Copyright © 2026 wizeshi

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Global scroll behavior for Wisp desktop & mobile.
///
/// Enables smooth [ClampingScrollPhysics] and adds mouse-drag scrolling
/// so users can click-drag to scroll just like touch or trackpad.
class DesktopSmoothScrollBehavior extends MaterialScrollBehavior {
  const DesktopSmoothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// A [ScrollActivity] that drives high-performance, buttery-smooth scrolling
/// across physical mouse wheel events using frame-rate-independent exponential decay.
///
/// Unlike [DrivenScrollActivity], which cancels and restarts an easing curve
/// on every discrete wheel notch (causing stutter, zero-velocity hitching,
/// and target loss), this activity maintains a single running [Ticker].
/// Consecutive wheel notches continuously accumulate into [_targetPixels],
/// allowing natural acceleration and liquid deceleration without interruptions.
class SmoothScrollActivity extends ScrollActivity {
  SmoothScrollActivity(
    super.delegate, {
    required TickerProvider vsync,
    required double initialTarget,
    this.smoothingRate = 22.0,
  }) : _targetPixels = initialTarget {
    _ticker = vsync.createTicker(_onTick);
    _ticker.start();
  }

  final double smoothingRate;
  late final Ticker _ticker;
  double _targetPixels;
  Duration _lastElapsed = Duration.zero;

  void addDelta(double delta, double min, double max) {
    final double current = (delegate as ScrollPosition).pixels;
    // If user reverses scroll direction, snap target immediately to current offset
    // so direction changes feel instant and responsive rather than fighting inertia.
    if ((delta > 0 && _targetPixels < current) ||
        (delta < 0 && _targetPixels > current)) {
      _targetPixels = current;
    }
    _targetPixels = (_targetPixels + delta).clamp(min, max);
  }

  void _onTick(Duration elapsed) {
    final double dt = _lastElapsed == Duration.zero
        ? 1.0 / 60.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    // Guard against anomalous delta-time spikes (e.g. window blur, debugger pause)
    if (dt <= 0 || dt > 0.1) return;

    final pos = delegate as ScrollPosition;
    final double current = pos.pixels;

    // Keep target clamped in case extents updated dynamically during content layout
    _targetPixels = _targetPixels.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    final double diff = _targetPixels - current;

    if (diff.abs() < 0.5) {
      applyMoveTo(_targetPixels);
      delegate.goIdle();
      return;
    }

    // Frame-rate independent exponential smoothing
    final double factor = 1.0 - math.exp(-smoothingRate * dt);
    final double nextPixels = current + diff * factor;
    if (!applyMoveTo(nextPixels)) {
      delegate.goIdle();
    }
  }

  bool applyMoveTo(double value) {
    return delegate.setPixels(value).abs() < 0.001;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  bool get isScrolling => true;

  @override
  bool get shouldIgnorePointer => false;

  @override
  double get velocity => 0.0;
}

/// A [ScrollPosition] that intercepts [pointerScroll] to provide continuous,
/// interpolated mouse wheel scrolling while strictly respecting desktop conventions:
/// - Holding `Shift` on vertical scroll views drops vertical wheel deltas so
///   horizontal child scrollables (e.g. `CardRail`) can scroll horizontally.
/// - Rapid wheel notches accumulate into a unified physics ticker instead of
///   stepped single-frame jumps.
class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels = 0.0,
    super.keepScrollOffset = true,
    super.debugLabel,
    this.smoothingRate = 22.0,
    this.scrollSpeed = 1.0,
  });

  double smoothingRate;
  double scrollSpeed;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      goBallistic(0.0);
      return;
    }

    // Check if Shift is held: desktop standard uses Shift + Wheel for horizontal scrolling.
    final bool isShift = HardwareKeyboard.instance.isShiftPressed;
    final bool isVertical = axisDirection == AxisDirection.down ||
        axisDirection == AxisDirection.up;
    if (isShift && isVertical) {
      // Suppress vertical movement when Shift is pressed.
      return;
    }

    final double min = minScrollExtent;
    final double max = maxScrollExtent;
    if (max <= min) return;

    if (activity is SmoothScrollActivity) {
      (activity as SmoothScrollActivity).addDelta(
        delta * scrollSpeed,
        min,
        max,
      );
    } else {
      final double target = (pixels + delta * scrollSpeed).clamp(min, max);
      if ((target - pixels).abs() < 0.5) return;
      beginActivity(
        SmoothScrollActivity(
          this,
          vsync: context.vsync,
          initialTarget: target,
          smoothingRate: smoothingRate,
        ),
      );
    }
  }
}

/// A [ScrollController] that creates [SmoothScrollPosition] instances and
/// transparently proxies position events to an optional client [ScrollController].
class SmoothScrollController extends ScrollController {
  ScrollController? clientController;
  double smoothingRate;
  double scrollSpeed;

  SmoothScrollController({
    this.clientController,
    this.smoothingRate = 22.0,
    this.scrollSpeed = 1.0,
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
      smoothingRate: smoothingRate,
      scrollSpeed: scrollSpeed,
    );
  }

  @override
  void attach(ScrollPosition position) {
    if (clientController != null &&
        !clientController!.positions.contains(position)) {
      clientController!.attach(position);
    }
    super.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    if (clientController != null &&
        clientController!.positions.contains(position)) {
      clientController!.detach(position);
    }
    super.detach(position);
  }
}

/// Signature for the builder callback used by [WispSmoothScroll].
typedef WispSmoothScrollBuilder = Widget Function(
  BuildContext context,
  ScrollController controller,
  ScrollPhysics physics,
);

/// A lightweight, zero-dependency smooth scroll wrapper for Flutter desktop & web.
///
/// Solves the stepped/ratchet feel of physical mouse wheels by intercepting
/// [ScrollPosition.pointerScroll] and replacing instant single-frame jumps
/// with a continuous exponential smoothing [Ticker].
class WispSmoothScroll extends StatefulWidget {
  final ScrollController? controller;
  final WispSmoothScrollBuilder builder;
  final Axis scrollDirection;
  final double scrollSpeed;
  final double smoothingRate;

  const WispSmoothScroll({
    super.key,
    this.controller,
    required this.builder,
    this.scrollDirection = Axis.vertical,
    this.scrollSpeed = 1.0,
    this.smoothingRate = 22.0,
  });

  @override
  State<WispSmoothScroll> createState() => _WispSmoothScrollState();
}

class _WispSmoothScrollState extends State<WispSmoothScroll> {
  late SmoothScrollController _smoothController;

  @override
  void initState() {
    super.initState();
    _smoothController = SmoothScrollController(
      clientController: widget.controller,
      scrollSpeed: widget.scrollSpeed,
      smoothingRate: widget.smoothingRate,
    );
  }

  @override
  void didUpdateWidget(WispSmoothScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    _smoothController.scrollSpeed = widget.scrollSpeed;
    _smoothController.smoothingRate = widget.smoothingRate;

    // Update active positions if they exist
    for (final pos in _smoothController.positions) {
      if (pos is SmoothScrollPosition) {
        pos.scrollSpeed = widget.scrollSpeed;
        pos.smoothingRate = widget.smoothingRate;
      }
    }

    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller != null) {
        for (final pos in _smoothController.positions) {
          if (oldWidget.controller!.positions.contains(pos)) {
            oldWidget.controller!.detach(pos);
          }
        }
      }
      _smoothController.clientController = widget.controller;
      if (widget.controller != null) {
        for (final pos in _smoothController.positions) {
          if (!widget.controller!.positions.contains(pos)) {
            widget.controller!.attach(pos);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _smoothController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const physics = ClampingScrollPhysics();
    return widget.builder(context, _smoothController, physics);
  }
}

/// Drop-in replacement for [CustomScrollView] with silky smooth desktop scrolling.
class WispCustomScrollView extends StatelessWidget {
  final ScrollController? controller;
  final List<Widget> slivers;
  final Axis scrollDirection;
  final bool reverse;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final Clip clipBehavior;
  final double scrollSpeed;
  final double smoothingRate;

  const WispCustomScrollView({
    super.key,
    this.controller,
    this.slivers = const <Widget>[],
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.shrinkWrap = false,
    this.physics,
    this.clipBehavior = Clip.hardEdge,
    this.scrollSpeed = 1.0,
    this.smoothingRate = 22.0,
  });

  @override
  Widget build(BuildContext context) {
    return WispSmoothScroll(
      controller: controller,
      scrollDirection: scrollDirection,
      scrollSpeed: scrollSpeed,
      smoothingRate: smoothingRate,
      builder: (context, ctrl, phys) => CustomScrollView(
        controller: ctrl,
        scrollDirection: scrollDirection,
        reverse: reverse,
        shrinkWrap: shrinkWrap,
        physics: physics ?? phys,
        clipBehavior: clipBehavior,
        slivers: slivers,
      ),
    );
  }
}

/// Drop-in replacement for [ListView] with silky smooth desktop scrolling.
class WispListView extends StatelessWidget {
  final ScrollController? controller;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final Axis scrollDirection;
  final double scrollSpeed;
  final double smoothingRate;

  const WispListView({
    super.key,
    this.controller,
    this.children = const <Widget>[],
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.scrollDirection = Axis.vertical,
    this.scrollSpeed = 1.0,
    this.smoothingRate = 22.0,
  });

  @override
  Widget build(BuildContext context) {
    return WispSmoothScroll(
      controller: controller,
      scrollDirection: scrollDirection,
      scrollSpeed: scrollSpeed,
      smoothingRate: smoothingRate,
      builder: (context, ctrl, phys) => ListView(
        controller: ctrl,
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: physics ?? phys,
        scrollDirection: scrollDirection,
        children: children,
      ),
    );
  }
}
