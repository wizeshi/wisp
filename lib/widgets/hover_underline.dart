/// Hover underline helper for clickable text
library;

import 'package:flutter/material.dart';

class HoverUnderline extends StatefulWidget {
  final Widget Function(bool isHovering) builder;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final MouseCursor cursor;

  const HoverUnderline({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapDown,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<HoverUnderline> createState() => _HoverUnderlineState();
}

class _HoverUnderlineState extends State<HoverUnderline> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: widget.builder(_isHovering),
      ),
    );
  }
}
