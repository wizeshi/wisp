// Copyright © 2026 wizeshi

import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/core/theme/cover_art_palette_provider.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/playback/widgets/full_player/styles/desktop/original_full_player.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'full_player/styles/mobile/apple_music_full_player.dart';
import 'full_player/styles/mobile/original_full_player.dart';
import 'full_player/styles/desktop/spotify_full_player.dart';
import 'full_player/styles/mobile/spotify_full_player.dart';

// Re-export styles and components for external callers
export 'full_player/styles/mobile/apple_music_full_player.dart';
export 'full_player/styles/mobile/original_full_player.dart';
export 'full_player/styles/desktop/spotify_full_player.dart';
export 'full_player/styles/mobile/spotify_full_player.dart';
export 'full_player/components/canvas_video.dart';
export 'full_player/components/clickable_artist_names.dart';
export 'full_player/components/cover_gradient_container.dart';
export 'full_player/components/desktop_lyrics_preview.dart';
export 'full_player/components/full_player_lyrics_view.dart';
export 'full_player/components/full_player_volume_controls.dart';
export 'full_player/components/inline_delay_editor.dart';
export 'full_player/components/mobile_artist_info_card.dart';
export 'full_player/components/player_hero.dart';
export 'full_player/components/rotating_blurred_cover_background.dart';

class FullScreenPlayer extends StatelessWidget {
  const FullScreenPlayer({super.key});

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  static const Duration mobileTransitionDuration = Duration(milliseconds: 360);
  static const Duration mobileReverseTransitionDuration =
      Duration(milliseconds: 300);

  static Widget buildMobileTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child, {
    AppStyle? style,
  }) {
    AppStyle resolvedStyle = style ?? AppStyle.Original;
    if (style == null) {
      try {
        resolvedStyle = context.read<PreferencesProvider>().style;
      } catch (_) {}
    }

    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (resolvedStyle == AppStyle.AppleMusic) {
      return FadeTransition(
        opacity: curvedAnimation,
        child: child,
      );
    }

    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(curvedAnimation);

    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: child,
      ),
    );
  }

  static Route<void> buildMobileRoute({AppStyle? style}) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: mobileTransitionDuration,
      reverseTransitionDuration: mobileReverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const FullScreenPlayer(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          buildMobileTransition(
            context,
            animation,
            secondaryAnimation,
            child,
            style: style,
          ),
    );
  }

  static void show(BuildContext context) {
    if (NavigationService.instance.isInitialized) {
      unawaited(AppNavigation.instance.openFullPlayer());
      return;
    }
    Navigator.of(context, rootNavigator: true).push(buildMobileRoute());
  }

  @override
  Widget build(BuildContext context) {
    final style = context.select<PreferencesProvider, AppStyle>(
      (p) => p.style,
    );
    final darkPalette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (p) => p.darkPalette,
    );
    final darkTheme = AppTheme.dark(
      paletteOverride: darkPalette,
      appStyle: style,
    );

    final Widget body;
    // Use new desktop fullscreen for Spotify and Original on desktop
    if (_isDesktop && style == AppStyle.Spotify) {
      body = Material(
        type: MaterialType.transparency,
        child: PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) return;
            unawaited(AppNavigation.instance.disableFullPlayerDesktopMode());
          },
          child: const SpotifyDesktopFullScreenPlayer(),
        ),
      );
    } else if (_isDesktop && style == AppStyle.Original) {
      body = Material(
        type: MaterialType.transparency,
        child: PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) return;
            unawaited(AppNavigation.instance.disableFullPlayerDesktopMode());
          },
          child: const OriginalDesktopFullScreenPlayer(),
        ),
      );
    } else if (_isDesktop) {
      final sheet = DraggableScrollableSheet(
        initialChildSize: 1.0,
        minChildSize: 0.5,
        maxChildSize: 1.0,
        snap: true,
        snapSizes: const [0.5, 1.0],
        builder: (context, scrollController) =>
            _buildSheet(context, scrollController, style),
      );
      body = Material(
        type: MaterialType.transparency,
        child: PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) return;
            unawaited(AppNavigation.instance.disableFullPlayerDesktopMode());
          },
          child: sheet,
        ),
      );
    } else {
      body = Material(
        color: Colors.transparent,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: _DismissibleFullPlayerSheet(
            builder: (context, scrollController) =>
                _buildSheet(context, scrollController, style),
          ),
        ),
      );
    }

    return Theme(
      data: darkTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: body,
      ),
    );
  }

  Widget _buildSheet(
    BuildContext context,
    ScrollController scrollController,
    AppStyle style,
  ) {
    switch (style) {
      case AppStyle.AppleMusic:
        return _isDesktop
            ? AppleMusicDesktopFullScreenPlayer(
                scrollController: scrollController,
              )
            : AppleMusicFullScreenPlayer(scrollController: scrollController);
      case AppStyle.Original:
        return _isDesktop
            ? OriginalDesktopFullScreenPlayer()
            : OriginalMobileFullScreenPlayer(scrollController: scrollController);
      case AppStyle.Spotify:
        return _isDesktop
            ? SpotifyDesktopFullScreenPlayer()
            : SpotifyMobileFullScreenPlayer(scrollController: scrollController);
    }
  }
}

class _DismissibleFullPlayerSheet extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController scrollController)
      builder;

  const _DismissibleFullPlayerSheet({required this.builder});

  @override
  State<_DismissibleFullPlayerSheet> createState() =>
      _DismissibleFullPlayerSheetState();
}

class _DismissibleFullPlayerSheetState
    extends State<_DismissibleFullPlayerSheet> {
  double _extent = 1.0;
  bool _isDismissing = false;

  void _triggerDismiss() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final topRadius = ((1.0 - _extent) * 60.0).clamp(0.0, 24.0);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        if ((notification.extent - _extent).abs() > 0.004) {
          setState(() {
            _extent = notification.extent;
          });
        }
        if (notification.extent <= 0.52) {
          _triggerDismiss();
        }
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: 1.0,
        minChildSize: 0.45,
        maxChildSize: 1.0,
        snap: true,
        snapSizes: const [0.45, 1.0],
        builder: (context, scrollController) => ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
          child: widget.builder(context, scrollController),
        ),
      ),
    );
  }
}
