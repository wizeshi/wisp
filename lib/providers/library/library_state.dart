import 'package:flutter/foundation.dart';

import '../../models/metadata_models.dart';

class LibraryState extends ChangeNotifier {
  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericPlaylist> _localPlaylists = [];
  Set<String> _hiddenRemotePlaylistIds = {};
  List<GenericAlbum> _albums = [];
  List<GenericSimpleArtist> _artists = [];
  List<dynamic>? _allOrganized;

  List<GenericPlaylist> get playlists => _mergePlaylists();
  List<GenericAlbum> get albums => _albums;
  List<GenericSimpleArtist> get artists => _artists;
  List<dynamic>? get allOrganized => _allOrganized;

  bool isArtistFollowed(String artistId) {
    return _artists.any((artist) => artist.id == artistId);
  }

  bool isAlbumSaved(String albumId) {
    return _albums.any((album) => album.id == albumId);
  }

  void setLibrary({
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
    List<dynamic>? allOrganized,
  }) {
    _remotePlaylists = playlists;
    _albums = albums;
    _artists = artists;
    _allOrganized = allOrganized;
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

  void addArtist(GenericSimpleArtist artist) {
    if (isArtistFollowed(artist.id)) return;
    _artists = [..._artists, artist];
    notifyListeners();
  }

  void removeArtist(String artistId) {
    final next = _artists.where((artist) => artist.id != artistId).toList();
    if (next.length == _artists.length) return;
    _artists = next;
    notifyListeners();
  }

  void addAlbum(GenericAlbum album) {
    if (isAlbumSaved(album.id)) return;
    _albums = [..._albums, album];
    notifyListeners();
  }

  void removeAlbum(String albumId) {
    final next = _albums.where((album) => album.id != albumId).toList();
    if (next.length == _albums.length) return;
    _albums = next;
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
