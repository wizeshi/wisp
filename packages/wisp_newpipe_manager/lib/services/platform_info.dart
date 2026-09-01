import 'dart:io';

class PlatformInfo {
  const PlatformInfo({
    required this.osSlug,
    required this.archSlug,
    required this.displayOs,
    required this.displayArch,
  });

  final String osSlug;
  final String archSlug;
  final String displayOs;
  final String displayArch;

  String get releaseAssetName => 'wisp-$osSlug-$archSlug.zip';

  String get downloadUrl =>
      'https://github.com/wizeshi/wisp/releases/latest/download/$releaseAssetName';

  String get javaOsSlug => switch (osSlug) {
    'macos' => 'mac',
    'linux' => 'linux',
    'windows' => 'windows',
    _ => throw UnsupportedError('Unsupported operating system: $osSlug'),
  };

  String get javaArchSlug => archSlug == 'arm64' ? 'aarch64' : 'x64';

  String get javaArchiveExtension => osSlug == 'windows' ? 'zip' : 'tar.gz';

  static PlatformInfo current() {
    if (Platform.isMacOS) {
      return PlatformInfo(
        osSlug: 'macos',
        archSlug: _detectMacArch(),
        displayOs: 'macOS',
        displayArch: _detectMacArch(),
      );
    }

    if (Platform.isWindows) {
      return PlatformInfo(
        osSlug: 'windows',
        archSlug: _detectWindowsArch(),
        displayOs: 'Windows',
        displayArch: _detectWindowsArch(),
      );
    }

    if (Platform.isLinux) {
      return PlatformInfo(
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

  static String _detectWindowsArch() {
    return _normalizeArchitecture();
  }

  static String _detectLinuxArch() {
    return _normalizeArchitecture();
  }

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
