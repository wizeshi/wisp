import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';
import 'package:wisp/shared/widgets/display/marquee_text.dart';
import 'package:wisp_audio_output_info/models/types.dart';

class ConnectDeviceIndicator extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    bool showConnectStatus,
    Widget connectStatusWidget,
  )
  builder;
  final double? height;
  final Color? iconColor;
  final Color? textColor;

  const ConnectDeviceIndicator({
    super.key,
    required this.builder,
    this.height,
    this.iconColor,
    this.textColor,
  });

  @override
  State<ConnectDeviceIndicator> createState() => _ConnectDeviceIndicatorState();
}

class _ConnectDeviceIndicatorState extends State<ConnectDeviceIndicator> {
  bool showConnectStatus = false;

  String? deviceName;

  IconData? deviceIcon;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isHandoffConnected = context.select<ConnectSessionProvider, bool>(
      (provider) => provider.activeConnectionKind == ConnectionKind.handoff,
    );

    if (isHandoffConnected) {
      // User is using Handoff to connect to a device.
      final handoffDeviceType = context
          .select<ConnectSessionProvider, HandoffDeviceType?>(
            (provider) => provider.linkedDeviceType,
          );

      final handoffDevice = context.select<ConnectSessionProvider, String?>(
        (provider) => provider.linkedPeerName,
      );

      deviceName = handoffDevice ?? deviceName;

      switch (handoffDeviceType) {
        case HandoffDeviceType.desktop:
          deviceIcon = Icons.computer;
          break;
        case HandoffDeviceType.mobile:
          deviceIcon = Icons.phone_android;
          break;
        case null:
          break;
      }

      showConnectStatus = true;
    } else {
      // User is not using Handoff, check for alternative audio output.
      final isUsingAlternativeAudioOutput = context
          .select<ConnectSessionProvider, bool>(
            (provider) => provider.activeConnectionKind == ConnectionKind.audio,
          );

      if (isUsingAlternativeAudioOutput) {
        final audioDevice = context
            .select<ConnectSessionProvider, AudioOutputDevice?>(
              (provider) => provider.activeAudioOutputDevice,
            );

        if (audioDevice != null) {
          deviceName = audioDevice.name ?? deviceName;

          switch (audioDevice.kind) {
            case AudioOutputKind.speakers:
              deviceIcon = Icons.speaker;
              break;
            case AudioOutputKind.headphones:
              deviceIcon = Icons.headphones;
              break;
            case AudioOutputKind.headset:
              deviceIcon = Icons.headset;
              break;
            case AudioOutputKind.earbuds:
              deviceIcon = Icons.headphones;
              break;
            case AudioOutputKind.hearingAid:
              deviceIcon = Icons.hearing;
              break;
            case AudioOutputKind.receiver:
              deviceIcon = Icons.speaker_phone;
              break;
            case AudioOutputKind.amplifier:
              deviceIcon = Icons.speaker;
              break;
            case AudioOutputKind.soundbar:
              deviceIcon = Icons.speaker;
              break;
            case AudioOutputKind.television:
              deviceIcon = Icons.tv;
              break;
            case AudioOutputKind.lineOut:
              deviceIcon = Icons.speaker;
              break;
            case AudioOutputKind.digitalOut:
              deviceIcon = Icons.speaker;
              break;
            case AudioOutputKind.hdmi:
              deviceIcon = Icons.tv;
              break;
            case AudioOutputKind.displayPort:
              deviceIcon = Icons.tv;
              break;
            case AudioOutputKind.virtual:
              deviceIcon = Icons.speaker;
              break;
            case AudioOutputKind.remote:
              deviceIcon = Icons.speaker;
              break;
            case AudioOutputKind.unknown:
              deviceIcon = Icons.question_mark;
              break;
          }
        }

        showConnectStatus = true;
      } else {
        // User is not using Handoff or alternative audio output.
        deviceName = null;
        deviceIcon = null;
        showConnectStatus = false;
      }
    }

    final defaultHeight = 17.0;

    final height = widget.height ?? defaultHeight;

    final iconSizeMultiplier = 16 * (height / defaultHeight);
    final textHeightMultiplier = 12 * (height / defaultHeight);

    return widget.builder(
      context,
      showConnectStatus,
      Row(
        children: [
          Icon(
            deviceIcon,
            color: widget.iconColor ?? Colors.white,
            size: iconSizeMultiplier,
          ),
          const SizedBox(width: 4),
          MarqueeText(
            text: deviceName ?? "",
            style: TextStyle(
              color: widget.textColor ?? Colors.white,
              fontSize: textHeightMultiplier,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
