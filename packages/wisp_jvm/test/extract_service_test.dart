import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_jvm/src/extract_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wisp_jvm_extract_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('extractTarGzArchive extracts .tar.gz via streaming Isolate.run', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('jre/bin/hello.txt', utf8.encode('hello tar.gz')));
    final tarBytes = TarEncoder().encode(archive);
    final gzBytes = GZipEncoder().encode(tarBytes);

    final tarGzFile = File('${tempDir.path}/runtime.tar.gz')
      ..writeAsBytesSync(gzBytes);
    final destDir = Directory('${tempDir.path}/out_targz');

    await JvmExtractService().extractTarGzArchive(
      archiveFile: tarGzFile,
      destinationDir: destDir,
    );

    final extracted = File('${destDir.path}/jre/bin/hello.txt');
    expect(extracted.existsSync(), isTrue);
    expect(extracted.readAsStringSync(), 'hello tar.gz');
  });

  test('extractZipArchive extracts .zip via Isolate.run', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('jre/bin/hello.txt', utf8.encode('hello zip')));
    final zipBytes = ZipEncoder().encode(archive);

    final zipFile = File('${tempDir.path}/runtime.zip')
      ..writeAsBytesSync(zipBytes);
    final destDir = Directory('${tempDir.path}/out_zip');

    await JvmExtractService().extractZipArchive(
      archiveFile: zipFile,
      destinationDir: destDir,
    );

    final extracted = File('${destDir.path}/jre/bin/hello.txt');
    expect(extracted.existsSync(), isTrue);
    expect(extracted.readAsStringSync(), 'hello zip');
  });
}
