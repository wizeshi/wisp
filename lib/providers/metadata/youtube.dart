/// YouTube metadata provider (search-only)
library;

import 'package:flutter/foundation.dart';

import '../../models/metadata_models.dart';
import '../../models/youtube_converters.dart';
import '../../services/metadata_cache.dart';
import '../audio/youtube.dart';

class YouTubeMetadataProvider extends ChangeNotifier {
	final MetadataCacheStore _metadataCache = MetadataCacheStore.instance;
	final YouTubeProvider _youtube = YouTubeProvider();
	static const String _metadataProvider = 'youtube';

	Future<MetadataCacheEntry?> _readCacheEntry({
		required String type,
		required String id,
	}) {
		return _metadataCache.readEntry(
			provider: _metadataProvider,
			type: type,
			id: id,
		);
	}

	Future<void> _writeCacheEntry({
		required String type,
		required String id,
		required Map<String, dynamic> payload,
	}) {
		return _metadataCache.writeEntry(
			provider: _metadataProvider,
			type: type,
			id: id,
			payload: payload,
		);
	}

	Future<List<T>> _getListWithCache<T>({
		required String type,
		required String id,
		required MetadataFetchPolicy policy,
		required Future<List<T>> Function() fetcher,
		required Map<String, dynamic> Function(T) itemToJson,
		required T Function(Map<String, dynamic>) itemFromJson,
	}) async {
		MetadataCacheEntry? entry;
		List<T>? cached;
		try {
			entry = await _readCacheEntry(type: type, id: id);
			final items = entry?.payload['items'] as List?;
			if (items != null) {
				cached = items
						.whereType<Map<String, dynamic>>()
						.map(itemFromJson)
						.toList();
			}
		} catch (_) {
			cached = null;
		}

		final isExpired = entry?.isExpired ?? true;
		if (cached != null) {
			if (policy == MetadataFetchPolicy.cacheFirst) {
				return cached;
			}
			if (policy == MetadataFetchPolicy.refreshIfExpired && !isExpired) {
				return cached;
			}
			if (policy == MetadataFetchPolicy.refreshAlways) {
				try {
					final fresh = await fetcher();
					await _writeCacheEntry(
						type: type,
						id: id,
						payload: {'items': fresh.map(itemToJson).toList()},
					);
					return fresh;
				} catch (_) {
					return cached;
				}
			}
		}

		try {
			final fresh = await fetcher();
			await _writeCacheEntry(
				type: type,
				id: id,
				payload: {'items': fresh.map(itemToJson).toList()},
			);
			return fresh;
		} catch (e) {
			if (cached != null) return cached;
			rethrow;
		}
	}

	String _cacheKeyForQuery(String query) {
		final normalized = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
		return normalized.isEmpty ? 'empty' : normalized;
	}

	Future<List<GenericSong>> searchTracks(
		String query, {
		int limit = 10,
		MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
	}) async {
		final cacheId = _cacheKeyForQuery(query);
		return _getListWithCache<GenericSong>(
			type: 'search_tracks',
			id: cacheId,
			policy: policy,
			fetcher: () async {
				final results = await _youtube.searchYouTubeTracks(
					query,
					limit: limit,
				);
				return results.map(youtubeResultToGenericSong).toList();
			},
			itemToJson: (item) => item.toJson(),
			itemFromJson: GenericSong.fromJson,
		);
	}
}
