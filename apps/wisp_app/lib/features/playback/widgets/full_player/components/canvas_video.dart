// Copyright © 2026 wizeshi

import 'dart:async' show unawaited;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/system/app_focus_service.dart';

class CanvasVideo extends StatefulWidget {
  final String url;
  final String fallbackUrl;

  const CanvasVideo({
    super.key,
    required this.url,
    required this.fallbackUrl,
  });

  @override
  State<CanvasVideo> createState() => _CanvasVideoState();
}

class _CanvasVideoState extends State<CanvasVideo> {
  VideoPlayerController? _controller;
  bool _initFailed = false;
  bool? _lastShouldPlay;

  // Whether the "freeze while unfocused" behavior is turned on for this
  // widget, per the user's preference. Kept in sync from build(). Reuses
  // the "Animated Canvas - Sidebar" preference since it's the only canvas
  // toggle exposed, covering this fullscreen instance too.
  bool _freezeWhenUnfocused = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant CanvasVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _initialize();
    }
  }

  @override
  void dispose() {
    AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    _disposeController();
    super.dispose();
  }

  void _handleFocusChanged() {
    // Re-evaluate play/pause immediately: no need to wait for a rebuild
    // driven by the playback provider to freeze/resume this animated canvas.
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    final shouldPlay =
        context.read<PlaybackCoordinator>().effectiveIsPlaying &&
        (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    _syncPlayback(controller, shouldPlay);
  }

  Future<void> _initialize() async {
    try {
      _initFailed = false;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      _initFailed = true;
      if (mounted) setState(() {});
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _lastShouldPlay = null;
  }

  void _syncPlayback(VideoPlayerController controller, bool shouldPlay) {
    if (_lastShouldPlay == shouldPlay) return;
    _lastShouldPlay = shouldPlay;
    unawaited(_setPlayback(controller, shouldPlay));
  }

  Future<void> _setPlayback(
    VideoPlayerController controller,
    bool shouldPlay,
  ) async {
    try {
      if (shouldPlay) {
        if (!controller.value.isPlaying) {
          await controller.play();
        }
      } else {
        if (controller.value.isPlaying) {
          await controller.pause();
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIsPlaying = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.effectiveIsPlaying,
    );
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.animatedCanvasSidebar,
      ),
    );
    _freezeWhenUnfocused = freezeWhenUnfocused;
    // Freeze this animated canvas (stop decoding/painting video frames)
    // whenever the app/window is unfocused and the user has enabled that
    // behavior for it, regardless of playback state.
    final shouldPlay =
        effectiveIsPlaying &&
        (!freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    final controller = _controller;
    if (_initFailed || controller == null || !controller.value.isInitialized) {
      return CachedNetworkImage(
        imageUrl: widget.fallbackUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) =>
            Container(color: Colors.grey[900]),
      );
    }

    _syncPlayback(controller, shouldPlay);

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

