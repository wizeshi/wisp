import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the support directory owned by the installed wisp application.
class WispSupportDirectory {
  static const _applicationId = 'dev.wizeshi.wisp';

  Future<Directory> get() async {
    if (Platform.isMacOS) {
      final installerSupportDirectory = await getApplicationSupportDirectory();
      return Directory(
        p.join(installerSupportDirectory.parent.path, _applicationId),
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(
      supportDirectory.parent.parent.path,
      '${_applicationId.split('.')[0]}.${_applicationId.split('.')[1]}',
      _applicationId.split('.')[2],
    ));
  }
}

