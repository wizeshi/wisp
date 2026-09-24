// Copyright © 2026 wizeshi

import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/system/app_focus_service.dart';

class RotatingBlurredCoverBackground extends StatefulWidget {
  final String imageUrl;

  const RotatingBlurredCoverBackground({super.key, required this.imageUrl});

  @override
  State<RotatingBlurredCoverBackground> createState() =>
      _RotatingBlurredCoverBackgroundState();
}

class _RotatingBlurredCoverBackgroundState
    extends State<RotatingBlurredCoverBackground>
    with SingleTickerProviderStateMixin, WindowListener {
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 50),
  );

  bool _isMinimized = false;

  // Whether the "freeze while unfocused" behavior is turned on for this
  // widget, per the user's preference. Kept in sync from build().
  bool _freezeWhenUnfocused = false;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  /// Whether the rotation should be running: not minimized, and either the
  /// freeze-when-unfocused preference is off or the app/window currently has
  /// focus (covers window blur on desktop and backgrounding on mobile,
  /// freezing this expensive blurred background whenever it isn't visible).
  bool get _shouldAnimate =>
      !_isMinimized &&
      (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value);

  @override
  void initState() {
    super.initState();
    _rotationController.repeat();
    AppFocusService.instance.isFocused.addListener(_syncAnimationState);
    if (_isDesktop) {
      windowManager.addListener(this);
      _syncMinimizedState();
    }
  }

  Future<void> _syncMinimizedState() async {
    try {
      final minimized = await windowManager.isMinimized();
      if (!mounted) return;
      _isMinimized = minimized;
      _syncAnimationState();
    } catch (_) {}
  }

  void _syncAnimationState() {
    if (!mounted) return;
    if (_shouldAnimate) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      _rotationController.stop(canceled: false);
    }
  }

  @override
  void onWindowMinimize() {
    _isMinimized = true;
    _syncAnimationState();
  }

  @override
  void onWindowRestore() {
    _isMinimized = false;
    _syncAnimationState();
  }

  @override
  void dispose() {
    AppFocusService.instance.isFocused.removeListener(_syncAnimationState);
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.rotatingAlbumArtFullScreen,
      ),
    );
    if (freezeWhenUnfocused != _freezeWhenUnfocused) {
      _freezeWhenUnfocused = freezeWhenUnfocused;
      _syncAnimationState();
    }

    if (widget.imageUrl.isEmpty) {
      return Container(color: const Color(0xFF101010));
    }

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final maxSide = width > height ? width : height;
          final imageSize = maxSide * 2.4;

          return ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
                AnimatedBuilder(
                  animation: _rotationController,
                  builder: (context, child) {
                    final angle = _rotationController.value * 6.283185307179586;
                    final centerX = width;
                    final centerY = 0.0;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: centerX - (imageSize / 2),
                          top: centerY - (imageSize / 2),
                          width: imageSize,
                          height: imageSize,
                          child: Transform.rotate(angle: angle, child: child!),
                        ),
                      ],
                    );
                  },
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

