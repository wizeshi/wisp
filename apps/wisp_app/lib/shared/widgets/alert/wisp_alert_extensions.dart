// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert.dart';
import 'package:wisp/shared/widgets/alert/wisp_toast_host.dart';

/// Extension methods on [BuildContext] for displaying MUI-style alert toasts.
extension WispAlertContextX on BuildContext {
  /// Displays a customizable alert toast on the active [WispToastHost].
  void showAlert({
    required String message,
    String? title,
    AlertSeverity severity = AlertSeverity.info,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    if (!mounted) return;
    final manager = WispToastHost.maybeOf(this);
    manager?.show(
      message: message,
      title: title,
      severity: severity,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Displays a success alert toast.
  void showSuccessAlert(
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    showAlert(
      message: message,
      title: title,
      severity: AlertSeverity.success,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Displays an error alert toast.
  void showErrorAlert(
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    showAlert(
      message: message,
      title: title,
      severity: AlertSeverity.error,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Displays a warning alert toast.
  void showWarningAlert(
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    showAlert(
      message: message,
      title: title,
      severity: AlertSeverity.warning,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Displays an informational alert toast.
  void showInfoAlert(
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    showAlert(
      message: message,
      title: title,
      severity: AlertSeverity.info,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }
}

