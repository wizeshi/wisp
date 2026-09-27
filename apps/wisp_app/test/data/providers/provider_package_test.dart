// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/sources/providers/provider_package_model.dart';

void main() {
  group('ProviderPackage Version & Update Indicator Tests', () {
    test('isNewerVersion detects higher patch, minor, and major versions', () {
      // Patch update
      expect(ProviderPackage.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(ProviderPackage.isNewerVersion('1.0.0', '1.0.1'), isFalse);

      // Minor update
      expect(ProviderPackage.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(ProviderPackage.isNewerVersion('1.0.9', '1.1.0'), isFalse);

      // Major update
      expect(ProviderPackage.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(ProviderPackage.isNewerVersion('1.9.9', '2.0.0'), isFalse);

      // Same version
      expect(ProviderPackage.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(ProviderPackage.isNewerVersion('1.2.3', '1.2.3'), isFalse);

      // Null or empty local
      expect(ProviderPackage.isNewerVersion('1.0.0', null), isFalse);
      expect(ProviderPackage.isNewerVersion('1.0.0', ''), isFalse);
    });

    test('ProviderPackage.hasUpdate is true only when installed and remote is newer', () {
      const upToDate = ProviderPackage(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        version: '1.0.0',
        type: 'lyrics',
        path: 'lyrics/betterlyrics',
        isInstalled: true,
        installedVersion: '1.0.0',
      );
      expect(upToDate.hasUpdate, isFalse);

      const updateAvailable = ProviderPackage(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        version: '1.1.0',
        type: 'lyrics',
        path: 'lyrics/betterlyrics',
        isInstalled: true,
        installedVersion: '1.0.0',
      );
      expect(updateAvailable.hasUpdate, isTrue);

      const notInstalled = ProviderPackage(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        version: '1.1.0',
        type: 'lyrics',
        path: 'lyrics/betterlyrics',
        isInstalled: false,
        installedVersion: null,
      );
      expect(notInstalled.hasUpdate, isFalse);

      const devBuild = ProviderPackage(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        version: '1.0.0',
        type: 'lyrics',
        path: 'lyrics/betterlyrics',
        isInstalled: true,
        installedVersion: '1.2.0',
      );
      expect(devBuild.hasUpdate, isFalse);
      expect(
        ProviderPackage.isNewerVersion(devBuild.installedVersion!, devBuild.version),
        isTrue,
      );
    });
  });
}
