import 'package:flutter/material.dart';

class SlidingTrackBackground extends StatefulWidget {
  final int transitionToken;
  final String? trackId;
  final int queueIndex;
  final Widget child;
  final Duration duration;

  const SlidingTrackBackground({
    super.key,
    required this.transitionToken,
    required this.trackId,
    required this.queueIndex,
    required this.child,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<SlidingTrackBackground> createState() => _SlidingTrackBackgroundState();
}

class _SlidingTrackBackgroundState extends State<SlidingTrackBackground> {
  int _slideDirection = 1;

  @override
  void didUpdateWidget(covariant SlidingTrackBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queueIndex == widget.queueIndex &&
        oldWidget.transitionToken == widget.transitionToken) {
      return;
    }

    _slideDirection = widget.queueIndex >= oldWidget.queueIndex ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final slideDirection = _slideDirection;

    return AnimatedSwitcher(
      duration: widget.duration,
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
        );
      },
      transitionBuilder: (child, animation) {
        final isOutgoing = animation.status == AnimationStatus.reverse;
        final outgoingTarget =
          slideDirection > 0 ? const Offset(-1, 0) : const Offset(1, 0);
        final incomingStart =
          slideDirection > 0 ? const Offset(1, 0) : const Offset(-1, 0);

        final slide = isOutgoing
          ? Tween<Offset>(begin: Offset.zero, end: outgoingTarget)
            .animate(ReverseAnimation(animation))
          : Tween<Offset>(begin: incomingStart, end: Offset.zero)
            .animate(animation);

        return SlideTransition(
          position: slide,
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          '${widget.transitionToken}-${widget.trackId ?? 'null'}-${widget.queueIndex}',
        ),
        child: widget.child,
      ),
    );
  }
}