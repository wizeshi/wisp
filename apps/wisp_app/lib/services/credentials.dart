/// Secure credential and token storage service
/// Handles Spotify Client ID/Secret and OAuth tokens using FlutterSecureStorage
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SpotifyCredentials {
  final String clientId;
  final String clientSecret;

  SpotifyCredentials({
    required this.clientId,
    required this.clientSecret,
  });

  Map<String, String> toJson() => {
        'client_id': clientId,
        'client_secret': clientSecret,
      };

  factory SpotifyCredentials.fromJson(Map<String, dynamic> json) {
    return SpotifyCredentials(
      clientId: json['client_id'] as String,
      clientSecret: json['client_secret'] as String,
    );
  }
}

class SpotifyToken {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  SpotifyToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  bool get isValid => !isExpired && accessToken.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.millisecondsSinceEpoch,
      };

  factory SpotifyToken.fromJson(Map<String, dynamic> json) {
    return SpotifyToken(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        json['expires_at'] as int,
      ),
    );
  }
}

class CredentialsService {
  static const _storage = FlutterSecureStorage();
  
  // Storage keys
  static const _keySpotifyCredentials = 'spotify_credentials';
  static const _keySpotifyToken = 'spotify_token';
  static const _keySpotifyLyricsCookie = 'spotify_lyrics_cookie';
  static const _keySpotifyCookies = 'spotify_cookies';

  /// Save Spotify Client ID and Secret
  Future<void> saveSpotifyCredentials(SpotifyCredentials credentials) async {
    await _storage.write(
      key: _keySpotifyCredentials,
      value: jsonEncode(credentials.toJson()),
    );
  }

  /// Retrieve Spotify Client ID and Secret
  Future<SpotifyCredentials?> getSpotifyCredentials() async {
    final json = await _storage.read(key: _keySpotifyCredentials);
    if (json == null || json.isEmpty) return null;
    
    try {
      return SpotifyCredentials.fromJson(jsonDecode(json));
    } catch (e) {
      return null;
    }
  }

  /// Check if Spotify credentials are configured
  Future<bool> hasSpotifyCredentials() async {
    final credentials = await getSpotifyCredentials();
    return credentials != null &&
        credentials.clientId.isNotEmpty &&
        credentials.clientSecret.isNotEmpty;
  }

  /// Save Spotify OAuth token
  Future<void> saveSpotifyToken(SpotifyToken token) async {
    await _storage.write(
      key: _keySpotifyToken,
      value: jsonEncode(token.toJson()),
    );
  }

  /// Retrieve Spotify OAuth token
  Future<SpotifyToken?> getSpotifyToken() async {
    final json = await _storage.read(key: _keySpotifyToken);
    if (json == null || json.isEmpty) return null;
    
    try {
      return SpotifyToken.fromJson(jsonDecode(json));
    } catch (e) {
      return null;
    }
  }

  /// Check if a valid (non-expired) token exists
  Future<bool> hasValidSpotifyToken() async {
    final token = await getSpotifyToken();
    return token?.isValid ?? false;
  }

  /// Clear Spotify OAuth token (logout)
  Future<void> clearSpotifyToken() async {
    await _storage.delete(key: _keySpotifyToken);
  }

  /// Save Spotify lyrics cookie (sp_dc)
  Future<void> saveSpotifyLyricsCookie(String cookie) async {
    await _storage.write(key: _keySpotifyLyricsCookie, value: cookie.trim());
  }

  /// Save all Spotify cookies as a JSON map of name -> value
  Future<void> saveSpotifyCookies(Map<String, String> cookies) async {
    await _storage.write(key: _keySpotifyCookies, value: jsonEncode(cookies));
  }

  /// Retrieve Spotify lyrics cookie (sp_dc)
  Future<String?> getSpotifyLyricsCookie() async {
    final value = await _storage.read(key: _keySpotifyLyricsCookie);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Retrieve all saved Spotify cookies
  Future<Map<String, String>?> getSpotifyCookies() async {
    final jsonStr = await _storage.read(key: _keySpotifyCookies);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final Map<String, dynamic> parsed = jsonDecode(jsonStr);
      return parsed.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      return null;
    }
  }

  /// Check if Spotify lyrics cookie exists
  Future<bool> hasSpotifyLyricsCookie() async {
    final cookie = await getSpotifyLyricsCookie();
    return cookie != null && cookie.isNotEmpty;
  }

  /// Check if any Spotify cookies are saved
  Future<bool> hasSpotifyCookies() async {
    final cookies = await getSpotifyCookies();
    return cookies != null && cookies.isNotEmpty;
  }

  /// Clear Spotify lyrics cookie
  Future<void> clearSpotifyLyricsCookie() async {
    await _storage.delete(key: _keySpotifyLyricsCookie);
  }

  /// Clear saved Spotify cookies
  Future<void> clearSpotifyCookies() async {
    await _storage.delete(key: _keySpotifyCookies);
  }

  /// Clear all Spotify data (credentials + token)
  Future<void> clearAllSpotifyData() async {
    await _storage.delete(key: _keySpotifyCredentials);
    await _storage.delete(key: _keySpotifyToken);
    await _storage.delete(key: _keySpotifyLyricsCookie);
    await _storage.delete(key: _keySpotifyCookies);
  }
}
