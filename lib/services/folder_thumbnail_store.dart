/// Folder thumbnail storage helper
library;

import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class FolderThumbnailStore {
  FolderThumbnailStore._();

  static final FolderThumbnailStore instance = FolderThumbnailStore._();

  static const String _folderName = 'folder_thumbs';
  static const int _thumbSize = 512;

  Future<Directory> _getFolderDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String?> saveThumbnail(File source, {String? preferredName}) async {
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final resized = img.copyResize(
        decoded,
        width: _thumbSize,
        height: _thumbSize,
      );
      final encoded = img.encodePng(resized);

      final dir = await _getFolderDirectory();
      final fileName = preferredName ?? _randomFileName();
      final outFile = File('${dir.path}/$fileName.png');
      await outFile.writeAsBytes(encoded, flush: true);
      return outFile.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteThumbnail(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  String _randomFileName() {
    final rand = Random();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return 'thumb_${stamp}_${rand.nextInt(999999)}';
  }
}
