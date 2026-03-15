/// Playlist folder state + sorting preferences
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/library_folder.dart';
import '../../models/metadata_models.dart';
import '../../services/folder_thumbnail_store.dart';
import '../../utils/liked_songs.dart';

enum LibrarySortMode { original, recentlyPlayed, custom }

class LibraryFolderGroup {
  final PlaylistFolder folder;
  final List<GenericPlaylist> playlists;

  const LibraryFolderGroup({required this.folder, required this.playlists});
}

class LibraryPlaylistGroups {
  final List<LibraryFolderGroup> folders;
  final List<GenericPlaylist> unassigned;

  const LibraryPlaylistGroups({
    required this.folders,
    required this.unassigned,
  });
}

class LibraryFolderState extends ChangeNotifier {
  static const String _prefsFolders = 'library_folders';
  static const String _prefsAssignments = 'library_folder_assignments';
  static const String _prefsPlaylistOrder = 'library_custom_playlist_order';
  static const String _prefsFolderOrder = 'library_custom_folder_order';
  static const String _prefsLastPlayed = 'library_playlist_last_played';
  static const String _prefsSortMode = 'library_sort_mode';
  static const String _prefsCollapsedFolders = 'library_collapsed_folders';

  final List<PlaylistFolder> _folders = [];
  final Map<String, String?> _playlistFolderIds = {};
  final List<String> _customPlaylistOrder = [];
  final List<String> _customFolderOrder = [];
  final Map<String, DateTime> _playlistLastPlayed = {};
  final List<String> _originalPlaylistOrder = [];
  final Set<String> _collapsedFolderIds = {};

  LibrarySortMode _sortMode = LibrarySortMode.original;
  bool _initialized = false;

  LibraryFolderState() {
    _loadPrefs();
  }

  List<PlaylistFolder> get folders => List.unmodifiable(_folders);
  LibrarySortMode get sortMode => _sortMode;
  bool isFolderCollapsed(String folderId) => _collapsedFolderIds.contains(folderId);

  bool get isCustomSort => _sortMode == LibrarySortMode.custom;

  List<GenericPlaylist> sortPlaylists(List<GenericPlaylist> playlists) {
    return _orderPlaylists(playlists);
  }

  List<PlaylistFolder> sortFolders(Map<String, List<GenericPlaylist>> assigned) {
    return _orderFolders(assigned);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final foldersJson = prefs.getString(_prefsFolders);
    if (foldersJson != null) {
      final list = json.decode(foldersJson) as List;
      _folders
        ..clear()
        ..addAll(
          list.map((e) => PlaylistFolder.fromJson(e as Map<String, dynamic>)),
        );
    }

    final assignmentsJson = prefs.getString(_prefsAssignments);
    if (assignmentsJson != null) {
      final map = json.decode(assignmentsJson) as Map<String, dynamic>;
      _playlistFolderIds
        ..clear()
        ..addAll(map.map((key, value) => MapEntry(key, value as String?)));
    }

    final playlistOrderJson = prefs.getString(_prefsPlaylistOrder);
    if (playlistOrderJson != null) {
      final list = json.decode(playlistOrderJson) as List;
      _customPlaylistOrder
        ..clear()
        ..addAll(list.map((e) => e.toString()));
    }

    final folderOrderJson = prefs.getString(_prefsFolderOrder);
    if (folderOrderJson != null) {
      final list = json.decode(folderOrderJson) as List;
      _customFolderOrder
        ..clear()
        ..addAll(list.map((e) => e.toString()));
    }

    final lastPlayedJson = prefs.getString(_prefsLastPlayed);
    if (lastPlayedJson != null) {
      final map = json.decode(lastPlayedJson) as Map<String, dynamic>;
      _playlistLastPlayed
        ..clear()
        ..addAll(
          map.map(
            (key, value) => MapEntry(key, DateTime.parse(value as String)),
          ),
        );
    }

    final collapsedJson = prefs.getString(_prefsCollapsedFolders);
    if (collapsedJson != null) {
      final list = json.decode(collapsedJson) as List;
      _collapsedFolderIds
        ..clear()
        ..addAll(list.map((e) => e.toString()));
    }

    final sortModeRaw = prefs.getString(_prefsSortMode);
    if (sortModeRaw != null) {
      _sortMode = LibrarySortMode.values.firstWhere(
        (e) => e.name == sortModeRaw,
        orElse: () => LibrarySortMode.original,
      );
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    if (!_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsFolders,
      json.encode(_folders.map((f) => f.toJson()).toList()),
    );
    await prefs.setString(
      _prefsAssignments,
      json.encode(_playlistFolderIds),
    );
    await prefs.setString(
      _prefsPlaylistOrder,
      json.encode(_customPlaylistOrder),
    );
    await prefs.setString(
      _prefsFolderOrder,
      json.encode(_customFolderOrder),
    );
    await prefs.setString(
      _prefsLastPlayed,
      json.encode(
        _playlistLastPlayed.map(
          (key, value) => MapEntry(key, value.toIso8601String()),
        ),
      ),
    );
    await prefs.setString(
      _prefsCollapsedFolders,
      json.encode(_collapsedFolderIds.toList()),
    );
    await prefs.setString(_prefsSortMode, _sortMode.name);
  }

  void syncPlaylists(List<GenericPlaylist> playlists) {
    _originalPlaylistOrder
      ..clear()
      ..addAll(
        playlists
            .where((p) => !isLikedSongsPlaylistId(p.id))
            .map((p) => p.id),
      );

    final playlistIds = playlists
      .where((p) => !isLikedSongsPlaylistId(p.id))
      .map((p) => p.id)
      .toSet();

    _customPlaylistOrder.removeWhere((id) => !playlistIds.contains(id));
    for (final id in _originalPlaylistOrder) {
      if (!_customPlaylistOrder.contains(id)) {
        _customPlaylistOrder.add(id);
      }
    }

    _playlistFolderIds.removeWhere((key, value) => !playlistIds.contains(key));
    _playlistLastPlayed.removeWhere((key, value) => !playlistIds.contains(key));

    notifyListeners();
    _savePrefs();
  }

  PlaylistFolder? getFolderById(String folderId) {
    try {
      return _folders.firstWhere((folder) => folder.id == folderId);
    } catch (_) {
      return null;
    }
  }

  PlaylistFolder? folderForPlaylist(String playlistId) {
    final folderId = _playlistFolderIds[playlistId];
    if (folderId == null) return null;
    return getFolderById(folderId);
  }

  String? folderIdForPlaylist(String playlistId) =>
      _playlistFolderIds[playlistId];

  DateTime? lastPlayedForPlaylist(String playlistId) =>
      _playlistLastPlayed[playlistId];

  Future<PlaylistFolder> createFolder({
    required String title,
    File? thumbnailFile,
  }) async {
    final id = _generateId();
    String? thumbnailPath;
    if (thumbnailFile != null) {
      thumbnailPath = await FolderThumbnailStore.instance.saveThumbnail(
        thumbnailFile,
        preferredName: id,
      );
    }

    final folder = PlaylistFolder(
      id: id,
      title: title.trim(),
      thumbnailPath: thumbnailPath,
      createdAt: DateTime.now(),
    );

    _folders.add(folder);
    if (!_customFolderOrder.contains(id)) {
      _customFolderOrder.add(id);
    }

    notifyListeners();
    await _savePrefs();
    return folder;
  }

  Future<void> renameFolder(String folderId, String title) async {
    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    _folders[index] = _folders[index].copyWith(title: title.trim());
    notifyListeners();
    await _savePrefs();
  }

  Future<void> deleteFolder(String folderId) async {
    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    final folder = _folders.removeAt(index);
    _customFolderOrder.remove(folderId);
    _collapsedFolderIds.remove(folderId);

    for (final entry in _playlistFolderIds.entries.toList()) {
      if (entry.value == folderId) {
        _playlistFolderIds[entry.key] = null;
      }
    }

    await FolderThumbnailStore.instance.deleteThumbnail(folder.thumbnailPath);
    notifyListeners();
    await _savePrefs();
  }

  Future<void> changeFolderThumbnail(String folderId, File file) async {
    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    final old = _folders[index];
    final newPath = await FolderThumbnailStore.instance.saveThumbnail(
      file,
      preferredName: folderId,
    );
    await FolderThumbnailStore.instance.deleteThumbnail(old.thumbnailPath);
    _folders[index] = old.copyWith(thumbnailPath: newPath);
    notifyListeners();
    await _savePrefs();
  }

  Future<void> clearFolderThumbnail(String folderId) async {
    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    final old = _folders[index];
    await FolderThumbnailStore.instance.deleteThumbnail(old.thumbnailPath);
    _folders[index] = old.copyWith(thumbnailPath: null);
    notifyListeners();
    await _savePrefs();
  }

  Future<void> assignPlaylistToFolder(
    String playlistId,
    String? folderId,
  ) async {
    if (isLikedSongsPlaylistId(playlistId)) return;
    _playlistFolderIds[playlistId] = folderId;
    notifyListeners();
    await _savePrefs();
  }

  Future<void> batchAssignPlaylistsToFolders(Map<String, String> assignments) async {
    var changed = false;
    for (final entry in assignments.entries) {
      if (isLikedSongsPlaylistId(entry.key)) continue;
      if (_playlistFolderIds[entry.key] != entry.value) {
        _playlistFolderIds[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _savePrefs();
    }
  }

  Future<void> markPlaylistPlayed(String playlistId) async {
    _playlistLastPlayed[playlistId] = DateTime.now();
    notifyListeners();
    await _savePrefs();
  }

  Future<void> setSortMode(LibrarySortMode mode) async {
    if (_sortMode == mode) return;
    _sortMode = mode;
    notifyListeners();
    await _savePrefs();
  }

  Future<void> movePlaylistBefore(String draggedId, String targetId) async {
    if (isLikedSongsPlaylistId(draggedId) || isLikedSongsPlaylistId(targetId)) {
      return;
    }
    if (draggedId == targetId) return;
    _customPlaylistOrder.remove(draggedId);
    final targetIndex = _customPlaylistOrder.indexOf(targetId);
    if (targetIndex >= 0) {
      _customPlaylistOrder.insert(targetIndex, draggedId);
    } else {
      _customPlaylistOrder.add(draggedId);
    }
    notifyListeners();
    await _savePrefs();
  }

  Future<void> moveFolderBefore(String draggedId, String targetId) async {
    if (draggedId == targetId) return;
    _customFolderOrder.remove(draggedId);
    final targetIndex = _customFolderOrder.indexOf(targetId);
    if (targetIndex >= 0) {
      _customFolderOrder.insert(targetIndex, draggedId);
    } else {
      _customFolderOrder.add(draggedId);
    }

    final draggedPlaylists = _customPlaylistOrder
        .where((id) => _playlistFolderIds[id] == draggedId)
        .toList();
    if (draggedPlaylists.isNotEmpty) {
      _customPlaylistOrder.removeWhere(draggedPlaylists.contains);
      final targetPlaylistIndex = _customPlaylistOrder.indexWhere(
        (id) => _playlistFolderIds[id] == targetId,
      );
      final insertIndex = targetPlaylistIndex >= 0
          ? targetPlaylistIndex
          : _customPlaylistOrder.length;
      _customPlaylistOrder.insertAll(insertIndex, draggedPlaylists);
    }
    notifyListeners();
    await _savePrefs();
  }

  Future<void> moveFolderBeforePlaylist(
    String folderId,
    String targetPlaylistId,
  ) async {
    if (isLikedSongsPlaylistId(targetPlaylistId)) return;
    if (_playlistFolderIds[targetPlaylistId] == folderId) return;

    final folderPlaylists = _customPlaylistOrder
        .where((id) => _playlistFolderIds[id] == folderId)
        .toList();
    if (folderPlaylists.isEmpty) return;

    _customPlaylistOrder.removeWhere(folderPlaylists.contains);
    final targetIndex = _customPlaylistOrder.indexOf(targetPlaylistId);
    final insertIndex = targetIndex >= 0
        ? targetIndex
        : _customPlaylistOrder.length;
    _customPlaylistOrder.insertAll(insertIndex, folderPlaylists);
    notifyListeners();
    await _savePrefs();
  }

  /// Import remote folders (e.g. from Spotify). Adds any folders that don't
  /// yet exist locally. Uses the remote id as the local `PlaylistFolder.id`.
  Future<void> importRemoteFolders(List<PlaylistFolder> remoteFolders) async {
    var changed = false;
    for (final folder in remoteFolders) {
      final exists = _folders.any((f) => f.id == folder.id);
      if (!exists) {
        _folders.add(folder);
        if (!_customFolderOrder.contains(folder.id)) {
          _customFolderOrder.add(folder.id);
        }
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _savePrefs();
    }
  }

  Future<void> movePlaylistIntoFolder(
    String playlistId,
    String? folderId,
  ) async {
    if (isLikedSongsPlaylistId(playlistId)) return;
    _playlistFolderIds[playlistId] = folderId;
    if (_sortMode == LibrarySortMode.custom) {
      _movePlaylistToGroupEnd(playlistId, folderId);
    }
    notifyListeners();
    await _savePrefs();
  }

  Future<void> toggleFolderCollapsed(String folderId) async {
    if (_collapsedFolderIds.contains(folderId)) {
      _collapsedFolderIds.remove(folderId);
    } else {
      _collapsedFolderIds.add(folderId);
    }
    notifyListeners();
    await _savePrefs();
  }

  LibraryPlaylistGroups buildPlaylistGroups(List<GenericPlaylist> playlists) {
    final folderMap = <String, PlaylistFolder>{
      for (final folder in _folders) folder.id: folder,
    };
    final assigned = <String, List<GenericPlaylist>>{};
    final unassigned = <GenericPlaylist>[];

    for (final playlist in playlists) {
      if (isLikedSongsPlaylistId(playlist.id)) {
        continue;
      }
      final folderId = _playlistFolderIds[playlist.id];
      if (folderId != null && folderMap.containsKey(folderId)) {
        assigned.putIfAbsent(folderId, () => []).add(playlist);
      } else {
        unassigned.add(playlist);
      }
    }

    final orderedFolders = _orderFolders(assigned);
    final folderGroups = <LibraryFolderGroup>[];
    for (final folder in orderedFolders) {
      final list = assigned[folder.id] ?? [];
      folderGroups.add(
        LibraryFolderGroup(
          folder: folder,
          playlists: _orderPlaylists(list),
        ),
      );
    }

    return LibraryPlaylistGroups(
      folders: folderGroups,
      unassigned: _orderPlaylists(unassigned),
    );
  }

  List<PlaylistFolder> _orderFolders(
    Map<String, List<GenericPlaylist>> assigned,
  ) {
    final folders = List<PlaylistFolder>.from(_folders);
    switch (_sortMode) {
      case LibrarySortMode.original:
        folders.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        return folders;
      case LibrarySortMode.recentlyPlayed:
        folders.sort((a, b) {
          final aTime = _folderLastPlayed(assigned[a.id]);
          final bTime = _folderLastPlayed(assigned[b.id]);
          if (aTime == null && bTime == null) {
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          }
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
        return folders;
      case LibrarySortMode.custom:
        return _orderByCustomList(folders, _customFolderOrder);
    }
  }

  List<GenericPlaylist> _orderPlaylists(List<GenericPlaylist> playlists) {
    switch (_sortMode) {
      case LibrarySortMode.original:
        return _orderByOriginal(playlists);
      case LibrarySortMode.recentlyPlayed:
        return _orderByRecentlyPlayed(playlists);
      case LibrarySortMode.custom:
        return _orderByCustomList(playlists, _customPlaylistOrder);
    }
  }

  List<T> _orderByCustomList<T extends Object>(
    List<T> items,
    List<String> order,
  ) {
    final idFor = (T item) {
      if (item is PlaylistFolder) return item.id;
      if (item is GenericPlaylist) return item.id;
      return '';
    };

    final orderIndex = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      orderIndex[order[i]] = i;
    }

    final sorted = List<T>.from(items);
    sorted.sort((a, b) {
      final aIndex = orderIndex[idFor(a)] ?? 999999;
      final bIndex = orderIndex[idFor(b)] ?? 999999;
      return aIndex.compareTo(bIndex);
    });
    return sorted;
  }

  List<GenericPlaylist> _orderByOriginal(List<GenericPlaylist> playlists) {
    final orderIndex = <String, int>{};
    for (var i = 0; i < _originalPlaylistOrder.length; i++) {
      orderIndex[_originalPlaylistOrder[i]] = i;
    }
    final sorted = List<GenericPlaylist>.from(playlists);
    sorted.sort((a, b) {
      final aIndex = orderIndex[a.id] ?? 999999;
      final bIndex = orderIndex[b.id] ?? 999999;
      return aIndex.compareTo(bIndex);
    });
    return sorted;
  }

  List<GenericPlaylist> _orderByRecentlyPlayed(List<GenericPlaylist> playlists) {
    final orderIndex = <String, int>{};
    for (var i = 0; i < _originalPlaylistOrder.length; i++) {
      orderIndex[_originalPlaylistOrder[i]] = i;
    }

    final sorted = List<GenericPlaylist>.from(playlists);
    sorted.sort((a, b) {
      final aTime = _playlistLastPlayed[a.id];
      final bTime = _playlistLastPlayed[b.id];
      if (aTime == null && bTime == null) {
        final aIndex = orderIndex[a.id] ?? 999999;
        final bIndex = orderIndex[b.id] ?? 999999;
        return aIndex.compareTo(bIndex);
      }
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  DateTime? _folderLastPlayed(List<GenericPlaylist>? playlists) {
    if (playlists == null || playlists.isEmpty) return null;
    DateTime? latest;
    for (final playlist in playlists) {
      final time = _playlistLastPlayed[playlist.id];
      if (time == null) continue;
      if (latest == null || time.isAfter(latest)) {
        latest = time;
      }
    }
    return latest;
  }

  void _movePlaylistToGroupEnd(String playlistId, String? folderId) {
    _customPlaylistOrder.remove(playlistId);
    if (folderId == null) {
      _customPlaylistOrder.add(playlistId);
      return;
    }

    final playlistIdsInFolder = _playlistFolderIds.entries
        .where((entry) => entry.value == folderId)
        .map((e) => e.key)
        .toList();

    if (playlistIdsInFolder.isEmpty) {
      _customPlaylistOrder.add(playlistId);
      return;
    }

    var lastIndex = -1;
    for (final id in playlistIdsInFolder) {
      final idx = _customPlaylistOrder.indexOf(id);
      if (idx > lastIndex) lastIndex = idx;
    }

    if (lastIndex < 0 || lastIndex >= _customPlaylistOrder.length) {
      _customPlaylistOrder.add(playlistId);
    } else {
      _customPlaylistOrder.insert(lastIndex + 1, playlistId);
    }
  }

  String _generateId() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return 'folder_$stamp';
  }
}
