import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesProvider extends ChangeNotifier {
  static const _keyStyle = 'preferred_style';
  static const _keyAnimatedCanvas = 'animated_canvas_enabled';
  static const _keyAllowWriting = 'allow_writing';
  static const _keyMetadataSpotifyEnabled = 'metadata_spotify_enabled';
  static const _keyMetadataYouTubeEnabled = 'metadata_youtube_enabled';
  static const _keyAudioSpotifyEnabled = 'audio_spotify_enabled';
  static const _keyAudioYouTubeEnabled = 'audio_youtube_enabled';
  static const _keyLyricsLrclibEnabled = 'lyrics_lrclib_enabled';
  static const _keyLyricsSpotifyEnabled = 'lyrics_spotify_enabled';

  static const bool _defaultAllowWriting = true;
  static const bool _defaultMetadataSpotifyEnabled = true;
  static const bool _defaultMetadataYouTubeEnabled = true;
  static const bool _defaultAudioSpotifyEnabled = false;
  static const bool _defaultAudioYouTubeEnabled = true;
  static const bool _defaultLyricsLrclibEnabled = true;
  static const bool _defaultLyricsSpotifyEnabled = true;

  String _style = 'Spotify';
  String get style => _style;

  bool _animatedCanvasEnabled = false;
  bool get animatedCanvasEnabled => _animatedCanvasEnabled;

  bool _allowWriting = _defaultAllowWriting;
  bool get allowWriting => _allowWriting;

    bool _metadataSpotifyEnabled = _defaultMetadataSpotifyEnabled;
    bool get metadataSpotifyEnabled => _metadataSpotifyEnabled;

    bool _metadataYouTubeEnabled = _defaultMetadataYouTubeEnabled;
    bool get metadataYouTubeEnabled => _metadataYouTubeEnabled;

    bool _audioSpotifyEnabled = _defaultAudioSpotifyEnabled;
    bool get audioSpotifyEnabled => _audioSpotifyEnabled;

    bool _audioYouTubeEnabled = _defaultAudioYouTubeEnabled;
    bool get audioYouTubeEnabled => _audioYouTubeEnabled;

    bool _lyricsLrclibEnabled = _defaultLyricsLrclibEnabled;
    bool get lyricsLrclibEnabled => _lyricsLrclibEnabled;

    bool _lyricsSpotifyEnabled = _defaultLyricsSpotifyEnabled;
    bool get lyricsSpotifyEnabled => _lyricsSpotifyEnabled;

    bool get hasMetadataProviderEnabled =>
      _metadataSpotifyEnabled || _metadataYouTubeEnabled;
    bool get hasAudioProviderEnabled =>
      _audioSpotifyEnabled || _audioYouTubeEnabled;
    bool get hasLyricsProviderEnabled =>
      _lyricsLrclibEnabled || _lyricsSpotifyEnabled;

  PreferencesProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _style = prefs.getString(_keyStyle) ?? _style;
      _animatedCanvasEnabled =
          prefs.getBool(_keyAnimatedCanvas) ?? _animatedCanvasEnabled;
      _allowWriting =
          prefs.getBool(_keyAllowWriting) ?? _defaultAllowWriting;
        _metadataSpotifyEnabled =
          prefs.getBool(_keyMetadataSpotifyEnabled) ??
          _defaultMetadataSpotifyEnabled;
        _metadataYouTubeEnabled =
          prefs.getBool(_keyMetadataYouTubeEnabled) ??
          _defaultMetadataYouTubeEnabled;
        _audioSpotifyEnabled =
          prefs.getBool(_keyAudioSpotifyEnabled) ?? _defaultAudioSpotifyEnabled;
        _audioYouTubeEnabled =
          prefs.getBool(_keyAudioYouTubeEnabled) ?? _defaultAudioYouTubeEnabled;
        _lyricsLrclibEnabled =
          prefs.getBool(_keyLyricsLrclibEnabled) ??
          _defaultLyricsLrclibEnabled;
        _lyricsSpotifyEnabled =
          prefs.getBool(_keyLyricsSpotifyEnabled) ??
          _defaultLyricsSpotifyEnabled;
      notifyListeners();
    } catch (_) {
      // Ignore load errors; keep default
    }
  }

  static Future<bool> isWritingAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAllowWriting) ?? _defaultAllowWriting;
  }

  static Future<bool> isMetadataSpotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMetadataSpotifyEnabled) ??
        _defaultMetadataSpotifyEnabled;
  }

  static Future<bool> isMetadataYouTubeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMetadataYouTubeEnabled) ??
        _defaultMetadataYouTubeEnabled;
  }

  static Future<bool> isAudioSpotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAudioSpotifyEnabled) ?? _defaultAudioSpotifyEnabled;
  }

  static Future<bool> isAudioYouTubeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAudioYouTubeEnabled) ?? _defaultAudioYouTubeEnabled;
  }

  static Future<bool> isLyricsLrclibEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLyricsLrclibEnabled) ??
        _defaultLyricsLrclibEnabled;
  }

  static Future<bool> isLyricsSpotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLyricsSpotifyEnabled) ??
        _defaultLyricsSpotifyEnabled;
  }

  Future<void> setStyle(String style) async {
    if (style == _style) return;
    _style = style;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyStyle, style);
    } catch (_) {
      // Ignore save errors
    }
  }

  Future<void> setAnimatedCanvasEnabled(bool enabled) async {
    if (enabled == _animatedCanvasEnabled) return;
    _animatedCanvasEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAnimatedCanvas, enabled);
    } catch (_) {
      // Ignore save errors
    }
  }

  Future<void> setAllowWriting(bool allowed) async {
    if (allowed == _allowWriting) return;
    _allowWriting = allowed;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAllowWriting, allowed);
    } catch (_) {
      // Ignore save errors
    }
  }

  Future<void> setMetadataSpotifyEnabled(bool enabled) async {
    if (enabled == _metadataSpotifyEnabled) return;
    _metadataSpotifyEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyMetadataSpotifyEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setMetadataYouTubeEnabled(bool enabled) async {
    if (enabled == _metadataYouTubeEnabled) return;
    _metadataYouTubeEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyMetadataYouTubeEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setAudioSpotifyEnabled(bool enabled) async {
    if (enabled == _audioSpotifyEnabled) return;
    _audioSpotifyEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAudioSpotifyEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setAudioYouTubeEnabled(bool enabled) async {
    if (enabled == _audioYouTubeEnabled) return;
    _audioYouTubeEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAudioYouTubeEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setLyricsLrclibEnabled(bool enabled) async {
    if (enabled == _lyricsLrclibEnabled) return;
    _lyricsLrclibEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLyricsLrclibEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setLyricsSpotifyEnabled(bool enabled) async {
    if (enabled == _lyricsSpotifyEnabled) return;
    _lyricsSpotifyEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLyricsSpotifyEnabled, enabled);
    } catch (_) {}
  }
}
