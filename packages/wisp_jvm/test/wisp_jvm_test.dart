import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_jvm/wisp_jvm.dart';

void main() {
  group('JvmPlatformInfo Tests', () {
    test('returns valid platform info for current environment', () {
      final platform = JvmPlatformInfo.current();
      expect(platform.osSlug, isIn(['windows', 'macos', 'linux']));
      expect(platform.archSlug, isIn(['x64', 'arm64']));
      expect(platform.javaOsSlug, isIn(['windows', 'mac', 'linux']));
      expect(platform.javaArchSlug, isIn(['x64', 'aarch64']));
      expect(platform.javaArchiveExtension, isIn(['zip', 'tar.gz']));
      expect(platform.javaExecutableRelativePath, isNotEmpty);
    });

    test('manual platform configuration matches specifications', () {
      const macArm = JvmPlatformInfo(
        osSlug: 'macos',
        archSlug: 'arm64',
        displayOs: 'macOS',
        displayArch: 'arm64',
      );
      expect(macArm.javaOsSlug, 'mac');
      expect(macArm.javaArchSlug, 'aarch64');
      expect(macArm.javaArchiveExtension, 'tar.gz');

      const winX64 = JvmPlatformInfo(
        osSlug: 'windows',
        archSlug: 'x64',
        displayOs: 'Windows',
        displayArch: 'x64',
      );
      expect(winX64.javaOsSlug, 'windows');
      expect(winX64.javaArchSlug, 'x64');
      expect(winX64.javaArchiveExtension, 'zip');
    });
  });

  group('JvmRuntimeManager Tests', () {
    test('singleton instance is persistent', () {
      final instance1 = JvmRuntimeManager.instance;
      final instance2 = JvmRuntimeManager.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });
}

