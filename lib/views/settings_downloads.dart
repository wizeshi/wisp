library;

import 'package:flutter/material.dart';

import '../services/cache_manager.dart';

class DownloadsSettingsPage extends StatelessWidget {
  const DownloadsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        title: const Text('Downloads'),
      ),
      body: ListenableBuilder(
        listenable: AudioCacheManager.instance,
        builder: (context, _) {
          final cacheManager = AudioCacheManager.instance;
          final activeDownloads = cacheManager.recentActiveDownloads;
          final downloadedTracks = cacheManager.downloadedTracks;

          if (activeDownloads.isEmpty && downloadedTracks.isEmpty) {
            return Center(
              child: Text(
                'No downloads yet',
                style: TextStyle(color: Colors.grey[500]),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (activeDownloads.isNotEmpty) ...[
                _buildSectionHeader(context, 'DOWNLOADING'),
                const SizedBox(height: 10),
                ...activeDownloads.map((task) => _buildActiveTile(context, task)),
                const SizedBox(height: 20),
              ],
              if (downloadedTracks.isNotEmpty) ...[
                _buildSectionHeader(context, 'DOWNLOADED'),
                const SizedBox(height: 10),
                ...downloadedTracks.map((entry) => _buildCompletedTile(context, entry)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.grey[600],
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildActiveTile(BuildContext context, DownloadTask task) {
    final isDownloading = task.status == DownloadStatus.downloading;
    final statusLabel = isDownloading ? 'Downloading' : 'Queued';
    final progressPercent = (task.progress * 100).clamp(0, 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          isDownloading ? Icons.downloading : Icons.schedule,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          task.trackTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              task.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              '$statusLabel • $progressPercent%',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedTile(BuildContext context, CacheEntry entry) {
    final title = (entry.trackTitle?.trim().isNotEmpty ?? false)
        ? entry.trackTitle!
        : entry.trackId;
    final artist = (entry.artistName?.trim().isNotEmpty ?? false)
        ? entry.artistName!
        : 'Unknown artist';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          Icons.download_done,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          '$artist • ${_formatDateTime(entry.downloadDate)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}
