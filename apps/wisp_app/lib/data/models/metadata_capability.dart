// Copyright © 2026 wizeshi

/// Defines discrete capabilities supported by metadata providers.
enum MetadataCapability {
  search('search'),
  home('home'),
  canvas('canvas'),
  npv('npv'),
  library('library'),
  playlistManagement('playlist_management'),
  recommendations('recommendations'),
  userProfile('user_profile');

  final String id;
  const MetadataCapability(this.id);

  String toJson() => id;

  /// Parse capability from manifest string identifier.
  static MetadataCapability? fromString(String raw) {
    final lower = raw.trim().toLowerCase();
    final normalized = lower.replaceAll('-', '_');
    for (final cap in MetadataCapability.values) {
      if (cap.id == lower ||
          cap.id == normalized ||
          cap.name.toLowerCase() == lower ||
          cap.name.toLowerCase() == normalized) {
        return cap;
      }
    }
    return null;
  }
}
