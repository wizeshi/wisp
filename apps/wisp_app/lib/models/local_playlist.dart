/// Local/mixed playlist model
library;

import 'metadata_models.dart';

class LocalPlaylist {
  final String id;
  final String title;
  final String? thumbnailPath;
  final String? linkedId;
  final SongSource? linkedSource;
  final String authorName;
  final List<PlaylistItem> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalPlaylist({
    required this.id,
    required this.title,
    required this.authorName,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailPath,
    this.linkedId,
    this.linkedSource,
  });

  bool get isLinked => linkedId != null && linkedSource != null;

  LocalPlaylist copyWith({
    String? title,
    String? thumbnailPath,
    String? linkedId,
    SongSource? linkedSource,
    String? authorName,
    List<PlaylistItem>? tracks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LocalPlaylist(
      id: id,
      title: title ?? this.title,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      linkedId: linkedId ?? this.linkedId,
      linkedSource: linkedSource ?? this.linkedSource,
      authorName: authorName ?? this.authorName,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
      'thumbnail_path': thumbnailPath,
        'linked_id': linkedId,
        'linked_source': linkedSource?.toJson(),
        'author_name': authorName,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    return LocalPlaylist(
      id: json['id'] as String,
      title: json['title'] as String,
        thumbnailPath: json['thumbnail_path'] as String?,
      linkedId: json['linked_id'] as String?,
      linkedSource: json['linked_source'] != null
          ? SongSource.fromJson(json['linked_source'] as String)
          : null,
      authorName: json['author_name'] as String? ?? 'You',
      tracks: (json['tracks'] as List?)
              ?.map((t) => PlaylistItem.fromJson(t as Map<String, dynamic>))
              .toList() ??
          <PlaylistItem>[],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}