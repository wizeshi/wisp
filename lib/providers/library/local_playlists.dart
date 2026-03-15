/// Local/mixed playlist store
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_playlist.dart';
import '../../models/metadata_models.dart';
import '../../services/folder_thumbnail_store.dart';

class LocalPlaylistState extends ChangeNotifier {
  static const String _prefsKey = 'local_playlists';
  static const String _prefsTrashKey = 'local_playlists_trash';
  static const String _prefsHiddenKey = 'local_hidden_provider_playlists';

  final List<LocalPlaylist> _playlists = [];
  final List<LocalPlaylist> _trashed = [];
  final Set<String> _hiddenProviderPlaylistIds = {};
  LocalPlaylist? _lastDeleted;
  bool _initialized = false;

  LocalPlaylistState() {
    _loadPrefs();
  }

  List<LocalPlaylist> get playlists => List.unmodifiable(_playlists);
  Set<String> get hiddenProviderPlaylistIds =>
      Set.unmodifiable(_hiddenProviderPlaylistIds);

  List<GenericPlaylist> get genericPlaylists =>
      _playlists.map(_toGenericPlaylist).toList();

  bool isLocalPlaylistId(String id) => _playlists.any((p) => p.id == id);

  LocalPlaylist? getById(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  GenericPlaylist? getGenericPlaylist(String id) {
    final playlist = getById(id);
    if (playlist == null) return null;
    return _toGenericPlaylist(playlist);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = json.decode(raw) as List;
      _playlists
        ..clear()
        ..addAll(
          list.map((e) => LocalPlaylist.fromJson(e as Map<String, dynamic>)),
        );
    }
    final trashRaw = prefs.getString(_prefsTrashKey);
    if (trashRaw != null) {
      final list = json.decode(trashRaw) as List;
      _trashed
        ..clear()
        ..addAll(
          list.map((e) => LocalPlaylist.fromJson(e as Map<String, dynamic>)),
        );
    }
    final hiddenRaw = prefs.getString(_prefsHiddenKey);
    if (hiddenRaw != null) {
      final list = json.decode(hiddenRaw) as List;
      _hiddenProviderPlaylistIds
        ..clear()
        ..addAll(list.map((e) => e.toString()));
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    if (!_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      json.encode(_playlists.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(
      _prefsTrashKey,
      json.encode(_trashed.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(
      _prefsHiddenKey,
      json.encode(_hiddenProviderPlaylistIds.toList()),
    );
  }

  GenericPlaylist _toGenericPlaylist(LocalPlaylist playlist) {
    final durationSecs = playlist.tracks.fold<int>(
      0,
      (sum, item) => sum + item.durationSecs,
    );
    final thumbnailUrl = playlist.tracks.isNotEmpty
        ? playlist.tracks.first.thumbnailUrl
        : '';
    return GenericPlaylist(
      id: playlist.id,
      source: playlist.linkedSource ?? SongSource.local,
      title: playlist.title,
      thumbnailUrl: playlist.thumbnailPath ?? thumbnailUrl,
      author: GenericSimpleUser(
        id: playlist.authorName.toLowerCase().replaceAll(' ', '_'),
        source: playlist.linkedSource ?? SongSource.local,
        displayName: playlist.authorName,
      ),
      songs: playlist.tracks,
      durationSecs: durationSecs,
      total: playlist.tracks.length,
      hasMore: false,
    );
  }

  Future<LocalPlaylist> createPlaylist({
    required String title,
    String authorName = 'You',
    File? thumbnailFile,
  }) async {
    final now = DateTime.now();
    final id = 'local_${now.millisecondsSinceEpoch}';
    String? thumbnailPath;
    if (thumbnailFile != null) {
      thumbnailPath = await FolderThumbnailStore.instance.saveThumbnail(
        thumbnailFile,
        preferredName: id,
      );
    }
    final playlist = LocalPlaylist(
      id: id,
      title: title,
      authorName: authorName,
      tracks: const [],
      createdAt: now,
      updatedAt: now,
      thumbnailPath: thumbnailPath,
    );
    _playlists.add(playlist);
    await _savePrefs();
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String title) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final updated = _playlists[index].copyWith(
      title: title,
      updatedAt: DateTime.now(),
    );
    _playlists[index] = updated;
    await _savePrefs();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final playlist = _playlists[index];
    if (playlist.linkedId != null && playlist.linkedId!.isNotEmpty) {
      _hiddenProviderPlaylistIds.add(playlist.linkedId!);
    }
    // Soft-delete: move to trash so it can be restored.
    _lastDeleted = playlist;
    _trashed.add(playlist);
    _playlists.removeAt(index);
    await _savePrefs();
    notifyListeners();
  }

  /// Permanently delete a playlist that is currently in the trash.
  Future<void> permanentlyDeletePlaylist(String id) async {
    final index = _trashed.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final playlist = _trashed[index];
    await FolderThumbnailStore.instance.deleteThumbnail(playlist.thumbnailPath);
    _trashed.removeAt(index);
    await _savePrefs();
    notifyListeners();
  }

  /// Restore a trashed playlist back into the active playlists.
  Future<void> restorePlaylist(String id) async {
    final index = _trashed.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final playlist = _trashed.removeAt(index);
    // If it was linked to a provider, make sure it's not hidden anymore.
    if (playlist.linkedId != null && playlist.linkedId!.isNotEmpty) {
      _hiddenProviderPlaylistIds.remove(playlist.linkedId!);
    }
    _playlists.add(playlist);
    // If the restored playlist was the last deleted, clear the marker.
    if (_lastDeleted?.id == id) _lastDeleted = null;
    await _savePrefs();
    notifyListeners();
  }

  /// Undo the most recent delete operation (if available).
  Future<void> undoLastDelete() async {
    final playlist = _lastDeleted;
    if (playlist == null) return;
    final index = _trashed.indexWhere((p) => p.id == playlist.id);
    if (index < 0) {
      _lastDeleted = null;
      return;
    }
    _trashed.removeAt(index);
    if (playlist.linkedId != null && playlist.linkedId!.isNotEmpty) {
      _hiddenProviderPlaylistIds.remove(playlist.linkedId!);
    }
    _playlists.add(playlist);
    _lastDeleted = null;
    await _savePrefs();
    notifyListeners();
  }

  /// Un-hide a provider playlist id that was previously hidden when deleting.
  /// Call this with the provider's playlist id (e.g. a Spotify playlist id).
  Future<void> unhideProviderPlaylist(String providerId) async {
    if (providerId.isEmpty) return;
    final removed = _hiddenProviderPlaylistIds.remove(providerId);
    if (!removed) return;
    await _savePrefs();
    notifyListeners();
  }

  List<LocalPlaylist> get trashedPlaylists => List.unmodifiable(_trashed);

  Future<LocalPlaylist> ensureLinkedFromProvider(GenericPlaylist playlist) async {
    final existing = getById(playlist.id);
    if (existing != null) return existing;
    _hiddenProviderPlaylistIds.remove(playlist.id);
    final now = DateTime.now();
    final local = LocalPlaylist(
      id: playlist.id,
      title: playlist.title,
      authorName: playlist.author.displayName,
      tracks: List<PlaylistItem>.from(playlist.songs ?? const []),
      createdAt: now,
      updatedAt: now,
      linkedId: playlist.id,
      linkedSource: playlist.source,
    );
    _playlists.add(local);
    await _savePrefs();
    notifyListeners();
    return local;
  }

  Future<void> linkToProvider({
    required String id,
    required SongSource provider,
    required String providerId,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _playlists[index] = _playlists[index].copyWith(
      linkedId: providerId,
      linkedSource: provider,
      updatedAt: DateTime.now(),
    );
    await _savePrefs();
    notifyListeners();
  }

  Future<void> detachFromProvider(String id) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _playlists[index] = _playlists[index].copyWith(
      linkedId: null,
      linkedSource: null,
      updatedAt: DateTime.now(),
    );
    await _savePrefs();
    notifyListeners();
  }

  Future<void> updateThumbnail(String id, File imageFile) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final playlist = _playlists[index];
    final savedPath = await FolderThumbnailStore.instance.saveThumbnail(
      imageFile,
      preferredName: 'playlist_${playlist.id}',
    );
    if (savedPath == null) return;
    if (playlist.thumbnailPath != null && playlist.thumbnailPath!.isNotEmpty) {
      await FolderThumbnailStore.instance.deleteThumbnail(playlist.thumbnailPath);
    }
    _playlists[index] = playlist.copyWith(
      thumbnailPath: savedPath,
      updatedAt: DateTime.now(),
    );
    await _savePrefs();
    notifyListeners();
  }

  Future<void> addTrackFromSong(String id, GenericSong song) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final playlist = _playlists[index];
    final now = DateTime.now();
    final trackNumber = playlist.tracks.length + 1;
    final item = PlaylistItem(
      id: song.id,
      source: song.source,
      title: song.title,
      artists: song.artists,
      thumbnailUrl: song.thumbnailUrl,
      explicit: song.explicit,
      album: song.album,
      durationSecs: song.durationSecs,
      addedAt: now,
      trackNumber: trackNumber,
    );
    final updatedTracks = [...playlist.tracks, item];
    _playlists[index] = playlist.copyWith(
      tracks: updatedTracks,
      updatedAt: now,
    );
    await _savePrefs();
    notifyListeners();
  }

  Future<void> syncFromProvider({
    required String id,
    required List<PlaylistItem> providerTracks,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final playlist = _playlists[index];
    final existingKeys = playlist.tracks
        .map((item) => '${item.source.name}:${item.id}')
        .toSet();
    final newTracks = <PlaylistItem>[];
    for (final item in providerTracks) {
      final key = '${item.source.name}:${item.id}';
      if (!existingKeys.contains(key)) {
        newTracks.add(item);
      }
    }
    if (newTracks.isEmpty) return;
    final updatedTracks = [...playlist.tracks, ...newTracks];
    _playlists[index] = playlist.copyWith(
      tracks: updatedTracks,
      updatedAt: DateTime.now(),
    );
    await _savePrefs();
    notifyListeners();
  }
}