import 'dart:io';

class JvmPlatformInfo {
  const JvmPlatformInfo({
    required this.osSlug,
    required this.archSlug,
    required this.displayOs,
    required this.displayArch,
  });

  final String osSlug;
  final String archSlug;
  final String displayOs;
  final String displayArch;

  String get javaOsSlug => switch (osSlug) {
        'macos' => 'mac',
        'linux' => 'linux',
        'windows' => 'windows',
        _ => throw UnsupportedError('Unsupported operating system: $osSlug'),
      };

  String get javaArchSlug => archSlug == 'arm64' ? 'aarch64' : 'x64';

  String get javaArchiveExtension => osSlug == 'windows' ? 'zip' : 'tar.gz';

  String get javaExecutableRelativePath => Platform.isMacOS
      ? 'Contents/Home/bin/java'
      : (Platform.isWindows ? 'bin/java.exe' : 'bin/java');

  static JvmPlatformInfo current() {
    if (Platform.isMacOS) {
      return JvmPlatformInfo(
        osSlug: 'macos',
        archSlug: _detectMacArch(),
        displayOs: 'macOS',
        displayArch: _detectMacArch(),
      );
    }

    if (Platform.isWindows) {
      return JvmPlatformInfo(
        osSlug: 'windows',
        archSlug: _detectWindowsArch(),
        displayOs: 'Windows',
        displayArch: _detectWindowsArch(),
      );
    }

    if (Platform.isLinux) {
      return JvmPlatformInfo(
        osSlug: 'linux',
        archSlug: _detectLinuxArch(),
        displayOs: 'Linux',
        displayArch: _detectLinuxArch(),
      );
    }

    throw UnsupportedError('Unsupported operating system.');
  }

  static String _detectMacArch() {
    final versionToken = Platform.version
        .split(' ')
        .last
        .replaceAll('"', '')
        .split('_')
        .last
        .toLowerCase();

    if (versionToken == 'arm64') return 'arm64';
    if (versionToken == 'x64' || versionToken == 'x86_64') return 'x64';

    throw UnsupportedError('Unsupported macOS architecture: $versionToken');
  }

  static String _detectWindowsArch() => _normalizeArchitecture();

  static String _detectLinuxArch() => _normalizeArchitecture();

  static String _normalizeArchitecture() {
    final versionToken = Platform.version
        .split(' ')
        .last
        .replaceAll('"', '')
        .split('_')
        .last
        .toLowerCase();

    if (versionToken == 'arm64' || versionToken == 'aarch64') return 'arm64';
    if (versionToken == 'x64' || versionToken == 'x86_64') return 'x64';

    throw UnsupportedError('Unsupported architecture: $versionToken');
  }
}

