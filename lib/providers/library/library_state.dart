import 'package:flutter/foundation.dart';

import '../../models/metadata_models.dart';

class LibraryState extends ChangeNotifier {
  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericPlaylist> _localPlaylists = [];
  Set<String> _hiddenRemotePlaylistIds = {};
  List<GenericAlbum> _albums = [];
  List<GenericSimpleArtist> _artists = [];

  List<GenericPlaylist> get playlists => _mergePlaylists();
  List<GenericAlbum> get albums => _albums;
  List<GenericSimpleArtist> get artists => _artists;

  void setLibrary({
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
  }) {
    _remotePlaylists = playlists;
    _albums = albums;
    _artists = artists;
    notifyListeners();
  }

  void setLocalPlaylists(List<GenericPlaylist> playlists) {
    _localPlaylists = playlists;
    notifyListeners();
  }

  void setHiddenRemotePlaylistIds(Set<String> ids) {
    _hiddenRemotePlaylistIds = ids;
    notifyListeners();
  }

  void clear() {
    _remotePlaylists = [];
    _localPlaylists = [];
    _albums = [];
    _artists = [];
    notifyListeners();
  }

  List<GenericPlaylist> _mergePlaylists() {
    if (_localPlaylists.isEmpty) {
      if (_hiddenRemotePlaylistIds.isEmpty) return _remotePlaylists;
      return _remotePlaylists
          .where((p) => !_hiddenRemotePlaylistIds.contains(p.id))
          .toList();
    }
    final localById = {
      for (final playlist in _localPlaylists) playlist.id: playlist,
    };
    final merged = <GenericPlaylist>[];
    final seen = <String>{};

    for (final playlist in _remotePlaylists) {
      if (_hiddenRemotePlaylistIds.contains(playlist.id)) {
        continue;
      }
      final local = localById[playlist.id];
      merged.add(local ?? playlist);
      seen.add(playlist.id);
    }

    for (final playlist in _localPlaylists) {
      if (!seen.contains(playlist.id)) {
        merged.add(playlist);
      }
    }

    return merged;
  }
}
