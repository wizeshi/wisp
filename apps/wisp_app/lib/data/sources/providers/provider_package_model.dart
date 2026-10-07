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
  final String? service;
  final String? homepage;
  final String path;
  final List<String> files;

  final List<String> dependencies;
  final int? capabilityTier;

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

  String get uniqueKey => path.isNotEmpty ? path : '$type/$id';

  int get effectiveCapabilityTier {
    if (capabilityTier != null) return capabilityTier!;
    if (type == 'lyrics') {
      if (supportedSyncModes.contains('word')) return 3;
      if (supportedSyncModes.contains('line')) return 2;
      if (supportedSyncModes.contains('unsynced')) return 1;
      return 0;
    }
    if (type == 'audio') {
      final qLower = supportedQualities.map((q) => q.toLowerCase()).toList();
      if (qLower.contains('hi-res') || qLower.contains('hires') || qLower.contains('lossless')) return 3;
      if (qLower.contains('high')) return 2;
      return 1;
    }
    if (type == 'metadata') {
      if (priority >= 100) return 3;
      if (priority >= 50) return 2;
      return 1;
    }
    if (type == 'auth') {
      return 3;
    }
    return 1;
  }

  /// Sorts by type (metadata -> audio -> lyrics -> auth), then capability tier descending, then priority descending.
  static int comparePackages(ProviderPackage a, ProviderPackage b) {
    const typeOrder = {'metadata': 1, 'audio': 2, 'lyrics': 3, 'auth': 4};
    final aTypeRank = typeOrder[a.type.toLowerCase()] ?? 99;
    final bTypeRank = typeOrder[b.type.toLowerCase()] ?? 99;
    if (aTypeRank != bTypeRank) return aTypeRank.compareTo(bTypeRank);

    final tierDiff = b.effectiveCapabilityTier.compareTo(a.effectiveCapabilityTier);
    if (tierDiff != 0) return tierDiff;

    return b.priority.compareTo(a.priority);
  }

  const ProviderPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    this.service,
    this.author = 'wisp',
    this.description = '',
    this.supportedSyncModes = const [],
    this.supportedQualities = const [],
    this.priority = 0,
    this.dependencies = const [],
    this.capabilityTier,
    this.homepage,
    required this.path,
    this.files = const ['manifest.json', 'index.js'],
    this.isInstalled = false,
    this.installedVersion,
    this.isEnabled = true,
  });

  final List<String> supportedQualities;

  factory ProviderPackage.fromJson(
    Map<String, dynamic> json, {
    bool isInstalled = false,
    String? installedVersion,
    bool isEnabled = true,
  }) {
    final modes = (json['supportedSyncModes'] as List?)?.cast<String>() ?? [];
    final qualities = (json['supportedQualities'] as List?)?.cast<String>() ?? [];
    final deps = (json['dependencies'] as List?)?.cast<String>() ?? [];
    final filesList = (json['files'] as List?)?.cast<String>() ?? ['manifest.json', 'index.js'];

    return ProviderPackage(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? (json['id'] as String? ?? ''),
      version: json['version'] as String? ?? '1.0.0',
      type: json['type'] as String? ?? 'lyrics',
      service: json['service'] as String?,
      author: json['author'] as String? ?? 'wisp',
      description: json['description'] as String? ?? '',
      supportedSyncModes: modes,
      supportedQualities: qualities,
      priority: json['priority'] as int? ?? 0,
      dependencies: deps,
      capabilityTier: json['capabilityTier'] as int?,
      homepage: json['homepage'] as String?,
      path: json['path'] as String? ?? '${json['type'] ?? "lyrics"}/${json['id']}',
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
    List<String>? supportedQualities,
  }) {
    return ProviderPackage(
      id: id,
      name: name,
      version: version,
      type: type,
      service: service,
      author: author,
      description: description,
      supportedSyncModes: supportedSyncModes,
      supportedQualities: supportedQualities ?? this.supportedQualities,
      priority: priority,
      dependencies: dependencies,
      capabilityTier: capabilityTier,
      homepage: homepage,
      path: path,
      files: files,
      isInstalled: isInstalled ?? this.isInstalled,
      installedVersion: installedVersion ?? this.installedVersion,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
