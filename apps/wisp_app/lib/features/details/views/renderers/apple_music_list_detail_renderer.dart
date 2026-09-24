// Copyright © 2026 wizeshi

part of '../list_detail_view.dart';

class _AppleMusicListDetailRenderer extends StatelessWidget {
  final _SharedListDetailViewState view;
  final String title;
  final String? subtitle;
  final GenericSimpleUser? subtitleUser;
  final String imageUrl;
  final int total;
  final bool isDesktop;
  final String? description;
  final String? subtitleImageUrl;

  const _AppleMusicListDetailRenderer({
    required this.view,
    required this.title,
    required this.subtitle,
    required this.subtitleUser,
    required this.imageUrl,
    required this.subtitleImageUrl,
    required this.total,
    required this.isDesktop,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktop(context);
    }
    return _buildMobile(context);
  }

  Widget _buildHeaderArtwork(BuildContext context) {
    final isLiked =
        view.widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(view.widget.id);

    if (isLiked) {
      return Container(color: Colors.grey[900], child: const LikedSongsArt());
    }

    if (imageUrl.isNotEmpty) {
      if (view._isLocalImagePath(imageUrl)) {
        return Image.file(
          File(imageUrl.replaceFirst('file://', '')),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, url, error) =>
              Container(color: Colors.grey[900]),
        );
      } else {
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          placeholder: (context, url) => Container(color: Colors.grey[900]),
          errorWidget: (context, url, error) =>
              Container(color: Colors.grey[900]),
        );
      }
    }

    return Container(
      color: Colors.grey[900],
      child: Icon(
        view.widget.type == SharedListType.playlist
            ? Icons.playlist_play
            : Icons.album,
        color: Colors.grey[600],
        size: 64,
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final expandedHeight =
        MediaQuery.of(context).size.width - MediaQuery.of(context).padding.top;
    final contentSurfaceColor = Theme.of(context).colorScheme.surface;
    final backgroundProgress = view._scrollBackgroundProgress(
      view._mobileScrollController,
    );
    final backgroundScale = 1 + (backgroundProgress * 0.10);
    view._setMobileHeaderExtent(expandedHeight);
    view._scheduleStickyBarUpdate(view._mobileScrollController);

    return Stack(
      children: [
        Positioned.fill(child: Container(color: contentSurfaceColor)),
        WispSmoothScroll(
          controller: view._mobileScrollController,
          builder: (context, controller, physics) => CustomScrollView(
            controller: controller,
            physics: physics,
            slivers: [
            SliverAppBar(
              key: view._headerKey,
              backgroundColor: contentSurfaceColor,
              clipBehavior: Clip.none,
              pinned: true,
              expandedHeight: expandedHeight,
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: AnimatedOpacity(
                opacity: view._showStickyBar ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: view._showStickyBar
                    ? Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              actions: [
                if (view._showStickyBar)
                  view._buildStickyPlayAction(
                    useAppleStyle: true,
                    protrude: true,
                  )
                else ...[
                  IconButton(
                    icon: const Icon(CupertinoIcons.arrow_down_to_line),
                    onPressed: view._isLoading ? null : view._downloadAll,
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.ellipsis_vertical),
                    onPressed: view._showListContextMenu,
                  ),
                ],
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.scale(
                      scale: backgroundScale,
                      child: _buildHeaderArtwork(context),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                            Colors.black,
                          ],
                          stops: const [0.0, 0.25, 0.75, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 12,
                      child: _buildMobileMeta(),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Container(
                  key: view._mobileActionsKey,
                  child: _buildMobilePlaybackRow(),
                ),
              ),
            ),
            if (hasDescription)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                  child: buildParsedText(
                    context,
                    descriptionText,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    linkStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (layoutContext, constraints) {
                  return AnimatedBuilder(
                    animation: Listenable.merge([
                      view._mobileScrollController,
                      view._songListTopOffsetNotifier,
                    ]),
                    builder: (context, _) => view._buildSongList(
                      isMobile: true,
                      visualStyle: _ListVisualStyle.apple,
                      availableWidth: constraints.maxWidth,
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                child: view._buildRecommendedSection(
                  isMobile: true,
                  visualStyle: _ListVisualStyle.apple,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  }

  Widget _buildDesktop(BuildContext context) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final contentSurfaceColor = Theme.of(context).colorScheme.surface;

    view._scheduleStickyBarUpdate(view._desktopScrollController);
    return Stack(
      children: [
        Positioned.fill(child: Container(color: contentSurfaceColor)),
        SafeArea(
          bottom: false,
          child: WispSmoothScroll(
            controller: view._desktopScrollController,
            builder: (context, controller, physics) => ListView(
              controller: controller,
              physics: physics,
              padding: const EdgeInsets.fromLTRB(30, 30, 30, 18),
              children: [
              LayoutBuilder(
                builder: (headerContext, headerConstraints) {
                  final availableWidth = headerConstraints.maxWidth;
                  return Container(
                    key: view._headerKey,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 210,
                          height: 210,
                          child: _buildArtwork(context),
                        ),
                        const SizedBox(width: 22),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$total items • ${view._formatDuration(view._totalDurationSecs())}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              if ((subtitle != null && subtitle!.isNotEmpty) ||
                                  subtitleImageUrl != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (subtitleImageUrl != null) ...[
                                      MouseRegion(
                                        cursor: subtitleUser == null
                                            ? SystemMouseCursors.basic
                                            : SystemMouseCursors.click,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: subtitleUser == null
                                              ? null
                                              : () => view._openUser(
                                                  subtitleUser!,
                                                ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child:
                                                view._isLocalImagePath(
                                                  subtitleImageUrl!,
                                                )
                                                ? Image.file(
                                                    File(
                                                      subtitleImageUrl!
                                                          .replaceFirst(
                                                            'file://',
                                                            '',
                                                          ),
                                                    ),
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.cover,
                                                    filterQuality:
                                                        FilterQuality.medium,
                                                    errorBuilder:
                                                        (context, url, error) =>
                                                            Container(
                                                              width: 24,
                                                              height: 24,
                                                              color: Colors
                                                                  .grey[700],
                                                            ),
                                                  )
                                                : CachedNetworkImage(
                                                    imageUrl: subtitleImageUrl!,
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.cover,
                                                    filterQuality:
                                                        FilterQuality.medium,
                                                    errorWidget:
                                                        (context, url, error) =>
                                                            Container(
                                                              width: 24,
                                                              height: 24,
                                                              color: Colors
                                                                  .grey[700],
                                                            ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (subtitle != null &&
                                        subtitle!.isNotEmpty)
                                      subtitleUser == null
                                          ? Text(
                                              subtitle!,
                                              style: TextStyle(
                                                color: Colors.grey[300],
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            )
                                          : HoverUnderline(
                                              onTap: () =>
                                                  view._openUser(subtitleUser!),
                                              builder: (isHovering) => Text(
                                                subtitle!,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  decoration: isHovering
                                                      ? TextDecoration.underline
                                                      : TextDecoration.none,
                                                ),
                                              ),
                                            ),
                                  ],
                                ),
                              ],
                              if (hasDescription) ...[
                                const SizedBox(height: 4),
                                buildParsedText(
                                  context,
                                  descriptionText,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  linkStyle: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 16),
                              _buildDesktopPlaybackRow(
                                availableWidth: availableWidth,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              LayoutBuilder(
                builder: (layoutContext, constraints) {
                  final availableWidth = constraints.maxWidth;
                  return Column(
                    children: [
                      const SizedBox(height: 26),
                      view._buildListHeaderContent(
                        visualStyle: _ListVisualStyle.apple,
                        availableWidth: availableWidth,
                      ),
                      const SizedBox(height: 8),
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          layoutContext,
                        ).copyWith(scrollbars: false),
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            view._desktopScrollController,
                            view._songListTopOffsetNotifier,
                          ]),
                          builder: (context, _) => view._buildSongList(
                            isMobile: false,
                            visualStyle: _ListVisualStyle.apple,
                            availableWidth: availableWidth,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          layoutContext,
                        ).copyWith(scrollbars: false),
                        child: view._buildRecommendedSection(
                          isMobile: false,
                          visualStyle: _ListVisualStyle.apple,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: view._buildStickyNowPlayingBar(
              title: title,
              isDesktop: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtwork(BuildContext context) {
    final isLiked =
        view.widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(view.widget.id);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: Colors.grey[900],
        child: isLiked
            ? const LikedSongsArt()
            : (imageUrl.isNotEmpty
                  ? (view._isLocalImagePath(imageUrl)
                        ? Image.file(
                            File(imageUrl.replaceFirst('file://', '')),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, url, error) => Icon(
                              view.widget.type == SharedListType.playlist
                                  ? Icons.playlist_play
                                  : Icons.album,
                              color: Colors.grey[600],
                              size: 64,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[800]),
                            errorWidget: (context, url, error) => Icon(
                              view.widget.type == SharedListType.playlist
                                  ? Icons.playlist_play
                                  : Icons.album,
                              color: Colors.grey[600],
                              size: 64,
                            ),
                          ))
                  : Icon(
                      view.widget.type == SharedListType.playlist
                          ? Icons.playlist_play
                          : Icons.album,
                      color: Colors.grey[600],
                      size: 64,
                    )),
      ),
    );
  }

  Widget _buildMobileMeta() {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          subtitleUser == null
              ? Text(
                  subtitle!,
                  style: TextStyle(color: Colors.grey[300], fontSize: 24),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                )
              : InkWell(
                  onTap: () => view._openUser(subtitleUser!),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
        ],
        const SizedBox(height: 4),
        Text(
          '$total songs • ${view._formatDuration(view._totalDurationSecs())}',
          style: TextStyle(color: Colors.grey[500], fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMobilePlaybackRow() {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isPlayingList =
            view._isCurrentListPlaying(player) && player.isPlaying;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 44,
              child: AspectRatio(
                aspectRatio: 1,
                child: IconButton.filled(
                  onPressed: view._items.isEmpty
                      ? null
                      : () {
                          view._toggleListShuffle(player);
                        },
                  icon: const Icon(CupertinoIcons.shuffle, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        view._preShuffleEnabled ||
                            (view._isCurrentListPlaying(player) &&
                                player.shuffleEnabled)
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor:
                        view._preShuffleEnabled ||
                            (view._isCurrentListPlaying(player) &&
                                player.shuffleEnabled)
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 44),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: view._items.isEmpty
                  ? null
                  : () {
                      if (view._isCurrentListPlaying(player)) {
                        view._toggleCurrentTrackPlayback(player);
                      } else {
                        view._playFromStart();
                      }
                    },
              icon: Icon(
                isPlayingList
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                size: 20,
              ),
              label: Text(
                isPlayingList ? 'Pause' : 'Play',
                style: const TextStyle(fontSize: 20),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 44),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: AspectRatio(
                aspectRatio: 1,
                child: IconButton.filled(
                  onPressed: view._items.isEmpty
                      ? null
                      : view._showListContextMenu,
                  icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 44),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDesktopPlaybackRow({required double availableWidth}) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isPlayingList =
            view._isCurrentListPlaying(player) && player.isPlaying;
        final useCompactControls = availableWidth < 625;

        Widget buildPlaybackButton({
          required VoidCallback? onPressed,
          required IconData icon,
          required String label,
          required bool isPrimary,
        }) {
          if (useCompactControls) {
            return FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Icon(icon, size: 20),
            );
          }

          return FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(
              enabledMouseCursor: SystemMouseCursors.click,
              disabledMouseCursor: SystemMouseCursors.basic,
              minimumSize: const Size(112, 40),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                buildPlaybackButton(
                  onPressed: view._items.isEmpty
                      ? null
                      : () {
                          if (view._isCurrentListPlaying(player)) {
                            view._toggleCurrentTrackPlayback(player);
                          } else {
                            view._playFromStart();
                          }
                        },
                  icon: isPlayingList
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  label: isPlayingList ? 'Pause' : 'Play',
                  isPrimary: true,
                ),
                SizedBox(width: useCompactControls ? 6 : 10),
                buildPlaybackButton(
                  onPressed: view._items.isEmpty
                      ? null
                      : () {
                          if (view._isCurrentListPlaying(player)) {
                            view._toggleListShuffle(player);
                          } else {
                            view._playFromStart(shuffle: true);
                          }
                        },
                  icon: CupertinoIcons.shuffle,
                  label: 'Shuffle',
                  isPrimary: false,
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    CupertinoIcons.share,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: view._showShareDialog,
                ),
                IconButton(
                  icon: Icon(
                    CupertinoIcons.pencil,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: view._showEditDialog,
                ),
                IconButton(
                  icon: Icon(
                    CupertinoIcons.arrow_down_to_line,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: view._isLoading ? null : view._downloadAll,
                ),
                Builder(
                  builder: (buttonContext) => IconButton(
                    icon: Icon(
                      CupertinoIcons.ellipsis,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () =>
                        view._showListContextMenu(anchorContext: buttonContext),
                    onLongPress: null,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
