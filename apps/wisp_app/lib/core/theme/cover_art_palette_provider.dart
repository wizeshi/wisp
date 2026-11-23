// Copyright © 2026 wizeshi

import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/core/utils/cover_art_kmeans.dart';

class CoverArtPaletteProvider extends ChangeNotifier {
  ColorScheme? _darkPalette;
  ColorScheme? _lightPalette;
  Color? _primaryColor;
  String? _currentTrackId;
  String? _currentImageUrl;
  int _requestToken = 0;

  final Map<String, CoverArtPaletteColors> _colorCache = {};
  final Map<String, Future<CoverArtPaletteColors?>> _colorFutureCache = {};
  static const int _maxCacheSize = 64;

  ColorScheme? get palette => _darkPalette;
  ColorScheme? get darkPalette => _darkPalette;
  ColorScheme? get lightPalette => _lightPalette;
  Color? get primaryColor => _primaryColor;
  String? get currentTrackId => _currentTrackId;

  ColorScheme? paletteForBrightness(Brightness brightness) =>
      brightness == Brightness.light ? _lightPalette : _darkPalette;

  void updateForTrack(GenericSong? track) {
    final nextTrackId = track?.id;
    final nextImageUrl = track?.thumbnailUrl ?? '';
    if (nextTrackId == _currentTrackId && nextImageUrl == _currentImageUrl) {
      return;
    }

    _currentTrackId = nextTrackId;
    _currentImageUrl = nextImageUrl;

    if (nextImageUrl.isEmpty) {
      _applyColors(null);
      return;
    }

    final cached = _colorCache[nextImageUrl];
    if (cached != null) {
      _applyColors(cached);
      return;
    }

    _extractPalette(nextImageUrl);
  }

  Future<ColorScheme?> paletteForImageUrl(
    String imageUrl, {
    Brightness brightness = Brightness.dark,
  }) async {
    final colors = await colorsForImageUrl(imageUrl);
    if (colors == null) return null;
    return CoverArtKMeans.buildColorScheme(colors, brightness: brightness);
  }

  Future<CoverArtPaletteColors?> colorsForImageUrl(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Future.value(null);
    }
    final cached = _colorCache[imageUrl];
    if (cached != null) {
      return Future.value(cached);
    }
    final cachedFuture = _colorFutureCache[imageUrl];
    if (cachedFuture != null) {
      return cachedFuture;
    }
    _pruneCache(_colorFutureCache);
    final future = _buildColors(imageUrl);
    _colorFutureCache[imageUrl] = future;
    return future;
  }

  Future<void> _extractPalette(String imageUrl) async {
    final requestToken = ++_requestToken;
    CoverArtPaletteColors? colors;

    try {
      colors = await colorsForImageUrl(imageUrl).catchError((_) => null);
    } catch (_) {
      colors = null;
    }

    if (requestToken != _requestToken) {
      return;
    }

    _applyColors(colors);
  }

  Future<CoverArtPaletteColors?> _buildColors(String imageUrl) async {
    try {
      final provider = _imageProviderForUrl(imageUrl);
      if (provider == null) {
        return null;
      }
      final colors = await CoverArtKMeans.extractColorsFromImageProvider(
        provider: provider,
      );
      if (colors != null) {
        _colorCache[imageUrl] = colors;
        _pruneCache(_colorCache);
      }
      return colors;
    } finally {
      _colorFutureCache.remove(imageUrl);
    }
  }

  ImageProvider? _imageProviderForUrl(String imageUrl) {
    if (imageUrl.isEmpty) {
      return null;
    }
    if (_isLocalImagePath(imageUrl)) {
      final filePath = imageUrl.startsWith('file://')
          ? Uri.parse(imageUrl).toFilePath()
          : imageUrl;
      return FileImage(File(filePath));
    }
    return CachedNetworkImageProvider(imageUrl);
  }

  bool _isLocalImagePath(String path) {
    if (path.startsWith('/') || path.startsWith('file://')) return true;
    return RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path);
  }

  void _pruneCache<T>(Map<String, T> cache) {
    while (cache.length > _maxCacheSize) {
      cache.remove(cache.keys.first);
    }
  }

  void _applyColors(CoverArtPaletteColors? colors) {
    if (colors == null) {
      _darkPalette = null;
      _lightPalette = null;
      _primaryColor = null;
    } else {
      _darkPalette = CoverArtKMeans.buildColorScheme(
        colors,
        brightness: Brightness.dark,
      );
      _lightPalette = CoverArtKMeans.buildColorScheme(
        colors,
        brightness: Brightness.light,
      );
      _primaryColor = _darkPalette?.primary;
    }
    notifyListeners();
  }
}
