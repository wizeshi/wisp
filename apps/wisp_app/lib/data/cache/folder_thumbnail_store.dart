// Copyright © 2026 wizeshi

/// Folder thumbnail storage helper
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

Uint8List? _decodeResizeEncodePng(Uint8List bytes, int size) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: size, height: size);
  return Uint8List.fromList(img.encodePng(resized));
}

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
      final encoded = await Isolate.run(
        () => _decodeResizeEncodePng(bytes, _thumbSize),
      );
      if (encoded == null) return null;

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
