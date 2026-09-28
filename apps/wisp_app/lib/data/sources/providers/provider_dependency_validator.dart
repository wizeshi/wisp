// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source_manager.dart';
import 'package:wisp/data/sources/metadata/metadata_source_manager.dart';
import 'package:wisp/data/sources/providers/providers_repository_service.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

enum DependencyStatus {
  satisfied,
  missing,
  disabled,
}

class DependencyCheckResult {
  final String rawDependency; // e.g. "auth/spotify"
  final String type; // e.g. "auth"
  final String id; // e.g. "spotify"
  final DependencyStatus status;
  final String message;

  const DependencyCheckResult({
    required this.rawDependency,
    required this.type,
    required this.id,
    required this.status,
    required this.message,
  });

  bool get isSatisfied => status == DependencyStatus.satisfied;
}

class DependentProviderInfo {
  final String type; // 'metadata', 'lyrics', 'auth'
  final String id;
  final String name;

  const DependentProviderInfo({
    required this.type,
    required this.id,
    required this.name,
  });

  @override
  String toString() => '$name ($type/$id)';
}

class ProviderDependencyValidator {
  ProviderDependencyValidator._();

  /// Parse a dependency string like "auth/spotify" into (type, id).
  /// If no type prefix is specified, defaults to (null, id).
  static (String?, String) parseDependency(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      return (parts.first, parts.sublist(1).join('/'));
    }
    return (null, trimmed);
  }

  /// Check whether a single dependency is satisfied.
  static DependencyCheckResult checkDependency(
    String rawDependency, {
    PreferencesProvider? preferences,
  }) {
    final (type, id) = parseDependency(rawDependency);
    final effectiveType = type ?? 'auth';

    // 1. Check if provider is installed / available in memory
    bool isAvailable = false;
    switch (effectiveType) {
      case 'auth':
        isAvailable = AuthSourceManager.instance.getAuthSource(id) != null;
        break;
      case 'metadata':
        isAvailable = MetadataSourceManager.instance.sources.containsKey(id);
        break;
      case 'lyrics':
        isAvailable = LyricsSourceManager.instance.sources.containsKey(id);
        break;
      default:
        isAvailable = false;
    }

    if (!isAvailable) {
      return DependencyCheckResult(
        rawDependency: rawDependency,
        type: effectiveType,
        id: id,
        status: DependencyStatus.missing,
        message: 'Required provider $rawDependency is not installed or available.',
      );
    }

    // 2. Check if provider is enabled in preferences
    if (preferences != null) {
      final isEnabled = preferences.isProviderEnabled(id, type: effectiveType);
      if (!isEnabled) {
        return DependencyCheckResult(
          rawDependency: rawDependency,
          type: effectiveType,
          id: id,
          status: DependencyStatus.disabled,
          message: 'Required provider $rawDependency is disabled.',
        );
      }
    }

    return DependencyCheckResult(
      rawDependency: rawDependency,
      type: effectiveType,
      id: id,
      status: DependencyStatus.satisfied,
      message: 'Dependency $rawDependency is satisfied.',
    );
  }

  /// Check whether a single dependency is satisfied asynchronously.
  static Future<DependencyCheckResult> checkDependencyAsync(
    String rawDependency, {
    PreferencesProvider? preferences,
  }) async {
    final (type, id) = parseDependency(rawDependency);
    final effectiveType = type ?? 'auth';

    // 1. Check if provider is installed / available in memory
    bool isAvailable = false;
    switch (effectiveType) {
      case 'auth':
        isAvailable = AuthSourceManager.instance.getAuthSource(id) != null;
        break;
      case 'metadata':
        isAvailable = MetadataSourceManager.instance.sources.containsKey(id);
        break;
      case 'lyrics':
        isAvailable = LyricsSourceManager.instance.sources.containsKey(id);
        break;
      default:
        isAvailable = false;
    }

    if (!isAvailable) {
      return DependencyCheckResult(
        rawDependency: rawDependency,
        type: effectiveType,
        id: id,
        status: DependencyStatus.missing,
        message: 'Required provider $rawDependency is not installed or available.',
      );
    }

    // 2. Check if provider is enabled
    final isEnabled = preferences != null
        ? preferences.isProviderEnabled(id, type: effectiveType)
        : await PreferencesProvider.isProviderEnabledStatic(id, type: effectiveType);

    if (!isEnabled) {
      return DependencyCheckResult(
        rawDependency: rawDependency,
        type: effectiveType,
        id: id,
        status: DependencyStatus.disabled,
        message: 'Required provider $rawDependency is disabled.',
      );
    }

    return DependencyCheckResult(
      rawDependency: rawDependency,
      type: effectiveType,
      id: id,
      status: DependencyStatus.satisfied,
      message: 'Dependency $rawDependency is satisfied.',
    );
  }

  /// Check a list of dependencies. Returns only unsatisfied results.
  static List<DependencyCheckResult> checkDependencies(
    List<String> dependencies, {
    PreferencesProvider? preferences,
  }) {
    final results = <DependencyCheckResult>[];
    for (final dep in dependencies) {
      final res = checkDependency(dep, preferences: preferences);
      if (!res.isSatisfied) {
        results.add(res);
      }
    }
    return results;
  }

  /// Check a list of dependencies asynchronously. Returns only unsatisfied results.
  static Future<List<DependencyCheckResult>> checkDependenciesAsync(
    List<String> dependencies, {
    PreferencesProvider? preferences,
  }) async {
    final results = <DependencyCheckResult>[];
    for (final dep in dependencies) {
      final res = await checkDependencyAsync(dep, preferences: preferences);
      if (!res.isSatisfied) {
        results.add(res);
      }
    }
    return results;
  }

  /// Returns true if all dependencies are satisfied.
  static bool areDependenciesSatisfied(
    List<String> dependencies, {
    PreferencesProvider? preferences,
  }) {
    return checkDependencies(dependencies, preferences: preferences).isEmpty;
  }

  /// Returns true if all dependencies are satisfied asynchronously.
  static Future<bool> areDependenciesSatisfiedAsync(
    List<String> dependencies, {
    PreferencesProvider? preferences,
  }) async {
    final results = await checkDependenciesAsync(dependencies, preferences: preferences);
    return results.isEmpty;
  }

  /// Find all installed and active providers that declare a dependency on (targetType, targetId).
  /// For instance, if targetType == 'auth' and targetId == 'spotify',
  /// will find metadata/spotify and lyrics/spotify if they are active/enabled.
  static Future<List<DependentProviderInfo>> getActiveDependentsOf({
    required String type,
    required String id,
    PreferencesProvider? preferences,
  }) async {
    final targetDep = '${type.toLowerCase()}/${id.toLowerCase()}';
    final targetId = id.toLowerCase();
    final dependents = <DependentProviderInfo>[];

    // Read all installed provider manifests
    try {
      final baseDir = await ProvidersRepositoryService.instance.getBaseProvidersDirectory();
      final dirsToScan = <Directory>[baseDir];

      final autoRegisterDev =
          await PreferencesProvider.isAutoRegisterLocalProvidersEnabledStatic();
      if (autoRegisterDev) {
        final devPaths = [
          p.join(Directory.current.path, 'providers'),
          p.join(Directory.current.path, '..', '..', 'providers'),
          p.join(Directory.current.path, '..', 'providers'),
        ];
        for (final dp in devPaths) {
          final d = Directory(dp);
          if (d.existsSync() && !dirsToScan.any((existing) => p.equals(existing.path, d.path))) {
            dirsToScan.add(d);
          }
        }
      }

      final seen = <String>{};

      for (final root in dirsToScan) {
        if (!root.existsSync()) continue;
        final manifestFiles = root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.basename(f.path) == 'manifest.json');

        for (final mf in manifestFiles) {
          try {
            final json = jsonDecode(await mf.readAsString()) as Map<String, dynamic>;
            final pkgId = (json['id'] as String? ?? '').toLowerCase();
            final pkgType = (json['type'] as String? ?? '').toLowerCase();
            final pkgName = json['name'] as String? ?? pkgId;
            final key = '$pkgType/$pkgId';

            if (seen.contains(key)) continue;
            seen.add(key);

            // Don't compare a provider with itself
            if (pkgType == type.toLowerCase() && pkgId == targetId) continue;

            final deps = (json['dependencies'] as List?)?.cast<String>() ?? [];
            final dependsOnTarget = deps.any((d) {
              final trimmed = d.trim().toLowerCase();
              return trimmed == targetDep || trimmed == targetId;
            });

            if (dependsOnTarget) {
              // Check if this dependent provider is currently enabled
              final isEnabled = preferences?.isProviderEnabled(pkgId, type: pkgType) ?? true;
              if (isEnabled) {
                dependents.add(
                  DependentProviderInfo(
                    type: pkgType,
                    id: pkgId,
                    name: pkgName,
                  ),
                );
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      logger.w('[ProviderDependencyValidator] Error checking dependents: $e');
    }

    return dependents;
  }
}
