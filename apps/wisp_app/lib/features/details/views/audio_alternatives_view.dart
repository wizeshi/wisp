// Copyright © 2026 wizeshi

library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:wisp/data/cache/audio/audio_mapping_store.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/audio/audio_source_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/shared/widgets/layout/mobile_bottom_padding.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

/// Selection result from the alternatives view.
class AudioAlternativeSelection {
  final String providerId;
  final String mediaId;
  final bool isClear;

  AudioAlternativeSelection({
    required this.providerId,
    required this.mediaId,
    this.isClear = false,
  });
}

class AudioAlternativesView extends StatefulWidget {
  final GenericSong track;

  const AudioAlternativesView({super.key, required this.track});

  @override
  State<AudioAlternativesView> createState() => _AudioAlternativesViewState();
}

class _AudioAlternativesViewState extends State<AudioAlternativesView> {
  final AudioSourceManager _sourceManager = AudioSourceManager.instance;
  final AudioMappingStore _mappingStore = AudioMappingStore.instance;

  String? _selectedProviderId;
  List<AudioTrackCandidate> _candidates = const [];
  bool _isLoading = true;
  String? _error;

  String get _artistNames => widget.track.artists.map((a) => a.name).join(', ');
  String get _canonicalKey => AudioMappingStore.canonicalKey(
        title: widget.track.title,
        artists: widget.track.artists.map((a) => a.name),
      );

  @override
  void initState() {
    super.initState();
    final prefs = context.read<PreferencesProvider>();
    final ordered = _sourceManager.getOrderedSources(prefs);
    if (ordered.isNotEmpty) {
      // If there's an existing mapping or override, start on that provider
      final existingMappings = _mappingStore.getMappings(_canonicalKey);
      final override = existingMappings.where((m) => m.manualOverride).firstOrNull;
      if (override != null && ordered.any((s) => s.id == override.providerID)) {
        _selectedProviderId = override.providerID;
      } else if (existingMappings.isNotEmpty &&
          ordered.any((s) => s.id == existingMappings.first.providerID)) {
        _selectedProviderId = existingMappings.first.providerID;
      } else {
        _selectedProviderId = ordered.first.id;
      }
    }
    _runSearch();
  }

  Future<void> _runSearch() async {
    final providerId = _selectedProviderId;
    if (providerId == null) {
      setState(() {
        _isLoading = false;
        _candidates = const [];
        _error = 'No audio provider selected';
      });
      return;
    }

    final source = _sourceManager.getSource(providerId);
    if (source == null) {
      setState(() {
        _isLoading = false;
        _candidates = const [];
        _error = 'Provider "$providerId" not found';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = AudioSearchQuery(
        title: widget.track.title,
        artists: widget.track.artists.map((a) => a.name).toList(),
        album: widget.track.album?.title,
        durationSecs: widget.track.durationSecs,
        trackId: widget.track.id,
        metadataSource: widget.track.source,
      );

      final candidates = await source.searchAudio(query);

      if (!mounted) return;
      setState(() {
        _candidates = candidates;
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
    final providerId = _selectedProviderId ?? 'youtube';
    final existing = _mappingStore.getMapping(_canonicalKey, providerId)?.mediaID ?? '';
    final controller = TextEditingController(text: existing);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Custom $providerId Media ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter a custom media/track ID for provider "$providerId". Leave empty to clear mapping.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: providerId == 'youtube' ? 'e.g., dQw4w9WgXcQ' : 'e.g., 12345678',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          GenericTextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          GenericElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true || !mounted) return;

    final trimmed = controller.text.trim();
    if (trimmed.isEmpty) {
      await _mappingStore.removeMapping(_canonicalKey, providerId: providerId);
      if (!mounted) return;
      Navigator.pop(
        context,
        AudioAlternativeSelection(providerId: providerId, mediaId: '', isClear: true),
      );
    } else {
      await _mappingStore.setMapping(
        _canonicalKey,
        AudioMappingItem(
          providerID: providerId,
          mediaID: trimmed,
          manualOverride: true,
        ),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        AudioAlternativeSelection(providerId: providerId, mediaId: trimmed),
      );
    }
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
    final prefs = context.watch<PreferencesProvider>();
    final availableSources = _sourceManager.getOrderedSources(prefs);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Audio Alternatives'),
        actions: [
          if (availableSources.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedProviderId,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                  dropdownColor: Theme.of(context).cardColor,
                  items: availableSources.map((s) {
                    return DropdownMenuItem<String>(
                      value: s.id,
                      child: Text(
                        s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                  onChanged: (newId) {
                    if (newId != null && newId != _selectedProviderId) {
                      setState(() {
                        _selectedProviderId = newId;
                      });
                      _runSearch();
                    }
                  },
                ),
              ),
            ),
        ],
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
            trailing: _buildCurrentMappingBadge(),
          ),
          Divider(height: 1, color: Colors.grey[700]),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget? _buildCurrentMappingBadge() {
    final mappings = _mappingStore.getMappings(_canonicalKey);
    final currentProviderId = _selectedProviderId;
    final currentMapping = mappings.where((m) => m.providerID == currentProviderId).firstOrNull;

    if (currentMapping == null) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: currentMapping.manualOverride ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: currentMapping.manualOverride ? Colors.green : Colors.white24,
          width: 1,
        ),
      ),
      child: Text(
        currentMapping.manualOverride ? 'Manual Override' : 'Mapped',
        style: TextStyle(
          fontSize: 11,
          color: currentMapping.manualOverride ? Colors.green : Colors.white70,
          fontWeight: FontWeight.bold,
        ),
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
              GenericFilledButton(onPressed: _runSearch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final providerId = _selectedProviderId ?? 'youtube';

    return ListView.separated(
      padding: EdgeInsets.only(
        bottom: mobileBottomBarPadding(context, extra: 16),
      ),
      itemCount: _candidates.length + 1,
      separatorBuilder: (ctx, index) =>
          Divider(height: 1, color: Colors.grey[900]),
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Use manual ID'),
            subtitle: Text('Enter a custom $providerId media ID manually'),
            onTap: _useManualId,
          );
        }

        final candidate = _candidates[index - 1];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 80,
              height: 45,
              child: candidate.thumbnailUrl != null
                  ? Image.network(
                      candidate.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, error, stackTrace) => const ColoredBox(
                        color: Colors.black12,
                        child: Icon(Icons.music_note),
                      ),
                    )
                  : const ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.music_note),
                    ),
            ),
          ),
          title: Text(
            candidate.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  '${candidate.artist} • ${_formatDuration(candidate.duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (candidate.qualityLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    candidate.qualityLabel!,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            // Save as manual override in canonical store
            await _mappingStore.setMapping(
              _canonicalKey,
              AudioMappingItem(
                providerID: candidate.providerId,
                mediaID: candidate.mediaId,
                manualOverride: true,
              ),
            );
            if (!context.mounted) return;
            Navigator.pop(
              context,
              AudioAlternativeSelection(
                providerId: candidate.providerId,
                mediaId: candidate.mediaId,
              ),
            );
          },
        );
      },
    );
  }
}

