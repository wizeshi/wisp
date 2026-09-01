import 'dart:io';

class InstallSession {
  Directory? workDir;
  File? archiveFile;
  Directory? appBundle;
  Directory? installedApp;
  File? installedExecutable;

  Future<void> cleanup() async {
    if (workDir != null && await workDir!.exists()) {
      await workDir!.delete(recursive: true);
    }
    workDir = null;
    archiveFile = null;
    appBundle = null;
    installedApp = null;
    installedExecutable = null;
  }
}
