import 'package:wisp_innertubex_manager/src/innertubex_backend.dart';
import 'package:wisp_innertubex_manager/src/models/innertubex_models.dart';

class WispInnerTubeXMetadataExtractor {
  static final WispInnerTubeXMetadataExtractor _instance = WispInnerTubeXMetadataExtractor._internal();
  WispInnerTubeXMetadataExtractor._internal();
  factory WispInnerTubeXMetadataExtractor() => _instance;
  static WispInnerTubeXMetadataExtractor get instance => _instance;

  final InnerTubeXBackend _backend = InnerTubeXBackend.instance;

  Future<List<InnerTubeSearchResult>> search(String query, {String? type, int limit = 20}) {
    return _backend.search(query, type: type, limit: limit);
  }

  Future<InnerTubeTrack> getTrackInfo(String videoId) {
    return _backend.getTrackDetails(videoId);
  }

  Future<InnerTubeAlbum> getAlbumInfo(String browseId) {
    return _backend.getAlbumDetails(browseId);
  }

  Future<InnerTubeArtist> getArtistInfo(String browseId) {
    return _backend.getArtistDetails(browseId);
  }

  Future<InnerTubePlaylist> getPlaylistInfo(String browseId) {
    return _backend.getPlaylistDetails(browseId);
  }

  Future<InnerTubeAuthStatus> setSessionCookies(Map<String, String> cookies) {
    return _backend.updateSessionCookies(cookies);
  }

  Future<InnerTubeAuthStatus> getAuthStatus() {
    return _backend.getAuthStatus();
  }

  Future<InnerTubeAuthStatus> clearSession() {
    return _backend.clearSession();
  }

  Future<List<InnerTubeSearchResult>> getLikedTracks() {
    return _backend.getLikedTracks();
  }
}
