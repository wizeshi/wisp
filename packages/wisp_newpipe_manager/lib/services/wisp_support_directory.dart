import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the support directory owned by the installed Wisp application.
///
/// `getApplicationSupportDirectory` resolves the installer bundle's directory,
/// so its parent is used to target the main application's bundle identifier.
class WispSupportDirectory {
  static const _applicationId = 'dev.wizeshi.wisp';

  Future<Directory> get() async {
    if (Platform.isMacOS) {
      final installerSupportDirectory = await getApplicationSupportDirectory();
      return Directory(
        p.join(installerSupportDirectory.parent.path, _applicationId),
      );
    }

    // On Windows and Linux, the main app uses the same per-user support root
    // as the installer. Keeping the application ID as a child avoids writing
    // installer-specific data into the app's runtime directory.
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(
      supportDirectory.parent.parent.path,
      '${_applicationId.split('.')[0]}.${_applicationId.split('.')[1]}',
      _applicationId.split('.')[2]
    ));
  }
}
