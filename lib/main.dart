import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:wisp/providers/audio/youtube.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';
import 'providers/metadata/youtube.dart';
import 'services/wisp_audio_handler.dart';
import 'providers/preferences/preferences_provider.dart';
import 'providers/lyrics/provider.dart';
import 'providers/library/library_state.dart';
import 'providers/library/local_playlists.dart';
import 'providers/library/library_folders.dart';
import 'providers/search/search_state.dart';
import 'providers/navigation_state.dart';
import 'providers/theme/cover_art_palette_provider.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'services/cache_manager.dart';
import 'services/download_foreground_service.dart';
import 'services/desktop_notification_center.dart';
import 'services/discord_rpc_service.dart';
import 'services/spotify/spotify_audio_key_session_manager.dart';
import 'services/ytdlp_manager.dart';
import 'widgets/app_shell.dart';
import 'package:wisp/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux) {
    fvp.registerWith(options: {
      'platforms': ['linux'],
    });
  }

  // Initialize just_audio with media_kit backend for Linux
  JustAudioMediaKit.ensureInitialized();

  // Initialize audio_service for system media controls (MPRIS on Linux)
  if (Platform.isLinux) {
    AudioServiceMpris.registerWith();
  }

  try {
    await SpotifyAudioKeySessionManager.instance.initializeOnStartup();
  } catch (error) {
    logger.w('[Main] Spotify AP key session startup initialization failed', error: error);
  }

  final handler = await AudioService.init(
    builder: () => WispAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.wizeshi.wisp.channel.audio',
      androidNotificationChannelName: 'wisp',
      androidNotificationChannelDescription: 'Media playback controls',
      androidNotificationIcon: 'drawable/ic_stat_wisp',
      androidNotificationOngoing: true,
    ),
  );

  // Initialize window manager for custom titlebar (desktop only)
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

  // Update yt-dlp on Android during startup to avoid per-track delay
  if (Platform.isAndroid) {
    await YouTubeProvider.updateYtDlp();
  }

  // Ensure yt-dlp is available on desktop
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await YtDlpManager.instance.ensureReady(notifyOnFailure: true);
  }

  // Initialize audio cache manager
  await AudioCacheManager.instance.initialize();

  // Initialize Discord RPC (desktop only)
  await DiscordRpcService.instance.initialize();

  runApp(MyApp(audioHandler: handler));

  // Request notification permission on Android 13+ after UI is ready
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.instance.requestPermissionIfNeeded();
  });
}

class MyApp extends StatelessWidget {
  final WispAudioHandler audioHandler;

  const MyApp({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SpotifyInternalProvider()),
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => YouTubeMetadataProvider()),
        ChangeNotifierProvider.value(value: audioHandler),
        ChangeNotifierProxyProvider<WispAudioHandler, CoverArtPaletteProvider>(
          create: (_) => CoverArtPaletteProvider(),
          update: (_, player, palette) {
            final provider = palette ?? CoverArtPaletteProvider();
            provider.updateForTrack(player.currentTrack);
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => LyricsProvider()),
        ChangeNotifierProvider(create: (_) => LocalPlaylistState()),
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
        ChangeNotifierProvider(create: (_) => SearchState()),
        ChangeNotifierProvider(create: (_) => NavigationState()),
        ChangeNotifierProvider.value(value: DesktopNotificationCenter.instance),
      ],
      child: Consumer<CoverArtPaletteProvider>(
        builder: (context, palette, child) {
          return MaterialApp(
            title: 'Wisp',
            theme: AppTheme.dark(primaryOverride: palette.primaryColor),
            darkTheme: AppTheme.dark(primaryOverride: palette.primaryColor),
            themeMode: ThemeMode.dark,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}