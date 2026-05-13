import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/services/connect/connect_models.dart';

class PreferencesProvider extends ChangeNotifier {
  static const _keyStyle = 'preferred_style';
  static const _keyAnimatedCanvas = 'animated_canvas_enabled';
  static const _keyAllowWriting = 'allow_writing';
  static const _keyMetadataSpotifyEnabled = 'metadata_spotify_enabled';
  static const _keyMetadataYouTubeEnabled = 'metadata_youtube_enabled';
  static const _keyAudioSpotifyEnabled = 'audio_spotify_enabled';
  static const _keyAudioYouTubeEnabled = 'audio_youtube_enabled';
  static const _keyGaplessPlaybackEnabled = 'gapless_playback_enabled';
  static const _keyCrossfadeEnabled = 'crossfade_enabled';
  static const _keyCrossfadeDurationSeconds = 'crossfade_duration_seconds';
  static const _keyLyricsLrclibEnabled = 'lyrics_lrclib_enabled';
  static const _keyLyricsSpotifyEnabled = 'lyrics_spotify_enabled';
  static const _keyHandoffSecurityLevel = 'handoff_security_level';
  static const _keyTrustedDevices = 'handoff_trusted_devices';

  static const bool _defaultAllowWriting = true;
  static const bool _defaultMetadataSpotifyEnabled = true;
  static const bool _defaultMetadataYouTubeEnabled = true;
  static const bool _defaultAudioSpotifyEnabled = false;
  static const bool _defaultAudioYouTubeEnabled = true;
  static const bool _defaultGaplessPlaybackEnabled = true;
  static const bool _defaultCrossfadeEnabled = false;
  static const double _defaultCrossfadeDurationSeconds = 3.0;
  static const bool _defaultLyricsLrclibEnabled = true;
  static const bool _defaultLyricsSpotifyEnabled = true;
  static const HandoffSecurityLevel _defaultHandoffSecurityLevel =
      HandoffSecurityLevel.keyExchange;

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

  bool _gaplessPlaybackEnabled = _defaultGaplessPlaybackEnabled;
  bool get gaplessPlaybackEnabled => _gaplessPlaybackEnabled;

  bool _crossfadeEnabled = _defaultCrossfadeEnabled;
  bool get crossfadeEnabled => _crossfadeEnabled;

  double _crossfadeDurationSeconds = _defaultCrossfadeDurationSeconds;
  double get crossfadeDurationSeconds => _crossfadeDurationSeconds;

  bool _lyricsLrclibEnabled = _defaultLyricsLrclibEnabled;
  bool get lyricsLrclibEnabled => _lyricsLrclibEnabled;

  bool _lyricsSpotifyEnabled = _defaultLyricsSpotifyEnabled;
  bool get lyricsSpotifyEnabled => _lyricsSpotifyEnabled;

  HandoffSecurityLevel _handoffSecurityLevel = _defaultHandoffSecurityLevel;
  HandoffSecurityLevel get handoffSecurityLevel => _handoffSecurityLevel;

  List<TrustedDevice> _trustedDevices = <TrustedDevice>[];
  List<TrustedDevice> get trustedDevices =>
      List.unmodifiable(_trustedDevices);

  bool get hasMetadataProviderEnabled =>
      _metadataSpotifyEnabled || _metadataYouTubeEnabled;
  bool get hasAudioProviderEnabled => _audioSpotifyEnabled || _audioYouTubeEnabled;
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
      _allowWriting = prefs.getBool(_keyAllowWriting) ?? _defaultAllowWriting;
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
      _gaplessPlaybackEnabled =
          prefs.getBool(_keyGaplessPlaybackEnabled) ??
          _defaultGaplessPlaybackEnabled;
      _crossfadeEnabled =
          prefs.getBool(_keyCrossfadeEnabled) ?? _defaultCrossfadeEnabled;
      _crossfadeDurationSeconds =
          prefs.getDouble(_keyCrossfadeDurationSeconds) ??
          _defaultCrossfadeDurationSeconds;
      _lyricsLrclibEnabled =
          prefs.getBool(_keyLyricsLrclibEnabled) ??
          _defaultLyricsLrclibEnabled;
      _lyricsSpotifyEnabled =
          prefs.getBool(_keyLyricsSpotifyEnabled) ??
          _defaultLyricsSpotifyEnabled;
      _handoffSecurityLevel = HandoffSecurityLevelJson.fromJson(
        prefs.getString(_keyHandoffSecurityLevel),
      );
      _trustedDevices = _decodeTrustedDevices(
        prefs.getString(_keyTrustedDevices),
      );
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

  static Future<bool> isGaplessPlaybackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGaplessPlaybackEnabled) ??
        _defaultGaplessPlaybackEnabled;
  }

  static Future<bool> isCrossfadeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCrossfadeEnabled) ?? _defaultCrossfadeEnabled;
  }

  static Future<double> isCrossfadeDurationSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyCrossfadeDurationSeconds) ??
        _defaultCrossfadeDurationSeconds;
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

  Future<void> setGaplessPlaybackEnabled(bool enabled) async {
    if (enabled == _gaplessPlaybackEnabled) return;
    _gaplessPlaybackEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyGaplessPlaybackEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setCrossfadeEnabled(bool enabled) async {
    if (enabled == _crossfadeEnabled) return;
    _crossfadeEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyCrossfadeEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setCrossfadeDurationSeconds(double seconds) async {
    final normalized = seconds.clamp(1.0, 6.0).toDouble();
    if (normalized == _crossfadeDurationSeconds) return;
    _crossfadeDurationSeconds = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyCrossfadeDurationSeconds, normalized);
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

  Future<void> setHandoffSecurityLevel(
    HandoffSecurityLevel level,
  ) async {
    if (level == _handoffSecurityLevel) return;
    _handoffSecurityLevel = level;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyHandoffSecurityLevel, level.toJson());
    } catch (_) {}
  }

  Future<void> setTrustedDevices(List<TrustedDevice> devices) async {
    _trustedDevices = List<TrustedDevice>.from(devices);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTrustedDevices, _encodeTrustedDevices(devices));
    } catch (_) {}
  }

  Future<void> upsertTrustedDevice(TrustedDevice device) async {
    final nextDevices = <TrustedDevice>[
      for (final existing in _trustedDevices)
        if (existing.id != device.id) existing,
      device,
    ];
    nextDevices.sort(
      (a, b) => b.lastConnectionAt.compareTo(a.lastConnectionAt),
    );
    await setTrustedDevices(nextDevices);
  }

  Future<void> forgetTrustedDevice(String deviceId) async {
    final nextDevices = _trustedDevices
        .where((device) => device.id != deviceId)
        .toList(growable: false);
    await setTrustedDevices(nextDevices);
  }

  Future<void> recordTrustedDeviceConnection({
    required String id,
    required String name,
    required String platform,
  }) async {
    final now = DateTime.now();
    final existing = _trustedDevices.where((device) => device.id == id);
    if (existing.isNotEmpty) {
      await upsertTrustedDevice(
        existing.first.copyWith(
          name: name,
          platform: platform,
          lastConnectionAt: now,
        ),
      );
      return;
    }
    await upsertTrustedDevice(
      TrustedDevice(
        id: id,
        name: name,
        platform: platform,
        trustedAt: now,
        lastConnectionAt: now,
      ),
    );
  }

  String _encodeTrustedDevices(List<TrustedDevice> devices) {
    final jsonList = devices.map((device) => device.toJson()).toList();
    return json.encode(jsonList);
  }

  List<TrustedDevice> _decodeTrustedDevices(String? value) {
    if (value == null || value.isEmpty) {
      return <TrustedDevice>[];
    }
    try {
      final decoded = json.decode(value);
      if (decoded is! List<dynamic>) {
        return <TrustedDevice>[];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TrustedDevice.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <TrustedDevice>[];
    }
  }
}
