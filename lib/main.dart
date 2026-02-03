import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'providers/metadata/spotify.dart';
import 'providers/audio/player.dart';
import 'providers/lyrics/provider.dart';
import 'providers/library/library_state.dart';
import 'providers/search/search_state.dart';
import 'providers/navigation_state.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'services/cache_manager.dart';
import 'services/download_foreground_service.dart';
import 'services/desktop_notification_center.dart';
import 'services/discord_rpc_service.dart';
import 'services/ytdlp_manager.dart';
import 'widgets/app_shell.dart';

/// Audio handler for system media controls (MPRIS on Linux)
class AudioPlayerHandler extends BaseAudioHandler {
  static AudioPlayerHandler? _instance;
  static AudioPlayerHandler get instance => _instance!;

  static MediaControl shuffleControl(bool enabled) => MediaControl.custom(
    androidIcon: enabled ? 'drawable/ic_shuffle_on' : 'drawable/ic_shuffle_off',
    label: 'Shuffle',
    name: 'toggleShuffle',
  );

  static MediaControl repeatControl(AudioServiceRepeatMode mode) {
    final icon = mode == AudioServiceRepeatMode.one
        ? 'drawable/ic_repeat_one'
        : mode == AudioServiceRepeatMode.all
        ? 'drawable/ic_repeat_on'
        : 'drawable/ic_repeat_off';
    return MediaControl.custom(
      androidIcon: icon,
      label: 'Repeat',
      name: 'toggleRepeat',
    );
  }

  // Callback functions to control the player
  Function()? onPlay;
  Function()? onPause;
  Function()? onSkipNext;
  Function()? onSkipPrevious;
  Function(Duration)? onSeek;
  Function(AudioServiceShuffleMode)? onSetShuffleMode;
  Function(AudioServiceRepeatMode)? onSetRepeatMode;
  Function()? onToggleShuffle;
  Function()? onToggleRepeat;

  AudioPlayerHandler() {
    _instance = this;
    // Initialize with idle state
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        controls: [
          shuffleControl(false),
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.play,
          MediaControl.skipToNext,
          repeatControl(AudioServiceRepeatMode.none),
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
      ),
    );
  }

  @override
  Future<void> play() async {
    onPlay?.call();
  }

  @override
  Future<void> pause() async {
    onPause?.call();
  }

  @override
  Future<void> skipToNext() async {
    onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    onSeek?.call(position);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    onSetShuffleMode?.call(shuffleMode);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    onSetRepeatMode?.call(repeatMode);
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggleShuffle':
        onToggleShuffle?.call();
        break;
      case 'toggleRepeat':
        onToggleRepeat?.call();
        break;
      default:
        break;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize just_audio with media_kit backend for Linux
  JustAudioMediaKit.ensureInitialized();

  // Initialize audio_service for system media controls (MPRIS on Linux)
  if (Platform.isLinux) {
    AudioServiceMpris.registerWith();
  }
  await AudioService.init(
    builder: () => AudioPlayerHandler(),
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
  }

  // Initialize notification service for download progress (mobile only)
  await NotificationService.instance.initialize();

  // Initialize foreground service for background downloads (Android)
  await DownloadForegroundService.initialize();

  // Ensure yt-dlp is available on desktop
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await YtDlpManager.instance.ensureReady(notifyOnFailure: true);
  }

  // Initialize audio cache manager
  await AudioCacheManager.instance.initialize();

  // Initialize Discord RPC (desktop only)
  await DiscordRpcService.instance.initialize();

  runApp(const MyApp());

  // Request notification permission on Android 13+ after UI is ready
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.instance.requestPermissionIfNeeded();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SpotifyProvider()),
        ChangeNotifierProvider(create: (_) => AudioPlayerProvider()),
        ChangeNotifierProvider(create: (_) => LyricsProvider()),
        ChangeNotifierProvider(create: (_) => LibraryState()),
        ChangeNotifierProvider(create: (_) => SearchState()),
        ChangeNotifierProvider(create: (_) => NavigationState()),
        ChangeNotifierProvider.value(value: DesktopNotificationCenter.instance),
      ],
      child: MaterialApp(
        title: 'Wisp',
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter = _counter + 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
