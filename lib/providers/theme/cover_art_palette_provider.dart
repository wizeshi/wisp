import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/metadata_models.dart';

class CoverArtPaletteProvider extends ChangeNotifier {
  ColorScheme? _palette;
  Color? _primaryColor;
  String? _currentTrackId;
  String? _currentImageUrl;
  int _requestToken = 0;

  final Map<String, ColorScheme> _cache = {};

  ColorScheme? get palette => _palette;
  Color? get primaryColor => _primaryColor;
  String? get currentTrackId => _currentTrackId;

  void updateForTrack(GenericSong? track) {
    final nextTrackId = track?.id;
    final nextImageUrl = track?.thumbnailUrl ?? '';
    if (nextTrackId == _currentTrackId && nextImageUrl == _currentImageUrl) {
      return;
    }

    _currentTrackId = nextTrackId;
    _currentImageUrl = nextImageUrl;

    if (nextImageUrl.isEmpty) {
      _applyPalette(null);
      return;
    }

    final cached = _cache[nextImageUrl];
    if (cached != null) {
      _applyPalette(cached);
      return;
    }

    _extractPalette(nextImageUrl);
  }

  Future<void> _extractPalette(String imageUrl) async {
    final requestToken = ++_requestToken;
    ColorScheme? palette;

    try {
      palette = await ColorScheme.fromImageProvider(
        provider: CachedNetworkImageProvider(imageUrl),
      ).catchError((_) => null);
    } catch (_) {
      palette = null;
    }

    if (requestToken != _requestToken) {
      return;
    }

    if (palette != null) {
      _cache[imageUrl] = palette;
    }

    _applyPalette(palette);
  }

  void _applyPalette(ColorScheme? palette) {
    _palette = palette;
    _primaryColor = palette?.primary;
    notifyListeners();
  }
}
