library;

import 'package:flutter/material.dart';

import '../models/metadata_models.dart';
import '../providers/audio/youtube.dart';

class YouTubeAlternativesView extends StatefulWidget {
  final GenericSong track;

  const YouTubeAlternativesView({super.key, required this.track});

  @override
  State<YouTubeAlternativesView> createState() => _YouTubeAlternativesViewState();
}

class _YouTubeAlternativesViewState extends State<YouTubeAlternativesView> {
  final YouTubeProvider _youTubeProvider = YouTubeProvider();

  List<YouTubeResult> _results = const [];
  bool _isLoading = true;
  String? _error;

  String get _artistNames => widget.track.artists.map((a) => a.name).join(', ');
  String get _query => '$_artistNames - ${widget.track.title}';

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  Future<void> _runSearch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await _youTubeProvider.searchYouTubeTracks(
        _query,
        limit: 20,
        artist: _artistNames,
        title: widget.track.title,
        durationSecs: widget.track.durationSecs,
      );

      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _useManualId() async {
    final existing = YouTubeProvider.getCachedVideoId(widget.track.id) ?? '';
    final controller = TextEditingController(text: existing);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('YouTube Video ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a custom YouTube video ID for this track. Leave empty to clear.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'e.g., dQw4w9WgXcQ'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true || !mounted) return;

    Navigator.pop(context, controller.text.trim());
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Alternatives'),
      ),
      body: Column(
        children: [
          ListTile(
            title: Text(
              widget.track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Divider(height: 1, color: Colors.grey[600]),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _runSearch,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length + 1,
      separatorBuilder: (ctx, index) => Divider(height: 1, color: Colors.grey[900]),
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Use manual ID'),
            subtitle: const Text('Enter a YouTube video ID manually'),
            onTap: _useManualId,
          );
        }

        final result = _results[index - 1];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 80,
              height: 45,
              child: Image.network(
                result.thumbnailUrl,
                fit: BoxFit.cover,
                  errorBuilder: (ctx, error, stackTrace) => const ColoredBox(
                  color: Colors.black12,
                  child: Icon(Icons.music_note),
                ),
              ),
            ),
          ),
          title: Text(
            result.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${result.channelName} • ${_formatDuration(result.duration)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pop(context, result.videoId),
        );
      },
    );
  }
}
