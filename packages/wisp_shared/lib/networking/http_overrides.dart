import 'dart:io';

// This fixes CERTIFICATE_VERIFY_FAILED errors when downloading files.
class WispHttpOverrides extends HttpOverrides{
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port)=> true;
  }
}