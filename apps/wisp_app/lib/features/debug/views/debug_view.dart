// Copyright © 2026 wizeshi

// Debug View for the app. Shows internal info about app state, player state, whatever needed.

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/data/sources/youtube/youtube_metadata.dart';
import 'package:wisp/services/system/listening_habits_service.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';

String _formatDuration(int? duration, {bool miliseconds = false}) {
  if (duration == null) return '--:--';
  if (miliseconds) {
    final minutes = duration ~/ 60000;
    final seconds = (duration ~/ 1000) % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  } else {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

enum DebugViewTab {
  // ignore: constant_identifier_names
  NavigationHistory,
  // ignore: constant_identifier_names
  PlayerState,
  // ignore: constant_identifier_names
  ProviderState,
  // ignore: constant_identifier_names
  Handoff,
  // ignore: constant_identifier_names
  Genres;

  String toJson() => name;

  static DebugViewTab fromJson(String json) {
    return DebugViewTab.values.firstWhere(
      (e) => e.name == json,
      orElse: () => DebugViewTab.NavigationHistory,
    );
  }
}

class DebugView extends StatefulWidget {
  const DebugView({super.key});

  @override
  State<DebugView> createState() => _DebugViewState();
}

const int _sidebarPercentage = 15;

class _DebugViewState extends State<DebugView> {
  DebugViewTab _selectedTab = DebugViewTab.NavigationHistory;
  bool _isSidebarExpanded = false;

  void _selectTab(DebugViewTab tab) {
    setState(() {
      _selectedTab = tab;

      final isMobile = MediaQuery.of(context).size.width < 700;
      if (isMobile) {
        _isSidebarExpanded = false;
      }
    });
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
    });
  }

  Widget _buildSidebar(Color highlightColor) {
    Widget buildButton(String text, DebugViewTab tab) {
      return ClickableText(
        text: text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: _selectedTab == tab ? highlightColor : null,
        ),
        onTap: () => _selectTab(tab),
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      child: SizedBox(
        width: 250,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildButton("Navigation", DebugViewTab.NavigationHistory),
                    const SizedBox(height: 6),
                    buildButton("Player", DebugViewTab.PlayerState),
                    const SizedBox(height: 6),
                    buildButton("Providers", DebugViewTab.ProviderState),
                    const SizedBox(height: 6),
                    buildButton("Handoff", DebugViewTab.Handoff),
                    const SizedBox(height: 6),
                    buildButton("Genres & Habits", DebugViewTab.Genres),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              SizedBox(
                width: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.grey.shade800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final highlightColor = Theme.of(context).colorScheme.primary;
    final isMobile = Platform.isAndroid || Platform.isIOS;

    return SafeArea(
      top: true,
      bottom: false,
      left: false,
      right: false,
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: isMobile
            ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
            : const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: isMobile
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.start,
              children: [
                if (isMobile)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 100),
                        child: Icon(
                          _isSidebarExpanded
                              ? Icons.chevron_left
                              : Icons.chevron_right,
                          key: ValueKey(_isSidebarExpanded),
                          size: 32,
                        ),
                      ),
                      onPressed: _toggleSidebar,
                    ),
                  ),

                const SizedBox(width: 8),

                const Text(
                  "Debug View",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const Divider(),

            Expanded(
              child: Stack(
                children: [
                  Row(
                    children: [
                      if (!isMobile)
                        Expanded(
                          flex: _sidebarPercentage,
                          child: _buildSidebar(highlightColor),
                        ),

                      Expanded(
                        flex: isMobile ? 1 : 100 - _sidebarPercentage,
                        child: switch (_selectedTab) {
                          DebugViewTab.NavigationHistory =>
                            NavigationHistoryView(),

                          DebugViewTab.PlayerState => PlayerStateView(),

                          DebugViewTab.ProviderState => ProviderStateView(),

                          DebugViewTab.Handoff => HandoffView(),

                          DebugViewTab.Genres => const GenresDebugView(),
                        },
                      ),
                    ],
                  ),

                  if (isMobile) ...[
                    IgnorePointer(
                      ignoring: !_isSidebarExpanded,
                      child: AnimatedOpacity(
                        opacity: _isSidebarExpanded ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleSidebar,
                          child: Container(color: Colors.black54),
                        ),
                      ),
                    ),

                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      top: 0,
                      bottom: 0,
                      left: _isSidebarExpanded ? 0 : -260,
                      child: _buildSidebar(highlightColor),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NavigationHistoryView extends StatelessWidget {
  const NavigationHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Text("Navigation History View");
  }
}

class PlayerStateView extends StatelessWidget {
  const PlayerStateView({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    final player = context.watch<WispAudioHandler>();

    final playerInfo = player.dumpInfo();
    final playerState = PlaybackState.fromJson(playerInfo['state']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 32,
              children: [
                PlayerStateViewSection(
                  title: "Player State Details",
                  children: [
                    PlayerStateViewRow(
                      label: "Current State",
                      value: _uppercaseFirstLetter(playerState.toJson()),
                    ),

                    isMobile
                        // Mobile
                        ? Column(
                            spacing: 6,
                            children: [
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Is Playing?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['isPlaying'].toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Is Loading?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['isLoading'].toString(),
                                    ),
                                  ),
                                ],
                              ),

                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Is Buffering?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['isBuffering'].toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Is Online?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['isOnline'].toString(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        // Desktop
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Is Playing?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['isPlaying'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Is Loading?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['isLoading'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Is Buffering?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['isBuffering'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Is Online?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['isOnline'].toString(),
                                ),
                              ),
                            ],
                          ),

                    PlayerStateViewRow(
                      label: "Error Message",
                      value: _uppercaseFirstLetter(
                        playerInfo['errorMessage'] ?? "None",
                      ),
                    ),

                    isMobile
                        // Mobile
                        ? Row(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Current Track",
                                value: _uppercaseFirstLetter(
                                  playerInfo['currentTrack']?.toString() ??
                                      "None",
                                ),
                                valueOverride:
                                    playerInfo['currentTrack'] != null
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: SimpleTrackRow(
                                          track: GenericSong.fromJson(
                                            playerInfo['currentTrack'],
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          )
                        // Desktop
                        : PlayerStateViewRow(
                            label: "Current Track",
                            value: _uppercaseFirstLetter(
                              playerInfo['currentTrack']?.toString() ?? "None",
                            ),
                            valueOverride: playerInfo['currentTrack'] != null
                                ? SimpleTrackRow(
                                    track: GenericSong.fromJson(
                                      playerInfo['currentTrack'],
                                    ),
                                  )
                                : null,
                          ),

                    PlayerStateViewRow(
                      label: "Queue",
                      value: "View Queue",
                      valueOverride: TextButton(
                        child: const Text("View Queue"),
                        onPressed: () {},
                      ),
                    ),

                    PlayerStateViewRow(
                      label: "Original Queue",
                      value: "View Original Queue",
                      valueOverride: TextButton(
                        child: const Text("View Original Queue"),
                        onPressed: () {},
                      ),
                    ),

                    isMobile
                        // Mobile
                        ? Column(
                            spacing: 6,
                            children: [
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Current Index",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['currentIndex'].toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Track Change Token",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['trackChangeToken'].toString(),
                                    ),
                                  ),
                                ],
                              ),
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Shuffle Enabled?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['shuffleEnabled'].toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Repeat Mode",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['repeatMode']
                                          .toString()
                                          .split('.')
                                          .last,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        // Desktop
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Current Index",
                                value: _uppercaseFirstLetter(
                                  playerInfo['currentIndex'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Track Change Token",
                                value: _uppercaseFirstLetter(
                                  playerInfo['trackChangeToken'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Shuffle Enabled?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['shuffleEnabled'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Repeat Mode",
                                value: _uppercaseFirstLetter(
                                  playerInfo['repeatMode']
                                      .toString()
                                      .split('.')
                                      .last,
                                ),
                              ),
                            ],
                          ),

                    isMobile
                        ? Column(
                            spacing: 6,
                            children: [
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Gapless Playback Enabled?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['gaplessPlaybackEnabled']
                                          .toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Crossfade Enabled?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['crossfadeEnabled'].toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Crossfade Duration (seconds)",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['crossfadeDurationSeconds']
                                          .toString(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Gapless Playback Enabled?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['gaplessPlaybackEnabled']
                                      .toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Crossfade Enabled?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['crossfadeEnabled'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Crossfade Duration (seconds)",
                                value: _uppercaseFirstLetter(
                                  playerInfo['crossfadeDurationSeconds']
                                      .toString(),
                                ),
                              ),
                            ],
                          ),

                    isMobile
                        ? Column(
                            spacing: 6,
                            children: [
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 2,
                                    label: "Is Track Transitioning?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['isTrackTransitioning']
                                          .toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 2,
                                    label: "Preloaded Next Index",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['preloadedNextIndex']
                                          .toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 6,
                                    label: "Preloaded Next Track",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['preloadedNextTrack']
                                              ?.toString() ??
                                          "None",
                                    ),
                                    valueOverride:
                                        playerInfo['preloadedNextTrack'] != null
                                        ? Container(
                                            padding: const EdgeInsets.only(
                                              top: 8.0,
                                            ),
                                            child: SimpleTrackRow(
                                              track: GenericSong.fromJson(
                                                playerInfo['preloadedNextTrack'],
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                              ),

                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Is Preload in Progress?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['isPreloadInProgress']
                                          .toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Preload Generation",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['preloadGeneration']
                                          .toString(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Is Track Transitioning?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['isTrackTransitioning'].toString(),
                                ),
                              ),
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Preload in Progress?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['isPreloadInProgress'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Preload Generation",
                                value: _uppercaseFirstLetter(
                                  playerInfo['preloadGeneration'].toString(),
                                ),
                              ),
                            ],
                          ),

                    isMobile
                        ? Column(
                            spacing: 6,
                            children: [
                              Row(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Preloaded Next Track",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['preloadedNextTrack']
                                              ?.toString() ??
                                          "None",
                                    ),
                                    valueOverride:
                                        playerInfo['preloadedNextTrack'] != null
                                        ? Container(
                                            padding: const EdgeInsets.only(
                                              top: 8.0,
                                            ),
                                            child: SimpleTrackRow(
                                              track: GenericSong.fromJson(
                                                playerInfo['preloadedNextTrack'],
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                              ),

                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Preloaded Next Index",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['preloadedNextIndex']
                                          .toString(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 2,
                                label: "Preloaded Next Index",
                                value: _uppercaseFirstLetter(
                                  playerInfo['preloadedNextIndex'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 3,
                                label: "Preloaded Next Track",
                                value: _uppercaseFirstLetter(
                                  playerInfo['preloadedNextTrack']
                                          ?.toString() ??
                                      "None",
                                ),
                                valueOverride:
                                    playerInfo['preloadedNextTrack'] != null
                                    ? Container(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: SimpleTrackRow(
                                          track: GenericSong.fromJson(
                                            playerInfo['preloadedNextTrack'],
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),

                    isMobile
                        ? Column(
                            spacing: 6,
                            children: [
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Saved Volume",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['savedVolume'].toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Volume",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['lastVolume'].toString(),
                                    ),
                                  ),
                                ],
                              ),

                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Raw Position",
                                    value: _formatDuration(
                                      int.tryParse(
                                            playerInfo['lastRawPositionMs']
                                                .toString(),
                                          ) ??
                                          0,
                                      miliseconds: true,
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Notified Position",
                                    value: _formatDuration(
                                      int.tryParse(
                                            playerInfo['lastNotifiedPositionMs']
                                                .toString(),
                                          ) ??
                                          0,
                                      miliseconds: true,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Saved Volume",
                                value: _uppercaseFirstLetter(
                                  playerInfo['savedVolume'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Volume",
                                value: _uppercaseFirstLetter(
                                  playerInfo['lastVolume'].toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Raw Position",
                                value: _formatDuration(
                                  int.tryParse(
                                        playerInfo['lastRawPositionMs']
                                            .toString(),
                                      ) ??
                                      0,
                                  miliseconds: true,
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Notified Position",
                                value: _formatDuration(
                                  int.tryParse(
                                        playerInfo['lastNotifiedPositionMs']
                                            .toString(),
                                      ) ??
                                      0,
                                  miliseconds: true,
                                ),
                              ),
                            ],
                          ),

                    isMobile
                        ? Column(
                            spacing: 6,
                            children: [
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Position Notify",
                                    value: DateTime.fromMillisecondsSinceEpoch(
                                      int.tryParse(
                                            playerInfo['lastPositionNotifyMs']
                                                .toString(),
                                          ) ??
                                          0,
                                    ).toString(),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Position Update",
                                    value: DateTime.fromMillisecondsSinceEpoch(
                                      int.tryParse(
                                            playerInfo['lastPositionUpdateMs']
                                                .toString(),
                                          ) ??
                                          0,
                                    ).toString(),
                                  ),
                                ],
                              ),

                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Media Update",
                                    value: DateTime.fromMillisecondsSinceEpoch(
                                      int.tryParse(
                                            playerInfo['lastMediaUpdateMs']
                                                .toString(),
                                          ) ??
                                          0,
                                    ).toString(),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Media Position",
                                    value: _formatDuration(
                                      int.tryParse(
                                            playerInfo['lastMediaPositionMs']
                                                .toString(),
                                          ) ??
                                          0,
                                      miliseconds: true,
                                    ),
                                  ),
                                ],
                              ),

                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Last Known Duration",
                                    value: _formatDuration(
                                      int.tryParse(
                                            playerInfo['lastKnownDurationMs']
                                                .toString(),
                                          ) ??
                                          0,
                                      miliseconds: true,
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "RPC last second",
                                    value: _formatDuration(
                                      int.tryParse(
                                            playerInfo['rpcLastSecond']
                                                .toString(),
                                          ) ??
                                          0,
                                      miliseconds: false,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Position Notify",
                                value: DateTime.fromMillisecondsSinceEpoch(
                                  int.tryParse(
                                        playerInfo['lastPositionNotifyMs']
                                            .toString(),
                                      ) ??
                                      0,
                                ).toString(),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Position Update",
                                value: DateTime.fromMillisecondsSinceEpoch(
                                  int.tryParse(
                                        playerInfo['lastPositionUpdateMs']
                                            .toString(),
                                      ) ??
                                      0,
                                ).toString(),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Media Update",
                                value: DateTime.fromMillisecondsSinceEpoch(
                                  int.tryParse(
                                        playerInfo['lastMediaUpdateMs']
                                            .toString(),
                                      ) ??
                                      0,
                                ).toString(),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Media Position",
                                value: _formatDuration(
                                  int.tryParse(
                                        playerInfo['lastMediaPositionMs']
                                            .toString(),
                                      ) ??
                                      0,
                                  miliseconds: true,
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Last Known Duration",
                                value: _formatDuration(
                                  int.tryParse(
                                        playerInfo['lastKnownDurationMs']
                                            .toString(),
                                      ) ??
                                      0,
                                  miliseconds: true,
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "RPC last second",
                                value: _formatDuration(
                                  int.tryParse(
                                        playerInfo['rpcLastSecond'].toString(),
                                      ) ??
                                      0,
                                  miliseconds: false,
                                ),
                              ),
                            ],
                          ),

                    SimpleRowWithEqualHeight(
                      children: [
                        PlayerStateViewElement(
                          flex: 1,
                          label: "Playlist Playback Enabled",
                          value: _uppercaseFirstLetter(
                            playerInfo['playlistPlaybackEnabled'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Playback Context Type",
                          value: _uppercaseFirstLetter(
                            playerInfo['playbackContext']['type'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Playback Context Name",
                          value: _uppercaseFirstLetter(
                            playerInfo['playbackContext']['name'].toString(),
                          ),
                        ),
                      ],
                    ),

                    SimpleRowWithEqualHeight(
                      children: [
                        PlayerStateViewElement(
                          flex: 1,
                          label: "Playback Context ID",
                          value: _uppercaseFirstLetter(
                            playerInfo['playbackContext']['id'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Playback Context Source",
                          value: _uppercaseFirstLetter(
                            playerInfo['playbackContext']['source'].toString(),
                          ),
                        ),
                      ],
                    ),

                    PlayerStateViewRow(
                      label: "Is Handoff Host?",
                      value: _uppercaseFirstLetter(
                        playerInfo['isHandoffHost'].toString(),
                      ),
                    ),

                    SimpleRowWithEqualHeight(
                      children: [
                        PlayerStateViewElement(
                          flex: 1,
                          label: "Prefetch Window Size",
                          value: _uppercaseFirstLetter(
                            playerInfo['prefetchWindowSize'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Prefetch Generation",
                          value: _uppercaseFirstLetter(
                            playerInfo['prefetchGeneration'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Prefetch Source Tasks",
                          value: _uppercaseFirstLetter(
                            playerInfo['prefetchSourceTasks'].toString(),
                          ),
                        ),
                      ],
                    ),

                    PlayerStateViewRow(
                      label: "Stream URL Cache",
                      value: "Open Stream URL Cache",
                      valueOverride: TextButton(
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(
                            Theme.of(context).colorScheme.primary,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            Colors.white,
                          ),
                        ),
                        child: const Text("Open Stream URL Cache"),
                        onPressed: () {},
                      ),
                    ),

                    PlayerStateViewRow(
                      label: "Stream URL Tasks",
                      value: _uppercaseFirstLetter(
                        playerInfo['streamUrlTasks'].toString(),
                      ),
                    ),

                    PlayerStateViewRow(
                      label: "Video ID Tasks",
                      value: _uppercaseFirstLetter(
                        playerInfo['videoIdTasks'].toString(),
                      ),
                    ),

                    PlayerStateViewRow(
                      label: "Output Devices",
                      value: _uppercaseFirstLetter(
                        playerInfo['outputDevices']
                            .map((device) => device['name'])
                            .join(', '),
                      ),
                    ),

                    PlayerStateViewRow(
                      label: "Active Output Device",
                      value: _uppercaseFirstLetter(
                        playerInfo['activeOutputDevice']['name'] ?? "Unknown",
                      ),
                    ),
                  ],
                ),

                PlayerStateViewSection(
                  title: "Engine Info",
                  children: [
                    SimpleRowWithEqualHeight(
                      children: [
                        PlayerStateViewElement(
                          flex: 1,
                          label: "Is Playing",
                          value: _uppercaseFirstLetter(
                            playerInfo['engine']['isPlaying'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Is Buffering?",
                          value: _uppercaseFirstLetter(
                            playerInfo['engine']['isBuffering'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Is Transitioning?",
                          value: _uppercaseFirstLetter(
                            playerInfo['engine']['isTransitioning'].toString(),
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Volume",
                          value: _uppercaseFirstLetter(
                            playerInfo['engine']['volume'].toString(),
                          ),
                        ),
                      ],
                    ),

                    SimpleRowWithEqualHeight(
                      children: [
                        PlayerStateViewElement(
                          flex: 1,
                          label: "Position",
                          value: _formatDuration(
                            int.tryParse(
                                  playerInfo['engine']['positionMs'].toString(),
                                ) ??
                                0,
                            miliseconds: true,
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Duration",
                          value: _formatDuration(
                            int.tryParse(
                                  playerInfo['engine']['durationMs'].toString(),
                                ) ??
                                0,
                            miliseconds: true,
                          ),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Error Message",
                          value: _formatDuration(
                            int.tryParse(
                                  playerInfo['engine']['error'].toString(),
                                ) ??
                                0,
                            miliseconds: true,
                          ),
                        ),
                      ],
                    ),

                    SimpleRowWithEqualHeight(
                      children: [
                        PlayerStateViewElement(
                          flex: 1,
                          label: "Source URI",
                          value: playerInfo['engine']['sourceUri'].toString(),
                        ),

                        PlayerStateViewElement(
                          flex: 1,
                          label: "Preloaded Source URI",
                          value: playerInfo['engine']['preloadedSourceUri']
                              .toString(),
                        ),
                      ],
                    ),
                  ],
                ),

                PlayerStateViewSection(
                  title: "Subscriptions",
                  children: [
                    isMobile
                        ? Column(
                            spacing: 6,
                            children: [
                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Engine State Subscription Active?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['subscriptions']['engineState']
                                          .toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label:
                                        "Engine Completed Subscription Active?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['subscriptions']['engineCompleted']
                                          .toString(),
                                    ),
                                  ),
                                ],
                              ),

                              Row(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label:
                                        "Output Devices Subscription Active?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['subscriptions']['outputDevices']
                                          .toString(),
                                    ),
                                  ),
                                ],
                              ),

                              SimpleRowWithEqualHeight(
                                children: [
                                  PlayerStateViewElement(
                                    flex: 1,
                                    label:
                                        "Active Output Device Subscription Active?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['subscriptions']['activeOutputDevice']
                                          .toString(),
                                    ),
                                  ),

                                  PlayerStateViewElement(
                                    flex: 1,
                                    label: "Connectivity Subscription Active?",
                                    value: _uppercaseFirstLetter(
                                      playerInfo['subscriptions']['connectivity']
                                          .toString(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : SimpleRowWithEqualHeight(
                            children: [
                              PlayerStateViewElement(
                                flex: 1,
                                label: "Engine State Subscription Active?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['subscriptions']['engineState']
                                      .toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Engine Completed Subscription Active?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['subscriptions']['engineCompleted']
                                      .toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Output Devices Subscription Active?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['subscriptions']['outputDevices']
                                      .toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label:
                                    "Active Output Device Subscription Active?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['subscriptions']['activeOutputDevice']
                                      .toString(),
                                ),
                              ),

                              PlayerStateViewElement(
                                flex: 1,
                                label: "Connectivity Subscription Active?",
                                value: _uppercaseFirstLetter(
                                  playerInfo['subscriptions']['connectivity']
                                      .toString(),
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PlayerStateViewRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? valueOverride;

  const PlayerStateViewRow({
    super.key,
    required this.label,
    required this.value,
    this.valueOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),

          valueOverride ??
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
        ],
      ),
    );
  }
}

class PlayerStateViewElement extends StatelessWidget {
  final String label;
  final int flex;
  final String value;
  final Widget? valueOverride;

  const PlayerStateViewElement({
    super.key,
    required this.label,
    required this.value,
    required this.flex,
    this.valueOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),

            valueOverride ??
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
          ],
        ),
      ),
    );
  }
}

class PlayerStateViewSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const PlayerStateViewSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Row(
          spacing: 8,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Expanded(child: Divider(color: Colors.white, thickness: 1)),
          ],
        ),
        ...children,
      ],
    );
  }
}

class ProviderStateView extends StatelessWidget {
  const ProviderStateView({super.key});

  @override
  Widget build(BuildContext context) {
    final spotifyInternalMetadata = context.watch<SpotifyInternalProvider>();
    final spotifyInternalMetadataDump = spotifyInternalMetadata.dumpJson();

    final metadataYoutube = context.watch<YouTubeMetadataProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              spacing: 32,
              children: [
                Column(
                  spacing: 12,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Text(
                          "Metadata Providers",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const Expanded(
                          child: Divider(color: Colors.white, thickness: 1),
                        ),
                      ],
                    ),

                    Container(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        spacing: 24,
                        children: [
                          ProviderStateViewSection(
                            providerName: spotifyInternalMetadata.displayName,
                            providerThumbnailUrl:
                                spotifyInternalMetadata.iconURL,
                            children: [
                              Row(
                                spacing: 8,
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: ProviderStateViewRow(
                                      label: "Is Authenticated?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['isAuthenticated']
                                            .toString(),
                                      ),
                                      valueStyle:
                                          spotifyInternalMetadataDump['isAuthenticated']
                                                  .toString()
                                                  .toLowerCase() ==
                                              "true"
                                          ? const TextStyle(color: Colors.green)
                                          : const TextStyle(color: Colors.red),
                                    ),
                                  ),

                                  Expanded(
                                    flex: 1,
                                    child: ProviderStateViewRow(
                                      label: "Is Loading?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['isLoading']
                                            .toString(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              ProviderStateViewRow(
                                label: "Error Message",
                                value: _uppercaseFirstLetter(
                                  spotifyInternalMetadataDump['errorMessage']
                                      .toString(),
                                ),
                              ),

                              ProviderStateViewRow(
                                label: "User ID",
                                // Don't uppercase user ID, as it is case sensitive
                                value: spotifyInternalMetadataDump['userId']
                                    .toString(),
                              ),

                              ProviderStateViewRow(
                                label: "User Display Name",
                                value:
                                    spotifyInternalMetadataDump['userDisplayName']
                                        .toString(),
                              ),

                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: 6,
                                  children: [
                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Bearer Token Present?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['bearerTokenPresent']
                                            .toString(),
                                      ),
                                      valueStyle:
                                          spotifyInternalMetadataDump['bearerTokenPresent']
                                                  .toString()
                                                  .toLowerCase() ==
                                              "true"
                                          ? const TextStyle(color: Colors.green)
                                          : const TextStyle(color: Colors.red),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Bearer Token Length",
                                      value:
                                          spotifyInternalMetadataDump['bearerTokenLength']
                                              .toString(),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Client Token Present?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['clientTokenPresent']
                                            .toString(),
                                      ),
                                      valueStyle:
                                          spotifyInternalMetadataDump['clientTokenPresent']
                                                  .toString()
                                                  .toLowerCase() ==
                                              "true"
                                          ? const TextStyle(color: Colors.green)
                                          : const TextStyle(color: Colors.red),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Client Token Length",
                                      value:
                                          spotifyInternalMetadataDump['clientTokenLength']
                                              .toString(),
                                    ),
                                  ],
                                ),
                              ),

                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: 6,
                                  children: [
                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Liked Tracks Loaded?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['likedTracksLoaded']
                                            .toString(),
                                      ),
                                      valueStyle:
                                          spotifyInternalMetadataDump['likedTracksLoaded']
                                                  .toString()
                                                  .toLowerCase() ==
                                              "true"
                                          ? const TextStyle(color: Colors.green)
                                          : const TextStyle(color: Colors.red),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Liked Tracks Total Count",
                                      value:
                                          spotifyInternalMetadataDump['likedTracksTotalCount']
                                              .toString(),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Liked Tracks IDs Count",
                                      value:
                                          spotifyInternalMetadataDump['likedTracksIdsCount']
                                              .toString(),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Is Refreshing Liked Tracks?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['isRefreshingLikedTracks']
                                            .toString(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              ProviderStateViewRow(
                                label: "Canvas URL Cache Size",
                                value:
                                    spotifyInternalMetadataDump['canvasUrlCacheSize']
                                        .toString(),
                              ),

                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: 6,
                                  children: [
                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Auth Init in Flight?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['authInitInFlight']
                                            .toString(),
                                      ),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Last Auth Init Attempt",
                                      value:
                                          spotifyInternalMetadataDump['lastAuthInitAttemptAt']
                                              .toString(),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Last Auth Init Failed?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['lastAuthInitFailed']
                                            .toString(),
                                      ),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Startup Auth Retry Scheduled?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['startupAuthRetryScheduled']
                                            .toString(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: 6,
                                  children: [
                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Last Token Refresh",
                                      value:
                                          spotifyInternalMetadataDump['lastTokenRefreshAt']
                                              .toString(),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Token Refresh in Progress?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['tokenRefreshInProgress']
                                            .toString(),
                                      ),
                                    ),

                                    ProviderStateViewElement(
                                      flex: 1,
                                      label: "Token Refresh Failed?",
                                      value: _uppercaseFirstLetter(
                                        spotifyInternalMetadataDump['tokenRefreshFailed']
                                            .toString(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          ProviderStateViewSection(
                            providerName: metadataYoutube.displayName,
                            providerThumbnailUrl: metadataYoutube.iconURL,
                            children: [
                              ProviderStateViewRow(
                                label: "Is Authenticated?",
                                value: "True",
                                valueStyle: const TextStyle(
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ProviderStateViewSection extends StatelessWidget {
  final String providerName;
  final String providerThumbnailUrl;
  final List<Widget> children;

  const ProviderStateViewSection({
    super.key,
    required this.providerName,
    required this.providerThumbnailUrl,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        Row(
          spacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.1),
              ),

              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 12,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: SvgPicture.network(providerThumbnailUrl),
                  ),

                  Text(
                    providerName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const Expanded(child: Divider(color: Colors.white, thickness: 1)),
          ],
        ),

        Column(spacing: 8, children: children),
      ],
    );
  }
}

class ProviderStateViewRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final Widget? overrideWidget;

  const ProviderStateViewRow({
    super.key,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
    this.overrideWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style:
                labelStyle ??
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),

          overrideWidget ??
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ).merge(valueStyle),
              ),
        ],
      ),
    );
  }
}

class ProviderStateViewElement extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final Widget? overrideWidget;
  final int flex;

  const ProviderStateViewElement({
    super.key,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
    this.overrideWidget,
    required this.flex,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Text(
              label,
              style:
                  labelStyle ??
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),

            overrideWidget ??
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ).merge(valueStyle),
                  textAlign: TextAlign.center,
                ),
          ],
        ),
      ),
    );
  }
}

class HandoffView extends StatelessWidget {
  const HandoffView({super.key});

  @override
  Widget build(BuildContext context) {
    return Text("Handoff View");
  }
}

class GenresDebugView extends StatefulWidget {
  const GenresDebugView({super.key});

  @override
  State<GenresDebugView> createState() => _GenresDebugViewState();
}

class _GenresDebugViewState extends State<GenresDebugView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _lookupController = TextEditingController();
  bool _sortByFrequency = true;
  bool _isLookingUp = false;
  List<String>? _liveLookupGenres;
  String? _liveLookupError;

  @override
  void dispose() {
    _searchController.dispose();
    _lookupController.dispose();
    super.dispose();
  }

  Future<void> _performLiveLookup() async {
    final input = _lookupController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isLookingUp = true;
      _liveLookupError = null;
      _liveLookupGenres = null;
    });

    try {
      final spotify = context.read<SpotifyInternalProvider>();
      final cleanId = input.startsWith('spotify:track:')
          ? input.split(':').last
          : input;
      final genres = await spotify.getTrackGenres(cleanId);
      if (mounted) {
        setState(() {
          _liveLookupGenres = genres;
          _isLookingUp = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _liveLookupError = e.toString();
          _isLookingUp = false;
        });
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ListeningHabitsService>(
      builder: (context, habits, _) {
        final uniqueGenresSet = habits.allUniqueGenres;
        final frequencyMap = habits.genreFrequency;
        final searchQuery = _searchController.text.toLowerCase().trim();

        var displayGenres = uniqueGenresSet.where((g) {
          if (searchQuery.isEmpty) return true;
          return g.toLowerCase().contains(searchQuery);
        }).toList();

        if (_sortByFrequency) {
          displayGenres.sort((a, b) {
            final fA = frequencyMap[a] ?? 0;
            final fB = frequencyMap[b] ?? 0;
            if (fB != fA) return fB.compareTo(fA);
            return a.compareTo(b);
          });
        } else {
          displayGenres.sort((a, b) => a.compareTo(b));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Top Summary Cards
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatCard(
                  title: "Unique Genres",
                  value: "${uniqueGenresSet.length}",
                  icon: Icons.category,
                  color: Colors.purpleAccent,
                ),
                _buildStatCard(
                  title: "Tracks Finished",
                  value: "${habits.history.length}",
                  icon: Icons.check_circle_outline,
                  color: Colors.greenAccent,
                ),
                _buildStatCard(
                  title: "Languages Detected",
                  value: "${habits.history.expand((r) => r.languages).toSet().length}",
                  icon: Icons.language,
                  color: Colors.blueAccent,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Live Test / Lookup Box
            Card(
              color: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade800),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bolt, color: Colors.amberAccent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Live Track Genre Lookup",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Test any Spotify Track ID or URI to see what genres Spotify returns right now:",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lookupController,
                            decoration: InputDecoration(
                              hintText: "e.g. 3I0w0pdn5s2W44gGmBxsa0",
                              hintStyle: TextStyle(color: Colors.grey.shade600),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey.shade700),
                              ),
                            ),
                            onSubmitted: (_) => _performLiveLookup(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isLookingUp ? null : _performLiveLookup,
                          icon: _isLookingUp
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search, size: 18),
                          label: const Text("Lookup"),
                        ),
                      ],
                    ),
                    if (_liveLookupGenres != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            "Result: ",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: _liveLookupGenres!.isEmpty
                                ? const Text(
                                    "No genres tagged by Spotify for this track",
                                    style: TextStyle(color: Colors.amberAccent),
                                  )
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _liveLookupGenres!
                                        .map(
                                          (g) => Chip(
                                            label: Text(g),
                                            backgroundColor: Colors.purple.shade900,
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ],
                      ),
                    ],
                    if (_liveLookupError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Error: $_liveLookupError",
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Section Header & Actions
            Row(
              children: [
                Expanded(
                  child: Text(
                    "All Available Genres (${displayGenres.length})",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _sortByFrequency
                      ? "Sorted by Frequency (Click for A-Z)"
                      : "Sorted Alphabetically (Click for Frequency)",
                  icon: Icon(
                    _sortByFrequency ? Icons.sort : Icons.sort_by_alpha,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _sortByFrequency = !_sortByFrequency;
                    });
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text("Copy JSON"),
                  onPressed: uniqueGenresSet.isEmpty
                      ? null
                      : () {
                          final jsonStr = jsonEncode(uniqueGenresSet.toList());
                          _copyToClipboard(context, jsonStr, "Genres JSON");
                        },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.list, size: 16),
                  label: const Text("Copy List"),
                  onPressed: uniqueGenresSet.isEmpty
                      ? null
                      : () {
                          final listStr = uniqueGenresSet.join(', ');
                          _copyToClipboard(context, listStr, "Genres list");
                        },
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Search input
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: "Filter unique genres...",
                prefixIcon: const Icon(Icons.filter_list, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade800),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // The Set of Genres (Chips)
            if (uniqueGenresSet.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.music_off, size: 48, color: Colors.grey.shade600),
                      const SizedBox(height: 12),
                      Text(
                        "No genres logged yet.",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Genres will appear here automatically as tracks finish playing.",
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: displayGenres.map((genre) {
                  final count = frequencyMap[genre] ?? 0;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _copyToClipboard(context, genre, 'Genre "$genre"'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.25),
                        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            genre,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          if (count > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.purpleAccent.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "$count",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 30),

            // Finished Track History
            if (habits.history.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Track Playback History (${habits.history.length})",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Most recent first",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...habits.history.reversed.take(50).map((record) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.grey.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade800),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    title: Text(
                      record.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          "${record.artistNames.join(', ')} • ${record.albumName ?? 'Unknown Album'} "
                          "${record.releaseYear != null ? '(${record.releaseYear})' : ''} "
                          "${record.languages.isNotEmpty ? '• Lang: ${record.languages.join(', ')}' : ''}",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        if (record.genres.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: record.genres
                                .map(
                                  (g) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.purpleAccent.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      g,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.purpleAccent,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                    trailing: Text(
                      _formatCompletedTime(record.completedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompletedTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }
}

class ClickableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final VoidCallback onTap;

  const ClickableText({
    super.key,
    required this.text,
    this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(text, style: style),
      ),
    );
  }
}

class SimpleTrackRow extends StatelessWidget {
  final GenericSong track;

  const SimpleTrackRow({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[900],
      ),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CachedNetworkImage(
                imageUrl: track.thumbnailUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    track.artists.map((artist) => artist.name).join(", "),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(width: 16),

          // Track Duration
          Text(
            _formatDuration(track.durationSecs),
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class SimpleRowWithEqualHeight extends StatelessWidget {
  final List<Widget> children;

  const SimpleRowWithEqualHeight({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: children,
      ),
    );
  }
}

String _uppercaseFirstLetter(String str) {
  if (str.isEmpty) return str;
  return str[0].toUpperCase() + str.substring(1);
}
