import 'package:flutter/foundation.dart';

import '../../models/metadata_models.dart';

class LibraryState extends ChangeNotifier {
  List<GenericPlaylist> _playlists = [];
  List<GenericAlbum> _albums = [];
  List<GenericSimpleArtist> _artists = [];

  List<GenericPlaylist> get playlists => _playlists;
  List<GenericAlbum> get albums => _albums;
  List<GenericSimpleArtist> get artists => _artists;

  void setLibrary({
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
  }) {
    _playlists = playlists;
    _albums = albums;
    _artists = artists;
    notifyListeners();
  }

  void clear() {
    _playlists = [];
    _albums = [];
    _artists = [];
    notifyListeners();
  }
}
