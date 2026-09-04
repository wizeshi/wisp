import 'dart:io';

import 'package:flutter/services.dart';

class WispIcons {
  static const _base = "packages/wisp_assets/assets";
  static const logo = "$_base/wisp.png";
}

class WispInfo {
  static const github = "https://github.com/wizeshi/wisp";
  static const version = "26.9.1";
  static const author = "wizeshi";
}

final caCertPath = "packages/wisp_assets/certs/cacert.pem";

void initializeWindowsCertificates() async {
  if (!Platform.isWindows) return;

  try {
    final ByteData certData = await rootBundle.load(caCertPath);
    final List<int> certBytes = certData.buffer.asUint8List();

    SecurityContext.defaultContext.setTrustedCertificatesBytes(certBytes);
  } catch (e) {
    print("Failed to load CA certificates: $e");
  }
}