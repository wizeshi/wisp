import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/services/connect/connect_packet_models.dart';

import '../../providers/connect/connect_session_provider.dart';
import '../../services/connect/connect_models.dart';

class ConnectMenu extends StatelessWidget {
  final VoidCallback onClose;
  final ScrollController? scrollController;
  final bool compact;

  const ConnectMenu({
    super.key,
    required this.onClose,
    this.scrollController,
    this.compact = false,
  });

  Future<void> _showSecurityRetryDialog(
    BuildContext context,
    ConnectSessionProvider connect,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Request Failed'),
          content: const Text(
            "Target device's connection security level is too low. Retry with lower, but equal, level security?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                connect.retryRejectedPairingWithLowerSecurity();
              },
              child: const Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Consumer<ConnectSessionProvider>(
      builder: (context, connect, child) {
        final devices = connect.discoveredDevices
            .where((device) => device.id != connect.localDeviceId)
            .toList();
        final availableOutputs = connect.availableOutputDevices;
        final hasExternalOutputs = availableOutputs.any(
          (device) => device.kind != ConnectOutputKind.local,
        );
        final errorMessage = connect.errorMessage;
        final securityRetryError =
          connect.errorCode == ConnectErrorCode.securityLevelTooLow;

        bool isCurrentOutput(ConnectOutputDevice device) {
          if (device.kind != connect.activeOutputKind) {
            return false;
          }
          if (device.kind == ConnectOutputKind.local) {
            return true;
          }
          final activeName = (connect.activeOutputDeviceName ?? '').trim();
          final deviceName = (device.name ?? '').trim();
          if (activeName.isNotEmpty && deviceName.isNotEmpty) {
            return activeName.toLowerCase() == deviceName.toLowerCase();
          }
          return true;
        }

        final outputDevices = availableOutputs
            .where(
              (device) => hasExternalOutputs ||
                  device.kind != ConnectOutputKind.local,
            )
            .where((device) => !isCurrentOutput(device))
            .toList();

        return Container(
          color: const Color(0xFF111111),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectMenuHeader(
                onClose: onClose,
                accent: accent,
                compact: compact,
              ),
              const SizedBox(height: 4),
              if (connect.hasPendingSecurityWarning)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _ConnectNoticeCard(
                    accent: Colors.amber,
                    icon: Icons.info_outline,
                    title: 'Security warning',
                    message: connect.pendingSecurityWarningMessage!,
                    actionLabel: 'Dismiss',
                    onAction: connect.clearPendingSecurityWarning,
                  ),
                ),
              if (connect.hasPendingSecurityWarning)
                const SizedBox(height: 12),
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _ConnectNoticeCard(
                    accent: Colors.redAccent,
                    icon: Icons.error_outline,
                    title: 'Request Failed',
                    message: errorMessage,
                    actionLabel:
                        securityRetryError ? 'Retry' : 'Dismiss',
                    onAction: securityRetryError
                        ? () => _showSecurityRetryDialog(context, connect)
                        : connect.clearErrorMessage,
                  ),
                ),
              if (errorMessage != null)
                const SizedBox(height: 12),
              if (connect.pendingPairRequest != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _PendingPairRequestCard(
                    connect: connect,
                    accent: accent,
                    request: connect.pendingPairRequest!,
                  ),
                ),
              if (connect.pendingPairRequest != null)
                const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _CurrentOutputCard(
                  connect: connect,
                  accent: accent,
                  compact: compact,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _HandoffModeSection(connect: connect, accent: accent),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  children: [
                    const _ListSectionLabel(text: 'Audio outputs'),
                    const SizedBox(height: 8),
                    if (outputDevices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ListInlineEmpty(
                          accent: accent,
                          text: 'No other audio outputs are available.',
                        ),
                      ),
                    ...outputDevices.map(
                      (outputDevice) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OutputDeviceCard(
                          connect: connect,
                          accent: accent,
                          device: outputDevice,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _ListSectionLabel(text: 'Handoff devices'),
                    const SizedBox(height: 8),
                    if (devices.isEmpty)
                      _ListInlineEmpty(
                        accent: accent,
                        text: 'No handoff devices found on this network.',
                      )
                    else
                      ...devices.map((device) {
                        final isSelected = connect.linkedDeviceId == device.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DeviceCard(
                            device: device,
                            selected: isSelected,
                            accent: accent,
                            onTap: () {
                              if (isSelected) {
                                connect.unlink(localResumed: true);
                                return;
                              }

                              // If a pairing request for this device is already pending,
                              // treat tap as cancel; otherwise begin pairing.
                              if (connect.pairingTargetDeviceId == device.id &&
                                  connect.phase == ConnectPhase.pairing) {
                                connect.cancelPairing();
                                return;
                              }

                              connect.beginPairing(
                                device.id,
                                mode: connect.nextOutgoingLinkMode,
                                rememberForDevice:
                                    connect.rememberModeForNextLink,
                              );
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectMenuHeader extends StatelessWidget {
  final VoidCallback onClose;
  final Color accent;
  final bool compact;

  const _ConnectMenuHeader({
    required this.onClose,
    required this.accent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, compact ? 8 : 16, 10, 10),
      child: Column(
        children: [
          if (compact) ...[
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(Icons.cast_connected, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Connect',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!compact)
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentOutputCard extends StatelessWidget {
  final ConnectSessionProvider connect;
  final Color accent;
  final bool compact;

  const _CurrentOutputCard({
    required this.connect,
    required this.accent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final outputKind = connect.activeOutputKind;
    final outputName = connect.activeOutputDeviceName;
    final subtitle = outputKind == ConnectOutputKind.local
        ? 'This Device'
        : switch (outputKind) {
            ConnectOutputKind.wired => 'Wired connection',
            ConnectOutputKind.bluetooth => 'Bluetooth audio',
            ConnectOutputKind.handoffDesktop => 'Handoff on desktop',
            ConnectOutputKind.handoffMobile => 'Handoff on mobile',
            ConnectOutputKind.local => 'This Device',
          };
    final title = outputKind == ConnectOutputKind.local
        ? connect.localDeviceName
        : (outputName ?? outputKind.label);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          _OutputIcon(kind: outputKind, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh devices',
            onPressed: connect.refreshConnectMenuData,
            icon: Icon(Icons.refresh, color: Colors.grey[200], size: 20),
          ),
          if (connect.isLinked)
            TextButton(
              onPressed: () => connect.unlink(localResumed: true),
              child: const Text('Unlink'),
            )
          else if (outputKind != ConnectOutputKind.local)
            TextButton(
              onPressed: () =>
                  connect.setActiveOutputDestination(ConnectOutputKind.local),
              child: const Text('Use this device'),
            ),
        ],
      ),
    );
  }
}

class _ListSectionLabel extends StatelessWidget {
  final String text;

  const _ListSectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.grey[350],
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ListInlineEmpty extends StatelessWidget {
  final Color accent;
  final String text;

  const _ListInlineEmpty({required this.accent, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering_off, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectNoticeCard extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _ConnectNoticeCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputDeviceCard extends StatelessWidget {
  final ConnectSessionProvider connect;
  final Color accent;
  final ConnectOutputDevice device;

  const _OutputDeviceCard({
    required this.connect,
    required this.accent,
    required this.device,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        connect.activeOutputKind == device.kind &&
        (device.kind == ConnectOutputKind.local ||
            connect.activeOutputDeviceName == device.name);
    final title = device.kind == ConnectOutputKind.local
        ? connect.localDeviceName
        : (device.name ?? device.kind.label);
    final subtitle = device.kind == ConnectOutputKind.local
        ? 'This Device'
        : device.kind.label;

    return Material(
      color: selected
          ? accent.withValues(alpha: 0.18)
          : const Color(0xFF1B1B1B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => connect.setActiveOutputDestination(
          device.kind,
          deviceName: device.name,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.6) : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              _OutputIcon(kind: device.kind, accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accent : Colors.grey[400],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                color: selected ? accent : Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandoffModeSection extends StatelessWidget {
  final ConnectSessionProvider connect;
  final Color accent;

  const _HandoffModeSection({required this.connect, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Handoff mode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<ConnectLinkMode>(
            style: ButtonStyle(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.selected)
                      ? accent
                      : Colors.white24,
                ),
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : Colors.grey[300],
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? accent.withValues(alpha: 0.92)
                    : Colors.transparent,
              ),
            ),
            segments: const [
              ButtonSegment<ConnectLinkMode>(
                value: ConnectLinkMode.fullHandoff,
                label: Text('Full handoff'),
              ),
              ButtonSegment<ConnectLinkMode>(
                value: ConnectLinkMode.controlOnly,
                label: Text('Controls only'),
              ),
            ],
            selected: {connect.nextOutgoingLinkMode},
            onSelectionChanged: (selection) {
              connect.setNextOutgoingLinkMode(selection.first);
            },
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final ConnectDevice device;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.device,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final platform = device.platform.trim().toLowerCase();

    return Material(
      color: selected
          ? accent.withValues(alpha: 0.18)
          : const Color(0xFF1B1B1B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.6) : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              _OutputIcon(kind: _kindFromPlatform(platform), accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selected ? 'Connected' : device.platform,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accent : Colors.grey[400],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Consumer<ConnectSessionProvider>(
                builder: (context, connect, child) {
                  final isPairingThisDevice =
                      connect.pairingTargetDeviceId == device.id &&
                          connect.phase == ConnectPhase.pairing;
                  if (!isPairingThisDevice) {
                    return Icon(
                      selected ? Icons.check_circle : Icons.chevron_right,
                      color: selected ? accent : Colors.white70,
                    );
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.white70,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          connect.cancelPairing();
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingPairRequestCard extends StatelessWidget {
  final ConnectSessionProvider connect;
  final Color accent;
  final ConnectPairRequest request;

  const _PendingPairRequestCard({
    required this.connect,
    required this.accent,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final modeLabel = request.requestedMode == ConnectLinkMode.fullHandoff
        ? 'Full handoff'
        : 'Controls only';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.call_received, color: accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incoming handoff request',
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'from ${request.fromDeviceName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              modeLabel,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: connect.rejectIncomingPair,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: connect.acceptIncomingPair,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutputIcon extends StatelessWidget {
  final ConnectOutputKind kind;
  final Color accent;

  const _OutputIcon({required this.kind, required this.accent});

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      ConnectOutputKind.wired => Icons.headphones,
      ConnectOutputKind.bluetooth => Icons.hearing,
      ConnectOutputKind.handoffMobile => Icons.smartphone,
      ConnectOutputKind.handoffDesktop => Icons.computer,
      ConnectOutputKind.local => Icons.play_circle_outline,
    };

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: kind.isExternal ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: accent, size: 20),
    );
  }
}

ConnectOutputKind _kindFromPlatform(String platform) {
  if (platform.contains('android') || platform.contains('ios')) {
    return ConnectOutputKind.handoffMobile;
  }
  if (platform.contains('windows') ||
      platform.contains('macos') ||
      platform.contains('linux')) {
    return ConnectOutputKind.handoffDesktop;
  }
  return ConnectOutputKind.handoffDesktop;
}
