// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:wisp/data/models/metadata_models.dart';

/// A dev-mode panel that dumps the full in-memory state of a [GenericSong] in
/// a readable, copy-friendly format. Only shown when debug mode is enabled in
/// settings — never rendered in production builds by the callers that guard it.
class TrackInspectDialog extends StatelessWidget {
  final GenericSong track;

  const TrackInspectDialog({super.key, required this.track});

  /// Convenience launcher — shows a bottom sheet on mobile, and a compact
  /// dialog on desktop/tablet.
  static Future<void> show(BuildContext context, GenericSong track) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    if (isNarrow) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TrackInspectDialog(track: track),
      );
    }
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: TrackInspectDialog(track: track),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = _buildFields();
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      constraints: const BoxConstraints(maxHeight: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Icon(Icons.code, size: 16, color: primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Inspect Element',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey[800], height: 1),
          // Fields list
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: fields.length,
              separatorBuilder: (_, __) =>
                  Divider(color: Colors.grey[900], height: 1, indent: 20),
              itemBuilder: (context, i) => _FieldRow(
                field: fields[i],
                primaryColor: primaryColor,
              ),
            ),
          ),
          Divider(color: Colors.grey[800], height: 1),
          // Copy all button
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('Copy all as JSON'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[400],
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () async {
                final json = _buildJsonString();
                await Clipboard.setData(ClipboardData(text: json));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Track data copied to clipboard')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_InspectField> _buildFields() {
    final album = track.album;
    return [
      _InspectField('title', track.title),
      _InspectField('id', track.id),
      _InspectField('source', track.source),
      _InspectField(
        'artists',
        track.artists.isEmpty
            ? '(none)'
            : track.artists.map((a) => '${a.name} [${a.id}]').join(', '),
      ),
      _InspectField(
        'album',
        album == null
            ? '(none)'
            : '${album.title} [${album.id}] · ${album.source}',
      ),
      _InspectField('duration', _formatDuration(track.durationSecs)),
      _InspectField('explicit', track.explicit.toString()),
      _InspectField(
        'languages',
        track.languages?.join(', ') ?? '(none)',
      ),
      _InspectField(
        'thumbnailUrl',
        track.thumbnailUrl.isEmpty ? '(empty)' : track.thumbnailUrl,
        isUrl: track.thumbnailUrl.isNotEmpty,
      ),
      if (album != null) ...[
        _InspectField('album.releaseDate', album.releaseDate.toLocal().toIso8601String().split('T').first),
        _InspectField('album.label', album.label.isEmpty ? '(empty)' : album.label),
        _InspectField(
          'album.artists',
          album.artists.isEmpty
              ? '(none)'
              : album.artists.map((a) => a.name).join(', '),
        ),
      ],
    ];
  }

  String _formatDuration(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} ($secs s)';
    }
    return '$m:${s.toString().padLeft(2, '0')} ($secs s)';
  }

  String _buildJsonString() {
    final map = track.toJson();
    final buf = StringBuffer('{\n');
    map.forEach((key, value) {
      buf.write('  "$key": ${_jsonValue(value)},\n');
    });
    buf.write('}');
    return buf.toString();
  }

  String _jsonValue(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return '"$v"';
    if (v is bool || v is num) return v.toString();
    if (v is List) {
      if (v.isEmpty) return '[]';
      final items = v.map(_jsonValue).join(', ');
      return '[$items]';
    }
    if (v is Map) {
      final pairs = v.entries.map((e) => '"${e.key}": ${_jsonValue(e.value)}').join(', ');
      return '{$pairs}';
    }
    return '"$v"';
  }
}

class _InspectField {
  final String key;
  final String value;
  final bool isUrl;

  const _InspectField(this.key, this.value, {this.isUrl = false});
}

class _FieldRow extends StatelessWidget {
  final _InspectField field;
  final Color primaryColor;

  const _FieldRow({required this.field, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: field.value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${field.key}" copied to clipboard')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                field.key,
                style: TextStyle(
                  color: primaryColor.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                field.value,
                style: TextStyle(
                  color: field.isUrl ? Colors.blue[300] : Colors.grey[300],
                  fontSize: 11,
                  fontFamily: 'monospace',
                  decoration:
                      field.isUrl ? TextDecoration.underline : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.copy,
              size: 12,
              color: Colors.grey[700],
            ),
          ],
        ),
      ),
    );
  }
}
