// Copyright © 2026 wizeshi

/// Local playlist folder model (global across providers)
library;

class PlaylistFolder {
  final String id;
  final String title;
  final String? thumbnailPath;
  final DateTime createdAt;
  final bool isPinned;

  const PlaylistFolder({
    required this.id,
    required this.title,
    required this.createdAt,
    this.thumbnailPath,
    this.isPinned = false,
  });

  PlaylistFolder copyWith({
    String? id,
    String? title,
    String? thumbnailPath,
    DateTime? createdAt,
    bool? isPinned,
  }) {
    return PlaylistFolder(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'thumbnail_path': thumbnailPath,
    'created_at': createdAt.toIso8601String(),
    'is_pinned': isPinned,
  };

  factory PlaylistFolder.fromJson(Map<String, dynamic> json) {
    return PlaylistFolder(
      id: json['id'] as String,
      title: json['title'] as String,
      thumbnailPath: json['thumbnail_path'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      isPinned:
          (json['is_pinned'] as bool?) ?? (json['isPinned'] as bool?) ?? false,
    );
  }
}
