// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source_manager.dart';
import 'package:wisp/data/sources/metadata/metadata_source_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp_assets/wisp_assets.dart';
import 'provider_package_model.dart';

const appRepo = "${WispInfo.author}/wisp";

/// Service responsible for fetching, downloading, updating, and managing
/// modular providers from the repository catalog.
class ProvidersRepositoryService {
  static final ProvidersRepositoryService instance =
      ProvidersRepositoryService._();

  ProvidersRepositoryService._();

  static const String repoRawBaseUrl =
      'https://raw.githubusercontent.com/$appRepo/main/providers';

  /// Number of installed providers with an update available.
  final ValueNotifier<int> updatesAvailableCount = ValueNotifier<int>(0);

  /// List of packages that currently have an update available.
  final ValueNotifier<List<ProviderPackage>> packagesWithUpdate =
      ValueNotifier<List<ProviderPackage>>([]);

  /// Check whether a specific provider has an update available.
  bool hasUpdateForProvider(String id, {String? type}) {
    return packagesWithUpdate.value.any(
      (pkg) => pkg.id == id && (type == null || pkg.type == type),
    );
  }

  /// Get the local providers root directory for the app.
  Future<Directory> getBaseProvidersDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'providers'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Discover all available providers by scanning the repository folders
  /// (via GitHub Git Trees API) or walking local directories recursively for manifest.json.
  Future<List<ProviderPackage>> fetchCatalog({
    PreferencesProvider? preferences,
  }) async {
    final Map<String, ProviderPackage> discovered = {};

    // 1. Try remote GitHub Git Trees API
    try {
      final treeRes = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/$appRepo/git/trees/main?recursive=1',
            ),
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent': 'wisp-app',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (treeRes.statusCode == 200) {
        final treeData = jsonDecode(treeRes.body) as Map<String, dynamic>;
        final tree =
            (treeData['tree'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];

        // Find all manifest.json files under providers/
        final manifestEntries = tree.where((item) {
          final path = (item['path'] as String? ?? '').replaceAll('\\', '/');
          return path.startsWith('providers/') &&
              path.endsWith('/manifest.json');
        }).toList();

        for (final entry in manifestEntries) {
          final manifestPath = (entry['path'] as String).replaceAll('\\', '/');
          final parentDir = p.dirname(manifestPath).replaceAll('\\', '/');
          final relativeProviderPath = parentDir.substring('providers/'.length);

          final siblingFiles = tree
              .where((item) {
                final pth = (item['path'] as String? ?? '').replaceAll(
                  '\\',
                  '/',
                );
                final type = item['type'] as String? ?? '';
                return pth.startsWith('$parentDir/') && type == 'blob';
              })
              .map((item) => p.basename(item['path'] as String))
              .toList();

          try {
            final rawManifestUrl =
                '$repoRawBaseUrl/$relativeProviderPath/manifest.json';
            final mRes = await http
                .get(Uri.parse(rawManifestUrl))
                .timeout(const Duration(seconds: 4));

            if (mRes.statusCode == 200) {
              final json = jsonDecode(mRes.body) as Map<String, dynamic>;
              json['path'] = relativeProviderPath;
              json['files'] = siblingFiles.isNotEmpty
                  ? siblingFiles
                  : ['manifest.json', 'index.js'];
              final pkg = ProviderPackage.fromJson(json);
              discovered[pkg.uniqueKey] = pkg;
            }
          } catch (e) {
            logger.d(
              '[ProvidersRepositoryService] Failed to fetch manifest for $manifestPath: $e',
            );
          }
        }
      }
    } catch (e) {
      logger.d('[ProvidersRepositoryService] Remote tree API scan failed: $e');
    }

    // 2. Discover from local workspace providers directories recursively
    final potentialRoots = [
      p.join(Directory.current.path, 'providers'),
      p.join(Directory.current.path, '..', '..', 'providers'),
      p.join(Directory.current.path, '..', 'providers'),
    ];

    for (final rootPath in potentialRoots) {
      final rootDir = Directory(rootPath);
      if (!rootDir.existsSync()) continue;

      try {
        final manifests = rootDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.basename(f.path).toLowerCase() == 'manifest.json');

        for (final manifestFile in manifests) {
          try {
            final content = await manifestFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final providerDir = manifestFile.parent;
            final relativePath = p
                .relative(providerDir.path, from: rootDir.path)
                .replaceAll('\\', '/');

            final files = providerDir
                .listSync()
                .whereType<File>()
                .map((f) => p.basename(f.path))
                .toList();

            json['path'] = relativePath;
            json['files'] = files.isNotEmpty
                ? files
                : ['manifest.json', 'index.js'];

            final pkg = ProviderPackage.fromJson(json);
            final key = pkg.uniqueKey;
            if (discovered.containsKey(key)) {
              final existing = discovered[key]!;
              if (ProviderPackage.isNewerVersion(
                pkg.version,
                existing.version,
              )) {
                discovered[key] = pkg;
              } else if (!ProviderPackage.isNewerVersion(
                existing.version,
                pkg.version,
              )) {
                // When versions are equal, prefer local workspace definition
                discovered[key] = pkg;
              }
            } else {
              discovered[key] = pkg;
            }
          } catch (e) {
            logger.d('[ProvidersRepositoryService] Local manifest error: $e');
          }
        }
      } catch (e) {
        logger.d(
          '[ProvidersRepositoryService] Local scan failed for $rootPath: $e',
        );
      }
    }

    final baseDir = await getBaseProvidersDirectory();
    final results = <ProviderPackage>[];

    for (final pkg in discovered.values) {
      final installedFolder = Directory(p.join(baseDir.path, pkg.path));
      final manifestFile = File(p.join(installedFolder.path, 'manifest.json'));

      bool isInstalled = false;
      String? installedVersion;

      if (manifestFile.existsSync()) {
        isInstalled = true;
        try {
          final m =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          installedVersion = m['version'] as String? ?? '1.0.0';
        } catch (_) {
          installedVersion = '1.0.0';
        }
      } else {
        // Also check if currently loaded in source manager (e.g. built-in)
        final loaded = pkg.type == 'metadata'
            ? MetadataSourceManager.instance.sources.containsKey(pkg.id)
            : pkg.type == 'auth'
            ? AuthSourceManager.instance.sources.containsKey(pkg.id)
            : LyricsSourceManager.instance.allSources.any(
                (s) => s.id == pkg.id,
              );
        if (loaded) {
          isInstalled = true;
          installedVersion = pkg.version;
        }
      }

      bool isEnabled = preferences != null
          ? preferences.isProviderEnabled(pkg.id)
          : await PreferencesProvider.isProviderEnabledStatic(pkg.id);

      results.add(
        pkg.copyWith(
          isInstalled: isInstalled,
          installedVersion: installedVersion,
          isEnabled: isEnabled,
        ),
      );
    }

    final updates = results.where((pkg) => pkg.hasUpdate).toList();
    packagesWithUpdate.value = updates;
    updatesAvailableCount.value = updates.length;

    return results;
  }

  /// Quick check for provider updates without needing explicit UI callers to filter.
  Future<int> checkForUpdates({PreferencesProvider? preferences}) async {
    try {
      final list = await fetchCatalog(preferences: preferences);
      final updates = list.where((p) => p.hasUpdate).toList();
      packagesWithUpdate.value = updates;
      updatesAvailableCount.value = updates.length;
      return updates.length;
    } catch (e) {
      logger.d('[ProvidersRepositoryService] checkForUpdates error: $e');
      return updatesAvailableCount.value;
    }
  }

  /// Update all providers that currently have an update available.
  Future<bool> updateAllProviders() async {
    final targets = List<ProviderPackage>.from(packagesWithUpdate.value);
    bool allSuccess = true;
    for (final pkg in targets) {
      final ok = await installOrUpdateProvider(pkg);
      if (!ok) allSuccess = false;
    }
    return allSuccess;
  }

  /// Download and install or update a provider package.
  Future<bool> installOrUpdateProvider(ProviderPackage pkg) async {
    try {
      final baseDir = await getBaseProvidersDirectory();
      final targetDir = Directory(p.join(baseDir.path, pkg.path));
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      // Critical files that must be written for the install to be considered valid.
      // manifest.json is always required; index.js is the conventional entry point.
      const criticalFiles = {'manifest.json', 'index.js'};
      final Set<String> writtenFiles = {};

      for (final fileName in pkg.files) {
        Uint8List? bytes;

        // Try local workspace first — guarantees that a locally-bumped version
        // is installed rather than the potentially stale remote copy. In
        // production (no workspace) these paths simply don't exist.
        final localPaths = [
          p.join(Directory.current.path, 'providers', pkg.path, fileName),
          p.join(
            Directory.current.path,
            '..',
            '..',
            'providers',
            pkg.path,
            fileName,
          ),
          p.join(Directory.current.path, '..', 'providers', pkg.path, fileName),
        ];

        for (final lp in localPaths) {
          final f = File(lp);
          if (f.existsSync()) {
            bytes = await f.readAsBytes();
            break;
          }
        }

        // Fall back to remote download
        if (bytes == null) {
          try {
            final fileUrl = '$repoRawBaseUrl/${pkg.path}/$fileName';
            final res = await http
                .get(Uri.parse(fileUrl))
                .timeout(const Duration(seconds: 10));
            if (res.statusCode == 200) {
              bytes = res.bodyBytes;
            }
          } catch (_) {}
        }

        if (bytes != null) {
          final targetFile = File(p.join(targetDir.path, fileName));
          await targetFile.writeAsBytes(bytes);
          writtenFiles.add(fileName);
        } else {
          logger.w(
            '[ProvidersRepositoryService] Could not find content for $fileName',
          );
        }
      }

      // Fail if none of the critical files were written.
      if (!writtenFiles.any(criticalFiles.contains)) {
        logger.e(
          '[ProvidersRepositoryService] No critical files written for ${pkg.name} — aborting',
        );
        return false;
      }

      // Auto-install dependencies if not already installed
      if (pkg.dependencies.isNotEmpty) {
        for (final depPath in pkg.dependencies) {
          final depDir = Directory(p.join(baseDir.path, depPath));
          if (!depDir.existsSync()) {
            final catalog = await fetchCatalog();
            final depPkg = catalog
                .where((p) => p.path == depPath || p.uniqueKey == depPath)
                .firstOrNull;
            if (depPkg != null) {
              logger.i(
                '[ProvidersRepositoryService] Installing dependency $depPath for ${pkg.name}...',
              );
              await installOrUpdateProvider(depPkg);
            }
          }
        }
      }

      // Clear uninstalled state in source managers
      if (pkg.type == 'metadata') {
        MetadataSourceManager.instance.clearUninstalled(pkg.id);
      } else if (pkg.type == 'lyrics') {
        LyricsSourceManager.instance.clearUninstalled(pkg.id);
      } else if (pkg.type == 'auth') {
        AuthSourceManager.instance.clearUninstalled(pkg.id);
      }

      // Reload source managers so changes are immediately active
      await AuthSourceManager.instance.reload();
      await MetadataSourceManager.instance.reload();
      await LyricsSourceManager.instance.reload();
      packagesWithUpdate.value = packagesWithUpdate.value
          .where((p) => p.uniqueKey != pkg.uniqueKey)
          .toList();
      updatesAvailableCount.value = packagesWithUpdate.value.length;
      logger.i(
        '[ProvidersRepositoryService] Successfully installed ${pkg.name}',
      );
      return true;
    } catch (e) {
      logger.e(
        '[ProvidersRepositoryService] Failed to install ${pkg.name}: $e',
      );
      return false;
    }
  }

  /// Uninstall a provider by removing its directory.
  Future<bool> uninstallProvider(ProviderPackage pkg) async {
    try {
      final baseDir = await getBaseProvidersDirectory();
      final targetDir = Directory(p.join(baseDir.path, pkg.path));
      if (targetDir.existsSync()) {
        targetDir.deleteSync(recursive: true);
      }

      // Immediately unregister from memory
      if (pkg.type == 'metadata') {
        MetadataSourceManager.instance.unregisterSource(pkg.id);
      } else if (pkg.type == 'lyrics') {
        LyricsSourceManager.instance.unregisterSource(pkg.id);
      } else if (pkg.type == 'auth') {
        AuthSourceManager.instance.unregisterSource(pkg.id);
      }

      await AuthSourceManager.instance.reload();
      await MetadataSourceManager.instance.reload();
      await LyricsSourceManager.instance.reload();
      packagesWithUpdate.value = packagesWithUpdate.value
          .where((p) => p.uniqueKey != pkg.uniqueKey)
          .toList();
      updatesAvailableCount.value = packagesWithUpdate.value.length;
      logger.i(
        '[ProvidersRepositoryService] Successfully uninstalled ${pkg.name}',
      );
      return true;
    } catch (e) {
      logger.e(
        '[ProvidersRepositoryService] Failed to uninstall ${pkg.name}: $e',
      );
      return false;
    }
  }
}
