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

  /// The suffix used by yt-dlp's release assets. macOS and Linux assets do not
  /// have an extension; the Windows asset is an executable.
  String get ytDlpAssetSuffix => switch (osSlug) {
    'macos' => '_macos',
    'linux' => '_linux',
    'windows' => '.exe',
    _ => throw UnsupportedError('Unsupported operating system: $osSlug'),
  };

  String get nodeOsSlug => switch (osSlug) {
    'macos' => 'darwin',
    'linux' => 'linux',
    'windows' => 'win',
    _ => throw UnsupportedError('Unsupported operating system: $osSlug'),
  };

  String get nodeArchSlug => archSlug;

  String get archiveExtension => osSlug == 'windows' ? 'zip' : 'tar.gz';

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
    final arch = Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ??
        Platform.environment['MACHTYPE']?.toLowerCase() ??
        '';

    if (arch.contains('arm64') || arch.contains('aarch64')) return 'arm64';
    if (arch.contains('x86_64') || arch.contains('x64') || arch.contains('amd64')) {
      return 'x64';
    }
    if (arch.contains('x86') || arch.contains('i386') || arch.contains('i686')) {
      return 'x86';
    }

    return 'x64'; // default fallback
  }
}
