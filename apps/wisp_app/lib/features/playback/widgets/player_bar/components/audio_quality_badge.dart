// Copyright © 2026 wizeshi

library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';

/// Compact, interactive audio quality pill badge in the player bar.
///
/// Tapping opens an anchored pop-up bubble above the badge displaying
/// resolved source stream parameters (Format, Bit Depth, Sample Rate, Provider)
/// alongside playback engine output parameters (Engine Bitrate and Sample Rate).
class AudioQualityBadge extends StatefulWidget {
  final Widget child;
  final Color preferredColor;

  const AudioQualityBadge({super.key, required this.child, required this.preferredColor});

  @override
  State<AudioQualityBadge> createState() => _AudioQualityBadgeState();
}

class _AudioQualityBadgeState extends State<AudioQualityBadge> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final badgeOffset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final screenSize = MediaQuery.of(context).size;

    const bubbleWidth = 270.0;
    // Keep at least 12px padding from left/right edges of screen
    final leftPos = (badgeOffset.dx - (bubbleWidth / 3)).clamp(
      12.0,
      (screenSize.width - bubbleWidth - 12.0).clamp(12.0, double.infinity),
    );
    // Position 8px above the badge top
    final bottomPos = screenSize.height - badgeOffset.dy + 8.0;

    final theme = Theme.of(context);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Dismiss on tapping outside
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _removeOverlay,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // Anchored popup bubble above badge, safely clamped within screen bounds
          Positioned(
            left: leftPos,
            bottom: bottomPos,
            width: bubbleWidth,
            child: Theme(
              data: theme,
              child: Material(
                color: Colors.transparent,
                child: _QualityInfoBubble(
                  onClose: _removeOverlay,
                  primaryColor: widget.preferredColor
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggleOverlay,
          child: widget.child
        ),
      ),
    );
  }
}

class _QualityInfoBubble extends StatelessWidget {
  final VoidCallback onClose;
  final Color primaryColor;

  const _QualityInfoBubble({required this.onClose, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<WispAudioHandler>(
      builder: (context, handler, _) {
        final quality = handler.activeTrackQuality;
        final engineBitrate = handler.audioBitrate;
        final engineSampleRate = handler.audioSampleRate;

        final sourceBitDepth = quality?.bitDepth;
        final sourceSampleRate = quality?.sampleRate;
        final sourceFormat = quality?.format ?? 'M4A / AAC';
        final providerName = quality?.providerName ?? 'Audio Source';

        // Format source kHz string
        String? sourceKHz;
        if (sourceSampleRate != null && sourceSampleRate > 0) {
          final khzVal = sourceSampleRate / 1000.0;
          sourceKHz = '${khzVal.toStringAsFixed(khzVal % 1 == 0 ? 0 : 1)} kHz';
        }

        // Format engine kHz string
        String? engineKHz;
        if (engineSampleRate != null && engineSampleRate > 0) {
          final khzVal = engineSampleRate / 1000.0;
          engineKHz = '${khzVal.toStringAsFixed(khzVal % 1 == 0 ? 0 : 1)} kHz';
        }

        // Engine bitrate string
        String? engineKbps;
        if (engineBitrate != null && engineBitrate > 0) {
          engineKbps = '${(engineBitrate / 1000).floor()} kbps';
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.graphic_eq, size: 15, color: primaryColor),
                      const SizedBox(width: 6),
                      Text(
                        'AUDIO FIDELITY',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 10),

              // Source Stream Section
              Text(
                'Source Stream ($providerName)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _buildMetricRow(label: 'Container / Codec', value: sourceFormat),
              if (sourceBitDepth != null && sourceBitDepth > 0)
                _buildMetricRow(
                  label: 'Bit Depth',
                  value: '$sourceBitDepth-bit',
                  accent: sourceBitDepth >= 24,
                  accentColor: primaryColor,
                ),
              if (sourceKHz != null)
                _buildMetricRow(
                  label: 'Sample Rate',
                  value: sourceKHz,
                  accent: (sourceSampleRate ?? 0) > 48000,
                  accentColor: primaryColor,
                ),
              if (quality?.bitrate != null && quality!.bitrate! > 0)
                _buildMetricRow(
                  label: 'Nominal Bitrate',
                  value: '${quality.bitrate} kbps',
                ),

              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 10),

              // Engine Output Section
              const Text(
                'Playback Engine Output',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (engineKbps != null)
                _buildMetricRow(label: 'Rendered Bitrate', value: engineKbps),
              if (engineKHz != null)
                _buildMetricRow(label: 'Output Rate', value: engineKHz),

              if (engineKbps == null && engineKHz == null)
                Text(
                  'Engine telemetry syncing...',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricRow({
    required String label,
    required String value,
    bool accent = false,
    Color? accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
          ),
          Text(
            value,
            style: TextStyle(
              color: accent ? (accentColor ?? Colors.white) : Colors.white,
              fontSize: 11.5,
              fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
