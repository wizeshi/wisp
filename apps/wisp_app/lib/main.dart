// Copyright © 2026 wizeshi

import 'dart:io';
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:wisp/data/sources/youtube/youtube_audio.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/services/system/protocol_registrar.dart';
import 'package:wisp_assets/wisp_assets.dart';
import 'package:wisp_newpipe_manager/wisp_newpipe_manager.dart';
import 'package:wisp/data/sources/youtube/youtube_metadata.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';
import 'package:wisp/features/search/state/search_state.dart';
import 'package:wisp/features/shell/navigation/navigation_state.dart';
import 'package:wisp/core/theme/cover_art_palette_provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/notifications/notification_service.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/services/notifications/download_foreground_service.dart';
import 'package:wisp/services/notifications/desktop_notification_center.dart';
import 'package:wisp/services/discord/discord_rpc_service.dart';
import 'package:wisp/services/system/listening_habits_service.dart';
import 'package:wisp/features/shell/widgets/app_shell.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/core/utils/logger.dart';

void main() async {
  MediaKit.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  if (isDesktop) {
    // Register the custom protocol handler for desktop platforms
    final isRegistered = await ProtocolRegistrar.isRegistered('wisp');
    if (!isRegistered) {
      await ProtocolRegistrar.register(scheme: 'wisp');
    }
  }

  final appLinks = AppLinks();

  initializeWindowsCertificates();

  // Initialize Flutter Video Player (FVP) for Linux platform
  fvp.registerWith(
    options: {
      'platforms': ['windows', 'macos', 'linux'],
    },
  );

  // Initialize audio_service for system media controls (MPRIS on Linux)
  if (Platform.isLinux) {
    AudioServiceMpris.registerWith();
  }

  // Initialize audio_service for background audio playback
  final handler = await AudioService.init(
    builder: () => WispAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.wizeshi.wisp.channel.audio',
      androidNotificationChannelName: 'wisp',
      androidNotificationChannelDescription: 'Media playback controls',
      androidNotificationIcon: 'drawable/ic_stat_wisp',
      androidNotificationOngoing: false,
      // Keep the service in foreground while paused/loading so Android
      // doesn't block restarting it during delayed stream URL resolution.
      androidStopForegroundOnPause: false,
    ),
  );
  final playbackCoordinator = PlaybackCoordinator();
  playbackCoordinator.bindAudioHandler(handler);

  // Initialize window manager with custom titlebar (desktop only)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      logger.d('[Main] window_manager init failed: $e');
    }
  }

  // Initialize notification service for download progress (mobile only)
  await NotificationService.instance.initialize();

  // Initialize foreground service for background downloads (Android)
  await DownloadForegroundService.initialize();

  // Initialize audio cache manager
  await AudioCacheManager.instance.initialize();

  // Initialize Discord RPC (desktop only)
  await DiscordRpcService.instance.initialize();

  // Initialize listening habits service
  await ListeningHabitsService.instance.initialize();

  if (Platform.isAndroid) {
    NewPipeManager.instance.androidDelegate = NativeAndroidNewPipeDelegate();
  }

  // Install a Flutter framework error handler so we can log full stacks.
  FlutterError.onError = (FlutterErrorDetails details) {
    // Don't know why this happens, but regardless, the app functions normally even
    // with this error being spammed in the console, so let's ignore it for now.
    if (details.exception.toString().contains("RawTooltipState")) {
      return;
    }

    FlutterError.dumpErrorToConsole(details);
    logger.e(
      '[Main] Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Run the app inside a guarded zone to catch uncaught async errors.
  runZonedGuarded(
    () {
      runApp(
        WispApp(
          audioHandler: handler,
          playbackCoordinator: playbackCoordinator,
          appLinks: appLinks,
        ),
      );

      // Request notification permission on Android 13+ after UI is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.instance.requestPermissionIfNeeded();
      });
    },
    (error, stack) {
      logger.e('[Main] Uncaught async error', error: error, stackTrace: stack);
      // Also print to stdout to ensure it appears in simple adb/logcat streams
      print('[Main] Uncaught async error: $error');
      print(stack);
    },
  );
}

class WispApp extends StatelessWidget {
  final WispAudioHandler audioHandler;
  final PlaybackCoordinator playbackCoordinator;
  final AppLinks appLinks;
  final SpotifyInternalProvider spotifyProvider;

  WispApp({
    super.key,
    required this.audioHandler,
    required this.playbackCoordinator,
    required this.appLinks,
    SpotifyInternalProvider? spotifyProvider,
  }) : spotifyProvider = spotifyProvider ?? SpotifyInternalProvider() {
    ListeningHabitsService.instance.bindSpotifyProvider(this.spotifyProvider);
    audioHandler.bindSpotifyProvider(this.spotifyProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Providers for various services and state management
        ChangeNotifierProvider.value(value: spotifyProvider),
        ChangeNotifierProvider(create: (_) => YouTubeMetadataProvider()),

        ChangeNotifierProvider(create: (_) => LyricsProvider()),

        ChangeNotifierProvider(create: (_) => LocalPlaylistState()),

        ChangeNotifierProvider(create: (_) => PreferencesProvider()),

        ChangeNotifierProxyProvider<LocalPlaylistState, LibraryState>(
          create: (_) => LibraryState(),
          update: (_, local, library) {
            final state = library ?? LibraryState();
            state.setLocalPlaylists(local.genericPlaylists);
            state.setHiddenRemotePlaylistIds(local.hiddenProviderPlaylistIds);
            return state;
          },
        ),
        ChangeNotifierProvider(create: (_) => LibraryFolderState()),

        ChangeNotifierProvider.value(value: audioHandler),
        ChangeNotifierProvider.value(value: playbackCoordinator),
        ChangeNotifierProvider.value(value: ListeningHabitsService.instance),

        ChangeNotifierProxyProvider<WispAudioHandler, CoverArtPaletteProvider>(
          create: (_) => CoverArtPaletteProvider(),
          update: (_, player, palette) {
            final provider = palette ?? CoverArtPaletteProvider();
            provider.updateForTrack(player.currentTrack);
            return provider;
          },
        ),

        ChangeNotifierProxyProvider3<
          WispAudioHandler,
          PlaybackCoordinator,
          PreferencesProvider,
          ConnectSessionProvider
        >(
          create: (_) => ConnectSessionProvider(),
          update: (_, audio, playback, preferences, connect) {
            final provider = connect ?? ConnectSessionProvider();
            provider.bindPreferencesProvider(preferences);
            provider.bindAudioHandler(audio);
            provider.bindPlaybackCoordinator(playback);
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => SearchState()),
        ChangeNotifierProvider(create: (_) => NavigationState()),
        ChangeNotifierProvider.value(value: DesktopNotificationCenter.instance),
      ],
      child: Consumer2<CoverArtPaletteProvider, PreferencesProvider>(
        builder: (context, palette, preferences, child) {
          return MaterialApp(
            title: 'Wisp',
            scrollBehavior: const DesktopSmoothScrollBehavior(),
            theme: AppTheme.dark(
              paletteOverride: palette.palette,
              appStyle: preferences.style,
            ),
            darkTheme: AppTheme.dark(
              paletteOverride: palette.palette,
              appStyle: preferences.style,
            ),
            themeMode: ThemeMode.dark,
            home: AppShell(appLinks: appLinks),
          );
        },
      ),
    );
  }
}
