part of '../mobile/apple_music_full_player.dart';

class AppleMusicDesktopFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;

  const AppleMusicDesktopFullScreenPlayer({
    required this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AppleMusicFullScreenPlayer(
      scrollController: scrollController,
      desktop: true,
    )._buildDesktopLayout(context);
  }
}

extension _AppleMusicDesktopLayout on AppleMusicFullScreenPlayer {
  Widget _buildDesktopLayout(BuildContext context) {
    return Selector<global_audio_player.WispAudioHandler, GenericSong?>(
      selector: (context, player) => player.currentTrack,
      builder: (context, currentTrack, child) {
        final player = context.read<global_audio_player.WispAudioHandler>();
        final lyricsProvider = context.watch<LyricsProvider>();
        final useCanvas = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.animatedCanvasEnabled,
        );
        final metadataManager = context.read<MetadataManager>();
        final canUseCanvas =
            useCanvas &&
            currentTrack != null &&
            metadataManager.hasCapability(
              MetadataCapability.canvas,
              source: currentTrack.source,
            );
        final canvasFuture = _getCanvasUrlFuture(
          metadataManager,
          currentTrack,
          canUseCanvas,
        );
        final viewPadding = MediaQuery.of(context).viewPadding;
        final windowPadding = MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ).padding;
        final topInset = viewPadding.top == 0
            ? windowPadding.top
            : viewPadding.top;
        final bottomInset = viewPadding.bottom == 0
            ? windowPadding.bottom
            : viewPadding.bottom;
        final imageUrl = currentTrack?.thumbnailUrl ?? '';
        final btnColor = Theme.of(context).colorScheme.primary;

        return FutureBuilder<String?>(
          future: canvasFuture,
          builder: (context, canvasSnapshot) {
            final canvasUrl = canvasSnapshot.data ?? '';
            final hasCanvas = canvasUrl.isNotEmpty;

            return ValueListenableBuilder<bool>(
              valueListenable: AppleMusicFullScreenPlayer
                  ._animatedCanvasTemporarilyDisabledNotifier,
              builder: (context, animatedCanvasDisabled, _) {
                return ValueListenableBuilder<_ApplePlayerViewMode>(
                  valueListenable: AppleMusicFullScreenPlayer._modeNotifier,
                  builder: (context, mode, _) {
                    final useNowPlayingCanvas =
                        !animatedCanvasDisabled && hasCanvas;

                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 420),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final moveAnimation = Tween<Offset>(
                                begin: const Offset(0, 0.06),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: moveAnimation,
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<bool>(useNowPlayingCanvas),
                              child: useNowPlayingCanvas
                                  ? _buildDesktopCanvasBackground(
                                      context,
                                      canvasUrl,
                                      imageUrl,
                                      topInset,
                                    )
                                  : _buildFallbackBackground(
                                      context,
                                      imageUrl,
                                      topInset,
                                    ),
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(bottom: bottomInset),
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(top: topInset),
                                  child: _buildHeader(context),
                                ),
                                Flexible(
                                  fit: FlexFit.tight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0,
                                    ),
                                    child: _buildDesktopBodyLayout(
                                      context,
                                      player,
                                      lyricsProvider,
                                      currentTrack,
                                      imageUrl,
                                      mode,
                                      btnColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopCanvasBackground(
    BuildContext context,
    String url,
    String fallbackUrl,
    double topInset,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: RotatingBlurredCoverBackground(
            imageUrl: fallbackUrl,
            blurSigma: 90,
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(
                        alpha: 0.1,
                      ),
                    BlendMode.srcATop,
                  ),
                  child: Transform.scale(
                    scale: 1.08,
                    child: CanvasVideo(url: url, fallbackUrl: fallbackUrl),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopBodyLayout(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
    dynamic currentTrack,
    String imageUrl,
    _ApplePlayerViewMode mode,
    Color btnColor,
  ) {
    final isNowPlaying = mode == _ApplePlayerViewMode.nowPlaying;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final contentWidth = screenWidth * 0.7;
        final panelGap = contentWidth * 0.025;
        final nowPlayingWidth = contentWidth * 0.45;
        final modeWidth = contentWidth - nowPlayingWidth - panelGap;

        // Since the aspect ratio of the image is 1, calculate height proportionally.
        // Image width accounts for 20px padding on each side (40px total).
        final imageSize = nowPlayingWidth - 40.0;
        const extraControlsHeight = 232.0; // track info + controls + vertical spacing & padding
        final nowPlayingHeight = imageSize + extraControlsHeight;
        final modeHeight = nowPlayingHeight * 0.75;

        Widget nowPlayingPanel = Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _buildCoverImageBox(
                    context,
                    imageUrl,
                    double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildTrackInfo(currentTrack, btnColor, true),
              const SizedBox(height: 8),
              _buildPlayerControls(context, player, btnColor, mode),
            ],
          ),
        );
        final modeContent = AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<_ApplePlayerViewMode>(mode),
            child: _buildModeContent(
              context,
              mode,
              player,
              lyricsProvider,
              false,
            ),
          ),
        );
        Widget modePanel = _AppleDesktopModePanel(
          showDelay:
              mode == _ApplePlayerViewMode.lyrics && currentTrack != null,
          lyricsProvider: lyricsProvider,
          trackId: currentTrack?.id,
          child: modeContent,
        );
        final modePanelSlot = AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0.12, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                axis: Axis.horizontal,
                alignment: Alignment.centerLeft,
                sizeFactor: animation,
                child: SlideTransition(position: offset, child: child),
              ),
            );
          },
          child: isNowPlaying
              ? const SizedBox(key: ValueKey('hidden-mode-panel'))
              : SizedBox(
                  key: const ValueKey('visible-mode-panel'),
                  width: modeWidth,
                  height: modeHeight,
                  child: modePanel,
                ),
        );

        return Center(
          child: SizedBox(
            width: contentWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: nowPlayingWidth,
                  child: nowPlayingPanel,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isNowPlaying) SizedBox(width: panelGap),
                      modePanelSlot,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppleDesktopModePanel extends StatefulWidget {
  final Widget child;
  final bool showDelay;
  final LyricsProvider lyricsProvider;
  final String? trackId;

  const _AppleDesktopModePanel({
    required this.child,
    required this.showDelay,
    required this.lyricsProvider,
    required this.trackId,
  });

  @override
  State<_AppleDesktopModePanel> createState() => _AppleDesktopModePanelState();
}

class _AppleDesktopModePanelState extends State<_AppleDesktopModePanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.showDelay && widget.trackId != null)
            Positioned(
              top: 0,
              // Just enough to avoid overlapping the lyrics scroll bar
              right: 16,
              child: InlineDelayEditor(
                lyricsProvider: widget.lyricsProvider,
                trackId: widget.trackId!,
                visible: _hovered,
                liquidGlass: true,
              ),
            ),
        ],
      ),
    );
  }
}
