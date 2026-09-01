import 'package:flutter/material.dart';
import '../models/metadata_models.dart';

class AnimatedLyricsPreviewList extends StatefulWidget {
  final List<LyricsLine> lines;
  final TextStyle textStyle;
  final EdgeInsetsGeometry itemPadding;
  final int? maxLines;
  final TextOverflow overflow;
  final Duration duration;
  final String? resetKey;

  const AnimatedLyricsPreviewList({
    super.key,
    required this.lines,
    required this.textStyle,
    this.itemPadding = const EdgeInsets.only(bottom: 6),
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.duration = const Duration(milliseconds: 190),
    this.resetKey,
  });

  @override
  State<AnimatedLyricsPreviewList> createState() =>
      _AnimatedLyricsPreviewListState();
}

class _AnimatedLyricsPreviewListState extends State<AnimatedLyricsPreviewList> {
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  List<LyricsLine> _items = [];
  String? _currentResetKey;
  int _updateToken = 0;

  @override
  void initState() {
    super.initState();
    _currentResetKey = widget.resetKey;
    _items = List<LyricsLine>.from(widget.lines);
  }

  @override
  void didUpdateWidget(covariant AnimatedLyricsPreviewList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != _currentResetKey) {
      setState(() {
        _currentResetKey = widget.resetKey;
        _items = List<LyricsLine>.from(widget.lines);
        _listKey = GlobalKey<AnimatedListState>();
      });
      return;
    }

    _syncLines(widget.lines);
  }

  bool _isSameLine(LyricsLine a, LyricsLine b) {
    return a.startTimeMs == b.startTimeMs && a.content == b.content;
  }

  bool _isShiftForward(List<LyricsLine> oldLines, List<LyricsLine> newLines) {
    if (oldLines.length != newLines.length || oldLines.isEmpty) return false;
    if (oldLines.length == 1) {
      return !_isSameLine(oldLines.first, newLines.first);
    }
    return _isSameLine(oldLines[1], newLines.first);
  }

  void _syncLines(List<LyricsLine> newLines) {
    _updateToken += 1;
    final token = _updateToken;
    if (_items.length == newLines.length && _items.isNotEmpty) {
      var allSame = true;
      for (var i = 0; i < _items.length; i++) {
        if (!_isSameLine(_items[i], newLines[i])) {
          allSame = false;
          break;
        }
      }
      if (allSame) return;
    } else if (_items.isEmpty && newLines.isEmpty) {
      return;
    }

    if (_isShiftForward(_items, newLines)) {
      final listState = _listKey.currentState;
      if (listState == null) {
        setState(() => _items = List<LyricsLine>.from(newLines));
        return;
      }

      final removedLine = _items.first;
      final previousLength = _items.length;
      final newTailLine = newLines.last;

      setState(() {
        _items.removeAt(0);
        for (var i = 0; i < _items.length; i++) {
          _items[i] = newLines[i];
        }
        _items.add(newTailLine);
      });

      listState.removeItem(
        0,
        (context, animation) =>
            _buildAnimatedItem(removedLine, animation, isRemoving: true),
        duration: widget.duration,
      );

      if (!mounted || token != _updateToken) return;
      _listKey.currentState?.insertItem(
        previousLength - 1,
        duration: widget.duration,
      );
      return;
    }

    setState(() {
      _items = List<LyricsLine>.from(newLines);
      _listKey = GlobalKey<AnimatedListState>();
    });
  }

  Widget _buildAnimatedItem(
    LyricsLine line,
    Animation<double> animation, {
    required bool isRemoving,
  }) {
    final progress = isRemoving ? ReverseAnimation(animation) : animation;

    final slideAnimation = isRemoving
        ? Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(0, -0.32),
          ).animate(
            CurvedAnimation(
              parent: progress,
              curve: Curves.easeInOutCubicEmphasized,
            ),
          )
        : Tween<Offset>(begin: const Offset(0, 0.28), end: Offset.zero).animate(
            CurvedAnimation(parent: progress, curve: Curves.easeOutCubic),
          );

    final opacityAnimation = isRemoving
        ? Tween<double>(begin: 1, end: 0).animate(
            CurvedAnimation(parent: progress, curve: Curves.easeInCubic),
          )
        : CurvedAnimation(parent: progress, curve: Curves.easeOutCubic);

    final sizeAnimation = isRemoving
        ? Tween<double>(
            begin: 1,
            end: 0,
          ).animate(CurvedAnimation(parent: progress, curve: Curves.linear))
        : Tween<double>(
            begin: 0,
            end: 1,
          ).animate(CurvedAnimation(parent: progress, curve: Curves.linear));

    return SizeTransition(
      sizeFactor: sizeAnimation,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: opacityAnimation,
        child: SlideTransition(
          position: slideAnimation,
          child: Padding(
            padding: widget.itemPadding,
            child: Text(
              line.content,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
              style: widget.textStyle,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      clipBehavior: Clip.hardEdge,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        return _buildAnimatedItem(_items[index], animation, isRemoving: false);
      },
    );
  }
}
