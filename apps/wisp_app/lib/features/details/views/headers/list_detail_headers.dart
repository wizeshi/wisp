// Copyright © 2026 wizeshi

part of '../list_detail_view.dart';

extension _ListDetailHeaders on _SharedListDetailViewState {
  Widget _buildMobileHeader(
    String title,
    String? subtitle,
    GenericSimpleUser? subtitleUser,
    String imageUrl,
    int total,
    String? description,
  ) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final isLiked =
        widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(widget.id);
    return Column(
      children: [
        // Album art - 70% width as per old design
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.grey[900],
                  child: isLiked
                      ? const LikedSongsArt()
                      : (imageUrl.isNotEmpty
                            ? (_isLocalImagePath(imageUrl)
                                  ? Image.file(
                                      File(
                                        imageUrl.replaceFirst('file://', ''),
                                      ),
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (context, url, error) =>
                                          Icon(
                                            widget.type ==
                                                    SharedListType.playlist
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
                                      placeholder: (context, url) => Container(
                                        color: Colors.grey[800],
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Icon(
                                            widget.type ==
                                                    SharedListType.playlist
                                                ? Icons.playlist_play
                                                : Icons.album,
                                            color: Colors.grey[600],
                                            size: 64,
                                          ),
                                    ))
                            : Icon(
                                widget.type == SharedListType.playlist
                                    ? Icons.playlist_play
                                    : Icons.album,
                                color: Colors.grey[600],
                                size: 64,
                              )),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Title and info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    Text(
                      ' • ',
                      style: TextStyle(color: Colors.grey[500], fontSize: 20),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: subtitleUser == null
                            ? null
                            : () => _openUser(subtitleUser),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: subtitleUser == null
                                ? Colors.grey[400]
                                : Colors.white,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_totalDurationSecs()),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  Text(' • ', style: TextStyle(color: Colors.grey[500])),
                  Text(
                    '$total songs',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
              if (hasDescription) ...[
                const SizedBox(height: 6),
                buildParsedText(
                  context,
                  descriptionText,
                  linkStyle: TextStyle(color: Colors.grey[300], fontSize: 13),
                  style: TextStyle(color: Colors.grey[300], fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileActionsRow() {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final isCurrentListActive = _isCurrentListPlaying(player);
        final shuffleActive = (isCurrentListActive
            ? player.shuffleEnabled
            : _preShuffleEnabled);
        final repeatActive =
            player.repeatMode != global_audio_player.RepeatMode.off;

        final playerIsPlaying = context.select<PlaybackCoordinator, bool>(
          (coordinator) => coordinator.effectiveIsPlaying,
        );
        final playlistIsPlaying = playerIsPlaying && isCurrentListActive;

        return SizedBox(
          height: 56,
          child: Row(
            children: [
              // Left side: Download + More
              IconButton(
                icon: const Icon(Icons.download_outlined),
                color: Colors.white,
                onPressed: () => _downloadAll(),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz),
                color: Colors.white,
                onPressed: () => _showListContextMenu(),
              ),
              const Spacer(),
              // Right side: Loop + Shuffle + Play
              IconButton(
                icon: Icon(
                  player.repeatMode == global_audio_player.RepeatMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                ),
                color: repeatActive ? colorScheme.primary : Colors.white,
                onPressed: () {
                  context.read<PlaybackCoordinator>().toggleRepeat();
                },
              ),
              IconButton(
                icon: const Icon(Icons.shuffle),
                color: shuffleActive ? colorScheme.primary : Colors.white,
                onPressed: () => _toggleListShuffle(player),
              ),
              const SizedBox(width: 8),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    playlistIsPlaying ? Icons.pause : Icons.play_arrow,
                    size: 32,
                  ),
                  color: colorScheme.onPrimary,
                  onPressed: () {
                    if (isCurrentListActive) {
                      playerIsPlaying
                          ? context.read<PlaybackCoordinator>().pause()
                          : context.read<PlaybackCoordinator>().play();
                    } else {
                      if (_items.isNotEmpty) {
                        _playFromStart();
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    String title,
    String? subtitle,
    GenericSimpleUser? subtitleUser,
    String? subtitleImageUrl,
    String imageUrl,
    int total,
    String? description,
  ) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final isLiked =
        widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(widget.id);

    final headerHeight = (MediaQuery.of(context).size.width * 0.125).clamp(
      200,
      double.infinity,
    );

    final baseFontSize = (MediaQuery.of(context).size.width * 0.00075).clamp(
      1,
      double.infinity,
    );

    return Container(
      width: double.infinity,
      height: headerHeight.toDouble(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      decoration: const BoxDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: isLiked
                  ? const LikedSongsArt()
                  : (imageUrl.isNotEmpty
                        ? (_isLocalImagePath(imageUrl)
                              ? Image.file(
                                  File(imageUrl.replaceFirst('file://', '')),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, url, error) =>
                                      Container(color: Colors.grey[800]),
                                )
                              : CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: Colors.grey[800]),
                                ))
                        : Icon(
                            widget.type == SharedListType.playlist
                                ? Icons.playlist_play
                                : Icons.album,
                            color: Colors.grey[600],
                            size: 48,
                          )),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  widget.type == SharedListType.playlist ? 'PLAYLIST' : 'ALBUM',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (52 * baseFontSize).toDouble(),
                    height: 0.95,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasDescription) const SizedBox(height: 4),
                if (hasDescription)
                  buildParsedText(
                    context,
                    descriptionText,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                    linkStyle: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (subtitleImageUrl != null) ...[
                      MouseRegion(
                        cursor: subtitleUser == null
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: subtitleUser == null
                              ? null
                              : () => _openUser(subtitleUser),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 24,
                              height: 24,
                              color: Colors.grey[900],
                              child: _isLocalImagePath(subtitleImageUrl)
                                  ? Image.file(
                                      File(
                                        subtitleImageUrl.replaceFirst(
                                          'file://',
                                          '',
                                        ),
                                      ),
                                      filterQuality: FilterQuality.medium,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, url, error) =>
                                          Container(color: Colors.grey[800]),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: subtitleImageUrl,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.medium,
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[800]),
                                      errorWidget: (context, url, error) =>
                                          Container(color: Colors.grey[800]),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (subtitle != null)
                      Flexible(
                        child: subtitleUser == null
                            ? Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : HoverUnderline(
                                onTap: () => _openUser(subtitleUser),
                                builder: (isHovering) => Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    decoration: isHovering
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '•',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
                    Text(
                      '$total songs',
                      style: TextStyle(color: Colors.grey[300], fontSize: 15),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '•',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                    Text(
                      _formatDuration(_totalDurationSecs()),
                      style: TextStyle(color: Colors.grey[300], fontSize: 15),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow(bool isDesktop, {Gradient? backgroundGradient}) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final shuffleActive = (_isCurrentListPlaying(player)
            ? player.shuffleEnabled
            : _preShuffleEnabled);
        final repeatActive =
            player.repeatMode != global_audio_player.RepeatMode.off;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(gradient: backgroundGradient),
          alignment: Alignment.bottomLeft,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowWidth = math.max(constraints.maxWidth, 920.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: SizedBox(
                    width: rowWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 54,
                              height: 54,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: FilledButton(
                                  onPressed: () {
                                    if (!_isLoading) {
                                      if (_isCurrentListPlaying(player)) {
                                        _toggleCurrentTrackPlayback(player);
                                      } else {
                                        _playFromStart();
                                      }
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    enabledMouseCursor:
                                        SystemMouseCursors.click,
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    padding: EdgeInsets.zero,
                                    shape: const CircleBorder(),
                                  ),
                                  child: Icon(
                                    _isCurrentListPlaying(player) &&
                                            player.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                _toggleListShuffle(player);
                              },
                              icon: Icon(
                                Icons.shuffle,
                                color: shuffleActive
                                    ? colorScheme.primary
                                    : Colors.white70,
                              ),
                            ),
                            IconButton(
                              onPressed: player.toggleRepeat,
                              icon: Icon(
                                player.repeatMode ==
                                        global_audio_player.RepeatMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                color: repeatActive
                                    ? colorScheme.primary
                                    : Colors.white70,
                              ),
                            ),
                            IconButton(
                              onPressed: _isLoading ? null : _downloadAll,
                              icon: const Icon(
                                Icons.download,
                                color: Colors.white70,
                              ),
                            ),
                            Builder(
                              builder: (buttonContext) {
                                return IconButton(
                                  onPressed: () {
                                    if (isDesktop) {
                                      _showListContextMenu(
                                        anchorContext: buttonContext,
                                      );
                                    } else {
                                      _showListContextMenu();
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.more_horiz,
                                    color: Colors.white70,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              width: _showSearch ? 12 : 0,
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              width: _showSearch ? (isDesktop ? 240 : 160) : 0,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 160),
                                opacity: _showSearch ? 1 : 0,
                                child: IgnorePointer(
                                  ignoring: !_showSearch,
                                  child: TextField(
                                    onChanged: (value) {
                                      _safeSetState(() {
                                        _searchQuery = value;
                                        _rebuildIndices();
                                      });
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Search in list',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                _safeSetState(() {
                                  _showSearch = !_showSearch;
                                  if (!_showSearch) {
                                    _searchQuery = '';
                                    _rebuildIndices();
                                  }
                                });
                              },
                              icon: Icon(
                                Icons.search,
                                color: _showSearch
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey[300],
                              ),
                            ),
                            const SizedBox(width: 8),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: DropdownButton<_SortMethod>(
                                value: _sortMethod,
                                mouseCursor: SystemMouseCursors.click,
                                dropdownColor: Colors.grey[900],
                                underline: const SizedBox.shrink(),
                                items: const [
                                  DropdownMenuItem(
                                    value: _SortMethod.position,
                                    child: Text('Index'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.title,
                                    child: Text('Title'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.author,
                                    child: Text('Author'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.album,
                                    child: Text('Album'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.addedAt,
                                    child: Text('Date Added'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.duration,
                                    child: Text('Duration'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.source,
                                    child: Text('Source'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _sortBy(value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStickyNowPlayingBar({
    required String title,
    required bool isDesktop,
  }) {
    final textColor = _stickyBarColor.computeLuminance() < 0.45
        ? Colors.white
        : Colors.black;
    final colorScheme = Theme.of(context).colorScheme;
    final barMargin = isDesktop
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 16);

    return AnimatedSlide(
      offset: _showStickyBar ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showStickyBar ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        child: Container(
          height: isDesktop ? 58 : 52,
          margin: barMargin,
          decoration: BoxDecoration(
            color: _stickyBarColor.withValues(alpha: isDesktop ? 0.96 : 0.92),
            borderRadius: BorderRadius.circular(isDesktop ? 0 : 14),
            boxShadow: isDesktop
                ? const []
                : const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            children: [
              SizedBox(width: isDesktop ? 14 : 6),
              Consumer<global_audio_player.WispAudioHandler>(
                builder: (context, player, child) {
                  final isPlayingList = _isCurrentListPlaying(player);
                  final isPlaying = isPlayingList && player.isPlaying;
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: Material(
                      color: colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          if (_items.isEmpty) return;
                          if (isPlayingList) {
                            _toggleCurrentTrackPlayback(player);
                          } else {
                            _playFromStart();
                          }
                        },
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: colorScheme.onPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: isDesktop ? 24 : 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortableHeader({
    required String text,
    required _SortMethod method,
    TextAlign textAlign = TextAlign.left,
    VoidCallback? onTap,
    // Zero this out (keep vertical for tap-target height / hover highlight)
    // when this header sits directly above a TrackRow column whose content
    // has no matching inset — otherwise the label sits ~4px off from the
    // row content it's labeling, even though the column widths match.
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
  }) {
    final headerStyle = TextStyle(color: Colors.grey[400], fontSize: 12);
    final isSorted = _sortMethod == method;
    final sortIcon = isSorted
        ? Icon(
            _ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: Colors.white,
          )
        : null;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: textAlign == TextAlign.right
          ? MainAxisAlignment.end
          : textAlign == TextAlign.center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Text(
          text,
          style: isSorted
              ? headerStyle.copyWith(color: Colors.white)
              : headerStyle,
        ),
        if (sortIcon != null) ...[const SizedBox(width: 4), sortIcon],
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap ?? () => _sortBy(method),
          child: Padding(padding: padding, child: content),
        ),
      ),
    );
  }

  Widget _buildListHeaderContent({
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
    required double availableWidth,
  }) {
    final visibleColumns = _getVisibleColumns(availableWidth);

    if (visualStyle == _ListVisualStyle.apple) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Align(
                alignment: Alignment.center,
                child: _buildSortableHeader(
                  text: '#',
                  method: _SortMethod.position,
                  textAlign: TextAlign.center,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const SizedBox(width: 44),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildSortableHeader(
                  text: 'Song',
                  method: _SortMethod.title,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                ),
              ),
            ),
            // Artist column - shown when artist column should be visible
            if (visibleColumns.showArtistColumn)
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSortableHeader(
                    text: 'Artist',
                    method: _SortMethod.author,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
              ),
            // Album column - hidden at smaller widths
            if (visibleColumns.showAlbum)
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSortableHeader(
                    text: 'Album',
                    method: _SortMethod.album,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
              ),
            // Time column - hidden at smallest width
            if (visibleColumns.showTime) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildSortableHeader(
                    text: 'Time',
                    method: _SortMethod.duration,
                    textAlign: TextAlign.right,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
              ),
            ],
            const SizedBox(
              width: 48,
            ), // Space for more context menu button
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.center,
              child: _buildSortableHeader(
                text: '#',
                method: _SortMethod.position,
                textAlign: TextAlign.center,
                padding: const EdgeInsets.symmetric(vertical: 2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 44),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildSortableHeader(
                text: _sortMethod == _SortMethod.author ? 'Author' : 'Title',
                method: _SortMethod.author == _sortMethod
                    ? _SortMethod.author
                    : _SortMethod.title,
                onTap: _handleTitleHeaderTap,
                padding: const EdgeInsets.symmetric(vertical: 2),
              ),
            ),
          ),
          if (widget.type == SharedListType.playlist &&
              visibleColumns.showAlbum)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildSortableHeader(
                  text: 'Album',
                  method: _SortMethod.album,
                  textAlign: TextAlign.left,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                ),
              ),
            ),
          if (widget.type == SharedListType.playlist &&
              visibleColumns.showAddedAt)
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildSortableHeader(
                  text: 'Added',
                  method: _SortMethod.addedAt,
                  textAlign: TextAlign.left,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                ),
              ),
            ),
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildSortableHeader(
                text: 'Time',
                method: _SortMethod.duration,
                textAlign: TextAlign.right,
                padding: const EdgeInsets.symmetric(vertical: 2),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildSortableHeader(
                text: '',
                method: _SortMethod.source,
                textAlign: TextAlign.right,
                padding: const EdgeInsets.symmetric(vertical: 2),
              ),
            ),
          ),
          const SizedBox(
            width: 48,
          ), // Space for more context menu button
        ],
      ),
    );
  }
}

