// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';

/// Severity types for [WispAlert], mirroring standard MUI severity levels.
enum AlertSeverity {
  info,
  success,
  warning,
  error;

  Color get color => colorFor(Brightness.dark);

  Color get backgroundColor => backgroundColorFor(Brightness.dark);

  Color get borderColor => borderColorFor(Brightness.dark);

  Color colorFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return switch (this) {
        AlertSeverity.info => const Color(0xFF0277BD),
        AlertSeverity.success => const Color(0xFF2E7D32),
        AlertSeverity.warning => const Color(0xFFED6C02),
        AlertSeverity.error => const Color(0xFFD32F2F),
      };
    }
    return switch (this) {
      AlertSeverity.info => const Color(0xFF29B6F6),
      AlertSeverity.success => const Color(0xFF66BB6A),
      AlertSeverity.warning => const Color(0xFFFFA726),
      AlertSeverity.error => const Color(0xFFEF5350),
    };
  }

  Color backgroundColorFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return switch (this) {
        AlertSeverity.info => const Color(0xFFE8F4FD),
        AlertSeverity.success => const Color(0xFFEDF7ED),
        AlertSeverity.warning => const Color(0xFFFFF4E5),
        AlertSeverity.error => const Color(0xFFFDEDED),
      };
    }
    return switch (this) {
      AlertSeverity.info => const Color(0xFF0D2538),
      AlertSeverity.success => const Color(0xFF0E2E1A),
      AlertSeverity.warning => const Color(0xFF2D200E),
      AlertSeverity.error => const Color(0xFF2D1414),
    };
  }

  Color borderColorFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return switch (this) {
        AlertSeverity.info => const Color(0xFF90CAF9),
        AlertSeverity.success => const Color(0xFFA5D6A7),
        AlertSeverity.warning => const Color(0xFFFFCC80),
        AlertSeverity.error => const Color(0xFFEF9A9A),
      };
    }
    return switch (this) {
      AlertSeverity.info => const Color(0xFF1E4976),
      AlertSeverity.success => const Color(0xFF1E5230),
      AlertSeverity.warning => const Color(0xFF593C16),
      AlertSeverity.error => const Color(0xFF5E2121),
    };
  }

  IconData get defaultIcon => switch (this) {
        AlertSeverity.info => Icons.info_outline,
        AlertSeverity.success => Icons.check_circle_outline,
        AlertSeverity.warning => Icons.warning_amber_rounded,
        AlertSeverity.error => Icons.error_outline,
      };
}

/// An MUI-style alert notification card with modern dark tonal surface,
/// severity coloring, optional title, action button, and close icon.
class WispAlert extends StatelessWidget {
  final String message;
  final String? title;
  final AlertSeverity severity;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  const WispAlert({
    super.key,
    required this.message,
    this.title,
    this.severity = AlertSeverity.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = colors.brightness;
    final effectiveIcon = icon ?? severity.defaultIcon;
    final accentColor = severity.colorFor(brightness);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: severity.backgroundColorFor(brightness),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: severity.borderColorFor(brightness),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: colors.isDark ? 0.35 : 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              effectiveIcon,
              size: 20,
              color: accentColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title!.isNotEmpty) ...[
                    Text(
                      title!,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message,
                    style: TextStyle(
                      color: colors.isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : colors.textPrimary.withValues(alpha: 0.88),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      actionLabel!.toUpperCase(),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (onClose != null) ...[
              const SizedBox(width: 4),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

