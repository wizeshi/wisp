// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';

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
  static const Map<String, String> _cacheTypes = {
    'audio': 'Audio',
    'metadata': 'Metadata',
    'lyrics': 'Lyrics',
    'yt-sp-link': 'Youtube - Spotify Link',
  };

  late final Map<String, bool> _cacheDeleteEnabled;

  @override
  void initState() {
    super.initState();
    _cacheDeleteEnabled = _cacheTypes.map(
      (key, value) => MapEntry(key, false),
    );
  }

  Future<bool> _deleteCacheByType(String type) async {
    try {
      switch (type) {
        case 'audio':
          await AudioCacheManager.instance.clearCache();
          return true;

        case 'metadata':
          await MetadataCacheStore.instance.clearProvider('spotify');
          await MetadataCacheStore.instance.clearProvider('spotify_internal');
          await MetadataCacheStore.instance.clearProvider('youtube');
          return true;

        case 'yt-sp-link':
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
        'Cache Deletion',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Theme(
            data: Theme.of(
              context,
            ).copyWith(dividerColor: Colors.transparent),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _cacheTypes.entries.map((entry) {
                return SwitchListTile.adaptive(
                  title: Text(
                    entry.value,
                    style: const TextStyle(color: Colors.white),
                  ),
                  value: _cacheDeleteEnabled[entry.key]!,
                  onChanged: (value) {
                    setState(() {
                      _cacheDeleteEnabled[entry.key] = value;
                    });
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              for (var key in _cacheDeleteEnabled.keys) {
                _cacheDeleteEnabled[key] = false;
              }
            });
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            var hadFailure = false;
            for (var key in _cacheDeleteEnabled.keys) {
              if (_cacheDeleteEnabled[key] == true) {
                final success = await _deleteCacheByType(key);
                if (!success) {
                  hadFailure = true;
                }
              }
            }
            if (!mounted) return;
            widget.showSnackBar(
              hadFailure
                  ? 'Some selected caches could not be deleted.'
                  : 'Selected caches deleted.',
            );
            navigator.pop();
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
