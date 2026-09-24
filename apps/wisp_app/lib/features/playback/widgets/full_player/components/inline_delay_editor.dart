// Copyright © 2026 wizeshi

import 'dart:async' show Timer, unawaited;
import 'package:flutter/material.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';

class InlineDelayEditor extends StatefulWidget {
  final LyricsProvider lyricsProvider;
  final String trackId;
  final bool visible;

  const InlineDelayEditor({
    super.key,
    required this.lyricsProvider,
    required this.trackId,
    required this.visible,
  });

  @override
  State<InlineDelayEditor> createState() => _InlineDelayEditorState();
}

class _InlineDelayEditorState extends State<InlineDelayEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final initial = widget.lyricsProvider.getDelaySecondsCached(widget.trackId);
    _controller = TextEditingController(text: initial.toStringAsFixed(2));
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _commit({bool formatText = false}) async {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) return;
    await widget.lyricsProvider.setDelaySeconds(widget.trackId, parsed);
    if (!mounted) return;
    if (formatText) {
      setState(() {
        _controller.text = parsed.toStringAsFixed(2);
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      });
    }
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _debounceTimer?.cancel();
      unawaited(_commit(formatText: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 240),
      opacity: widget.visible ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Delay:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(width: 6),
              IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    maxWidth: 120,
                  ),
                  child: SizedBox(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textAlign: TextAlign.right,
                      onChanged: (_) {
                        _debounceTimer?.cancel();
                        _debounceTimer = Timer(
                          const Duration(milliseconds: 350),
                          () => unawaited(_commit()),
                        );
                      },
                      onSubmitted: (_) => _commit(formatText: true),
                      onEditingComplete: () => _commit(formatText: true),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white10,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

