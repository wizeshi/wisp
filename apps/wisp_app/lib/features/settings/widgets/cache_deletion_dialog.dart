// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';

class _CacheCategory {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;

  const _CacheCategory({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class CacheDeletionDialog extends StatefulWidget {
  final void Function(String message) showSnackBar;

  const CacheDeletionDialog({super.key, required this.showSnackBar});

  static Future<void> show(
    BuildContext context, {
    required void Function(String message) showSnackBar,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => CacheDeletionDialog(
        showSnackBar: showSnackBar,
      ),
    );
  }

  @override
  State<CacheDeletionDialog> createState() => _CacheDeletionDialogState();
}

class _CacheDeletionDialogState extends State<CacheDeletionDialog> {
  static const List<_CacheCategory> _categories = [
    _CacheCategory(
      key: 'auto_audio',
      title: 'Streaming Audio Cache',
      subtitle: 'Transient music cached while playing (leaves downloads intact)',
      icon: Icons.cached,
    ),
    _CacheCategory(
      key: 'user_audio',
      title: 'Offline Downloads',
      subtitle: 'Tracks you explicitly saved for offline playback',
      icon: Icons.download_done,
    ),
    _CacheCategory(
      key: 'artwork',
      title: 'Artwork & Cover Images',
      subtitle: 'Cached album art, artist photos, and thumbnails',
      icon: Icons.image_outlined,
    ),
    _CacheCategory(
      key: 'lyrics',
      title: 'Lyrics & Sync Offsets',
      subtitle: 'Saved synchronized and plain lyrics',
      icon: Icons.lyrics_outlined,
    ),
    _CacheCategory(
      key: 'metadata',
      title: 'Metadata & Catalog Data',
      subtitle: 'Cached playlist and track information',
      icon: Icons.dataset_outlined,
    ),
    _CacheCategory(
      key: 'yt_link',
      title: 'YouTube Audio Match Cache',
      subtitle: 'Saved track-to-video search matches',
      icon: Icons.link,
    ),
  ];

  late final Map<String, bool> _cacheDeleteEnabled;

  @override
  void initState() {
    super.initState();
    _cacheDeleteEnabled = {
      for (final cat in _categories) cat.key: false,
    };
  }

  Future<bool> _deleteCacheByType(String type) async {
    try {
      switch (type) {
        case 'auto_audio':
          await AudioCacheManager.instance.clearAutoCache();
          return true;

        case 'user_audio':
          await AudioCacheManager.instance.clearUserDownloads();
          return true;

        case 'artwork':
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          await DefaultCacheManager().emptyCache();
          return true;

        case 'metadata':
          await MetadataCacheStore.instance.clearProvider('spotify');
          await MetadataCacheStore.instance.clearProvider('spotify_internal');
          await MetadataCacheStore.instance.clearProvider('youtube');
          return true;

        case 'yt_link':
          await YouTubeProvider.clearVideoIdCache();
          return true;

        case 'lyrics':
          if (!mounted) return false;
          await context.read<LyricsProvider>().clearCache();
          return true;
      }
    } catch (e) {
      logger.e('[Views/Settings] Failed to delete $type cache: $e');
      return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text(
        'Clear Storage & Cache',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _categories.map((cat) {
              return SwitchListTile.adaptive(
                secondary: Icon(cat.icon, color: Colors.grey[400]),
                title: Text(
                  cat.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  cat.subtitle,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                value: _cacheDeleteEnabled[cat.key] ?? false,
                onChanged: (value) {
                  setState(() {
                    _cacheDeleteEnabled[cat.key] = value;
                  });
                },
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
        ),
        ElevatedButton(
          onPressed: _cacheDeleteEnabled.values.any((v) => v)
              ? () async {
                  final navigator = Navigator.of(context);
                  var hadFailure = false;
                  for (final entry in _cacheDeleteEnabled.entries) {
                    if (entry.value) {
                      final success = await _deleteCacheByType(entry.key);
                      if (!success) hadFailure = true;
                    }
                  }
                  if (!mounted) return;
                  widget.showSnackBar(
                    hadFailure
                        ? 'Some selected caches could not be deleted.'
                        : 'Selected caches cleared.',
                  );
                  navigator.pop();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete Selected'),
        ),
      ],
    );
  }
}
