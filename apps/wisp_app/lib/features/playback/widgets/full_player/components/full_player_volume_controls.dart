// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;

class FullPlayerVolumeQuickPanel extends StatelessWidget {
  final Rect anchorRect;
  final Size overlaySize;
  final Color accentColor;
  final VoidCallback onToggleMute;

  const FullPlayerVolumeQuickPanel({
    super.key,
    required this.anchorRect,
    required this.overlaySize,
    required this.accentColor,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    const panelWidth = 228.0;
    const panelHeight = 72.0;
    const margin = 8.0;

    final left = (anchorRect.right - panelWidth).clamp(
      margin,
      overlaySize.width - panelWidth - margin,
    );
    final top = (anchorRect.top - panelHeight - margin).clamp(
      margin,
      overlaySize.height - panelHeight - margin,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: panelWidth,
          height: panelHeight,
          child: Material(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(12),
            elevation: 10,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                child: Selector<global_audio_player.WispAudioHandler, double>(
                  selector: (context, player) => player.volume,
                  builder: (context, volume, child) {
                    final audio = context
                        .read<global_audio_player.WispAudioHandler>();
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: volume <= 0.001 ? 'Unmute' : 'Mute',
                          onPressed: onToggleMute,
                          icon: Icon(
                            volume <= 0.001
                                ? Icons.volume_off
                                : volume < 0.5
                                ? Icons.volume_down
                                : Icons.volume_up,
                            color: Colors.grey[300],
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        Expanded(
                          child: FullPlayerHoverVolumeSlider(
                            value: volume,
                            onChanged: (value) => audio.setVolume(value),
                            primaryColor: accentColor,
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${(volume * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FullPlayerHoverVolumeSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final Color primaryColor;

  const FullPlayerHoverVolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.primaryColor,
  });

  @override
  State<FullPlayerHoverVolumeSlider> createState() =>
      _FullPlayerHoverVolumeSliderState();
}

class _FullPlayerHoverVolumeSliderState
    extends State<FullPlayerHoverVolumeSlider> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = _isHovering ? widget.primaryColor : Colors.grey[500]!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: activeColor,
          inactiveTrackColor: Colors.grey[700],
          thumbColor: Colors.white,
          overlayColor: widget.primaryColor.withValues(alpha: 0.2),
        ),
        child: Slider(
          min: 0,
          max: 1,
          value: widget.value,
          divisions: 100,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

