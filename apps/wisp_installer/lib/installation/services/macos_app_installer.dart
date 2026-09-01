import 'dart:io';

import 'package:path/path.dart' as p;

class MacOSAppInstaller {
  static const applicationsDir = '/Applications';

  Future<Directory> installToApplications(Directory appBundle) async {
    final appName = p.basename(appBundle.path);
    final destination = Directory(p.join(applicationsDir, appName));

    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }

    final result = await Process.run('ditto', [
      appBundle.path,
      destination.path,
    ]);

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw ProcessException(
        'ditto',
        [appBundle.path, destination.path],
        stderr.isEmpty ? 'Failed to copy app bundle to Applications.' : stderr,
        result.exitCode,
      );
    }

    return destination;
  }
}
