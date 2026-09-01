import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/metadata_models.dart';
import '../../utils/cover_art_kmeans.dart';

class CoverArtPaletteProvider extends ChangeNotifier {
  ColorScheme? _palette;
  Color? _primaryColor;
  String? _currentTrackId;
  String? _currentImageUrl;
  int _requestToken = 0;

  final Map<String, ColorScheme> _cache = {};
  final Map<String, Future<ColorScheme?>> _futureCache = {};
  static const int _maxCacheSize = 64;

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

  Future<ColorScheme?> paletteForImageUrl(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Future.value(null);
    }
    final cached = _cache[imageUrl];
    if (cached != null) {
      return Future.value(cached);
    }
    final cachedFuture = _futureCache[imageUrl];
    if (cachedFuture != null) {
      return cachedFuture;
    }
    _pruneCache(_futureCache);
    final future = _buildPalette(imageUrl);
    _futureCache[imageUrl] = future;
    return future;
  }

  Future<void> _extractPalette(String imageUrl) async {
    final requestToken = ++_requestToken;
    ColorScheme? palette;

    try {
      palette = await paletteForImageUrl(imageUrl).catchError((_) => null);
    } catch (_) {
      palette = null;
    }

    if (requestToken != _requestToken) {
      return;
    }

    _applyPalette(palette);
  }

  Future<ColorScheme?> _buildPalette(String imageUrl) async {
    try {
      final provider = _imageProviderForUrl(imageUrl);
      if (provider == null) {
        return null;
      }
      final palette = await CoverArtKMeans.fromImageProvider(
        provider: provider,
      );
      if (palette != null) {
        _cache[imageUrl] = palette;
        _pruneCache(_cache);
      }
      return palette;
    } finally {
      _futureCache.remove(imageUrl);
    }
  }

  ImageProvider? _imageProviderForUrl(String imageUrl) {
    if (imageUrl.isEmpty) {
      return null;
    }
    if (_isLocalImagePath(imageUrl)) {
      final filePath = imageUrl.replaceFirst('file://', '');
      return FileImage(File(filePath));
    }
    return CachedNetworkImageProvider(imageUrl);
  }

  bool _isLocalImagePath(String path) {
    return path.startsWith('/') || path.startsWith('file://');
  }

  void _pruneCache<T>(Map<String, T> cache) {
    while (cache.length > _maxCacheSize) {
      cache.remove(cache.keys.first);
    }
  }

  void _applyPalette(ColorScheme? palette) {
    _palette = palette;
    _primaryColor = palette?.primary;
    notifyListeners();
  }
}
