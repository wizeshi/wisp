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
    this.duration = const Duration(milliseconds: 250),
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
      setState(() {
        _items.removeAt(0);
      });
      listState.removeItem(
        0,
        (context, animation) =>
            _buildAnimatedItem(removedLine, animation, isRemoving: true),
        duration: widget.duration,
      );

      Future.delayed(widget.duration, () {
        if (!mounted || token != _updateToken) return;
        final insertIndex = _items.length;
        final newLine = newLines.last;
        setState(() {
          for (var i = 0; i < _items.length; i++) {
            _items[i] = newLines[i];
          }
          _items.insert(insertIndex, newLine);
        });
        _listKey.currentState?.insertItem(
          insertIndex,
          duration: widget.duration,
        );
      });
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
    final anim = isRemoving ? ReverseAnimation(animation) : animation;
    final tween = isRemoving
        ? Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.2))
        : Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero);

    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: tween.animate(anim),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        return _buildAnimatedItem(_items[index], animation, isRemoving: false);
      },
    );
  }
}
