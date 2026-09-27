// Copyright © 2026 wizeshi

library;

/// Represents a downloadable or installed modular provider package.
class ProviderPackage {
  final String id;
  final String name;
  final String version;
  final String type;
  final String author;
  final String description;
  final List<String> supportedSyncModes;
  final int priority;
  final String? homepage;
  final String path;
  final List<String> files;

  /// Runtime state
  final bool isInstalled;
  final String? installedVersion;
  final bool isEnabled;

  /// Compares semantic version strings (e.g. 1.0.1 vs 1.0.0).
  /// Returns true if [remote] is strictly newer than [local].
  static bool isNewerVersion(String remote, String? local) {
    if (local == null || local.trim().isEmpty) return false;
    final rClean = remote.trim();
    final lClean = local.trim();
    if (rClean == lClean) return false;

    try {
      final remoteParts = rClean
          .split(RegExp(r'[-+.]'))
          .map((p) => int.tryParse(p) ?? 0)
          .toList();
      final localParts = lClean
          .split(RegExp(r'[-+.]'))
          .map((p) => int.tryParse(p) ?? 0)
          .toList();

      final maxLen = remoteParts.length > localParts.length
          ? remoteParts.length
          : localParts.length;

      for (int i = 0; i < maxLen; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final l = i < localParts.length ? localParts[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
    } catch (_) {}

    return rClean != lClean;
  }

  bool get hasUpdate =>
      isInstalled &&
      isNewerVersion(version, installedVersion);

  const ProviderPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    this.author = 'wisp',
    this.description = '',
    this.supportedSyncModes = const [],
    this.priority = 0,
    this.homepage,
    required this.path,
    this.files = const ['manifest.json', 'index.js'],
    this.isInstalled = false,
    this.installedVersion,
    this.isEnabled = true,
  });

  factory ProviderPackage.fromJson(
    Map<String, dynamic> json, {
    bool isInstalled = false,
    String? installedVersion,
    bool isEnabled = true,
  }) {
    final modes = (json['supportedSyncModes'] as List?)?.cast<String>() ?? [];
    final filesList = (json['files'] as List?)?.cast<String>() ?? ['manifest.json', 'index.js'];

    return ProviderPackage(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? (json['id'] as String? ?? ''),
      version: json['version'] as String? ?? '1.0.0',
      type: json['type'] as String? ?? 'lyrics',
      author: json['author'] as String? ?? 'wisp',
      description: json['description'] as String? ?? '',
      supportedSyncModes: modes,
      priority: json['priority'] as int? ?? 0,
      homepage: json['homepage'] as String?,
      path: json['path'] as String? ?? 'lyrics/${json['id']}',
      files: filesList,
      isInstalled: isInstalled,
      installedVersion: installedVersion,
      isEnabled: isEnabled,
    );
  }

  ProviderPackage copyWith({
    bool? isInstalled,
    String? installedVersion,
    bool? isEnabled,
  }) {
    return ProviderPackage(
      id: id,
      name: name,
      version: version,
      type: type,
      author: author,
      description: description,
      supportedSyncModes: supportedSyncModes,
      priority: priority,
      homepage: homepage,
      path: path,
      files: files,
      isInstalled: isInstalled ?? this.isInstalled,
      installedVersion: installedVersion ?? this.installedVersion,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
