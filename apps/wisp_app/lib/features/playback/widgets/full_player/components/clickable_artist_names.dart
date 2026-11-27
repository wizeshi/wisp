// Copyright © 2026 wizeshi

import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';

/// Displays comma-separated clickable artist names (and an optional clickable
/// album suffix) using a single [Text.rich] widget so long lists ellipsize
/// cleanly without overflowing.
class ClickableArtistNames extends StatefulWidget {
  final List<GenericSimpleArtist> artists;
  final TextStyle style;
  final GenericSimpleAlbum? album;
  final String emptyText;
  final int maxLines;
  final bool closeFullPlayerFirst;
  final Future<void> Function()? onBeforeNavigate;
  final TextAlign textAlign;

  const ClickableArtistNames({
    super.key,
    required this.artists,
    required this.style,
    this.album,
    this.emptyText = 'No Artist',
    this.maxLines = 1,
    this.closeFullPlayerFirst = true,
    this.onBeforeNavigate,
    this.textAlign = TextAlign.start,
  });

  @override
  State<ClickableArtistNames> createState() => _ClickableArtistNamesState();
}

class _ClickableArtistNamesState extends State<ClickableArtistNames> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(covariant ClickableArtistNames oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artists != widget.artists ||
        oldWidget.album != widget.album ||
        oldWidget.closeFullPlayerFirst != widget.closeFullPlayerFirst ||
        oldWidget.onBeforeNavigate != widget.onBeforeNavigate) {
      _rebuildRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _rebuildRecognizers() {
    _disposeRecognizers();

    for (final artist in widget.artists) {
      if (artist.id.isNotEmpty) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => unawaited(_navigateToArtist(artist));
        _recognizers.add(recognizer);
      }
    }

    final album = widget.album;
    if (album != null && album.title.isNotEmpty && album.id.isNotEmpty) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(_navigateToAlbum(album));
      _recognizers.add(recognizer);
    }
  }

  Future<void> _prepareNavigation() async {
    if (widget.onBeforeNavigate != null) {
      await widget.onBeforeNavigate!();
    } else if (widget.closeFullPlayerFirst) {
      await AppNavigation.instance.closeFullPlayer();
    }
  }

  Future<void> _navigateToArtist(GenericSimpleArtist artist) async {
    await _prepareNavigation();
    NavigationService.instance.pushArtist(
      id: artist.id,
      source: artist.source,
    );
  }

  Future<void> _navigateToAlbum(GenericSimpleAlbum album) async {
    await _prepareNavigation();
    NavigationService.instance.pushList(
      id: album.id,
      type: 'album',
      source: album.source,
    );
  }

  @override
  Widget build(BuildContext context) {
    final artists = widget.artists;
    final album = widget.album;
    final hasAlbum = album != null && album.title.isNotEmpty;

    if (artists.isEmpty && !hasAlbum) {
      return Text(
        widget.emptyText,
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: widget.textAlign,
        style: widget.style,
      );
    }

    final spans = <InlineSpan>[];
    var recognizerIndex = 0;

    if (artists.isEmpty) {
      spans.add(TextSpan(text: widget.emptyText, style: widget.style));
    } else {
      for (var i = 0; i < artists.length; i++) {
        final artist = artists[i];
        final isClickable = artist.id.isNotEmpty;
        TapGestureRecognizer? recognizer;
        if (isClickable && recognizerIndex < _recognizers.length) {
          recognizer = _recognizers[recognizerIndex++];
        }

        spans.add(
          TextSpan(
            text: artist.name,
            style: widget.style,
            recognizer: recognizer,
            mouseCursor: isClickable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
          ),
        );

        if (i < artists.length - 1) {
          spans.add(TextSpan(text: ', ', style: widget.style));
        }
      }
    }

    if (hasAlbum) {
      spans.add(TextSpan(text: ' — ', style: widget.style));
      final isAlbumClickable = album.id.isNotEmpty;
      TapGestureRecognizer? albumRecognizer;
      if (isAlbumClickable && recognizerIndex < _recognizers.length) {
        albumRecognizer = _recognizers[recognizerIndex++];
      }
      spans.add(
        TextSpan(
          text: album.title,
          style: widget.style,
          recognizer: albumRecognizer,
          mouseCursor: isAlbumClickable
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
    );
  }
}
