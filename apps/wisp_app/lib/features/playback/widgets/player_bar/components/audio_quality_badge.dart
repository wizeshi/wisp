// Copyright © 2026 wizeshi

library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/sources/audio/models/audio_quality_info.dart';
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

  /// Opens the audio quality sheet on mobile or compact screens directly.
  static Future<void> showSheet(
    BuildContext context, {
    required Color preferredColor,
  }) {
    return QualityInfoSheet.show(context, primaryColor: preferredColor);
  }

  @override
  State<AudioQualityBadge> createState() => _AudioQualityBadgeState();
}

class _AudioQualityBadgeState extends State<AudioQualityBadge> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  bool get _isMobile {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return true;
    }
    return MediaQuery.sizeOf(context).width < 600;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _handleTap() {
    if (_isMobile) {
      _showSheet();
    } else {
      _toggleOverlay();
    }
  }

  void _showSheet() {
    _removeOverlay();
    QualityInfoSheet.show(
      context,
      primaryColor: widget.preferredColor,
    );
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
          onTap: _handleTap,
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
    return Selector<WispAudioHandler, (ActiveTrackQualityInfo?, double?, int?)>(
      selector: (context, handler) => (
        handler.activeTrackQuality,
        handler.audioBitrate,
        handler.audioSampleRate,
      ),
      builder: (context, data, _) {
        final quality = data.$1;
        final engineBitrate = data.$2;
        final engineSampleRate = data.$3;

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

        final colors = context.colors;
        return Container(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colors.borderSubtle,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
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
                          color: colors.textSecondary,
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
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: 10),

              // Source Stream Section
              Text(
                'Source Stream ($providerName)',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _buildMetricRow(context, label: 'Container / Codec', value: sourceFormat),
              if (sourceBitDepth != null && sourceBitDepth > 0)
                _buildMetricRow(
                  context,
                  label: 'Bit Depth',
                  value: '$sourceBitDepth-bit',
                  accent: sourceBitDepth >= 24,
                  accentColor: primaryColor,
                ),
              if (sourceKHz != null)
                _buildMetricRow(
                  context,
                  label: 'Sample Rate',
                  value: sourceKHz,
                  accent: (sourceSampleRate ?? 0) > 48000,
                  accentColor: primaryColor,
                ),
              if (quality?.bitrate != null && quality!.bitrate! > 0)
                _buildMetricRow(
                  context,
                  label: 'Nominal Bitrate',
                  value: '${quality.bitrate} kbps',
                ),

              const SizedBox(height: 10),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: 10),

              // Engine Output Section
              Text(
                'Playback Engine Output',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (engineKbps != null)
                _buildMetricRow(context, label: 'Rendered Bitrate', value: engineKbps),
              if (engineKHz != null)
                _buildMetricRow(context, label: 'Output Rate', value: engineKHz),

              if (engineKbps == null && engineKHz == null)
                Text(
                  'Engine telemetry syncing...',
                  style: TextStyle(
                    color: colors.textMuted,
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

  Widget _buildMetricRow(
    BuildContext context, {
    required String label,
    required String value,
    bool accent = false,
    Color? accentColor,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
          ),
          Text(
            value,
            style: TextStyle(
              color: accent
                  ? (accentColor ?? colors.textPrimary)
                  : colors.textPrimary,
              fontSize: 11.5,
              fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class QualityInfoSheet extends StatelessWidget {
  final VoidCallback onClose;
  final Color primaryColor;

  const QualityInfoSheet({
    super.key,
    required this.onClose,
    required this.primaryColor,
  });

  /// Displays the audio quality sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required Color primaryColor,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: context.colors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => QualityInfoSheet(
        onClose: () => Navigator.of(sheetContext).pop(),
        primaryColor: primaryColor,
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required String label,
    required String value,
    bool accent = false,
    Color? accentColor,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: accent
                  ? (accentColor ?? colors.textPrimary)
                  : colors.textPrimary,
              fontSize: 13,
              fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Selector<WispAudioHandler, (ActiveTrackQualityInfo?, double?, int?)>(
      selector: (_, handler) => (
        handler.activeTrackQuality,
        handler.audioBitrate,
        handler.audioSampleRate,
      ),
      builder: (context, data, _) {
        final quality = data.$1;
        final engineBitrate = data.$2;
        final engineSampleRate = data.$3;

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

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.graphic_eq, size: 16, color: primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'AUDIO FIDELITY',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    (Platform.isAndroid || Platform.isIOS)
                        ? const SizedBox.shrink() // No close button on mobile
                        : GestureDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: colors.borderSubtle),
                const SizedBox(height: 12),

                // Source Stream Section
                Text(
                  'Source Stream ($providerName)',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMetricRow(context, label: 'Container / Codec', value: sourceFormat),
                if (sourceBitDepth != null && sourceBitDepth > 0)
                  _buildMetricRow(
                    context,
                    label: 'Bit Depth',
                    value: '$sourceBitDepth-bit',
                    accent: sourceBitDepth >= 24,
                    accentColor: primaryColor,
                  ),
                if (sourceKHz != null)
                  _buildMetricRow(
                    context,
                    label: 'Sample Rate',
                    value: sourceKHz,
                    accent: (sourceSampleRate ?? 0) > 48000,
                    accentColor: primaryColor,
                  ),
                if (quality?.bitrate != null && quality!.bitrate! > 0)
                  _buildMetricRow(
                    context,
                    label: 'Nominal Bitrate',
                    value: '${quality.bitrate} kbps',
                  ),

                const SizedBox(height: 12),
                Divider(height: 1, color: colors.borderSubtle),
                const SizedBox(height: 12),

                // Playback Engine Output Section
                Text(
                  'Playback Engine Output',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (engineKbps != null)
                  _buildMetricRow(context, label: 'Rendered Bitrate', value: engineKbps),
                if (engineKHz != null)
                  _buildMetricRow(context, label: 'Output Rate', value: engineKHz),

                if (engineKbps == null && engineKHz == null)
                  Text(
                    'Engine telemetry syncing...',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}