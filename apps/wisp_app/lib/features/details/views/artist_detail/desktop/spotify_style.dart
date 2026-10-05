// Copyright © 2026 wizeshi

part of '../../artist_detail_view.dart';

extension _DesktopSpotifyStyle on _ArtistDetailViewState {
  Widget _buildDesktopArtistContentSpotify({
    required String imageUrl,
    required String name,
    required int followers,
    required String description,
    required Color headerColor,
    required Color actionsRowColor,
  }) {
    final theme = Theme.of(context);
    final contentSurfaceColor = theme.colorScheme.surface;
    final monthlyListeners = _artist?.monthlyListeners;
    final displayDescription = description.isEmpty
        ? 'No description available for this artist yet.'
        : description;
    final hasAlbums = (_artist?.albums ?? []).isNotEmpty;

    return Stack(
      children: [
        Positioned.fill(child: Container(color: contentSurfaceColor)),
        SafeArea(
          bottom: false,
          child: WispListView(
            key: PageStorageKey('artist_desktop_spotify_${widget.artistId}'),
            controller: _scrollController,
            padding: EdgeInsets.zero,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(color: headerColor),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ClipOval(
                        child: Container(
                          width: 180,
                          height: 180,
                          color: Colors.black.withValues(alpha: 0.18),
                          child: imageUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => Icon(
                                    CupertinoIcons.person_fill,
                                    color: Colors.grey[700],
                                    size: 54,
                                  ),
                                )
                              : Icon(
                                  CupertinoIcons.person_fill,
                                  color: Colors.grey[700],
                                  size: 54,
                                ),
                        ),
                      ),
                      const SizedBox(width: 28),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 58,
                              height: 0.95,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            monthlyListeners != null && monthlyListeners > 0
                                ? '${_formatNumber(monthlyListeners)} monthly listeners'
                                : '${_formatNumber(followers)} followers',
                            style: TextStyle(
                              color: Colors.grey[200],
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _buildActionsRow(
                useAppleIcons: false,
                backgroundGradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 1],
                  colors: [actionsRowColor, contentSurfaceColor],
                ),
              ),
              Container(
                width: double.infinity,
                color: contentSurfaceColor,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopTracksSection(
                      title: 'Popular',
                      spotifyStyle: true,
                    ),
                    const SizedBox(height: 28),
                    if (hasAlbums) ...[
                      _buildSpotifyAlbumsSection(isDesktop: true),
                      const SizedBox(height: 28),
                    ],
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About $name',
                            style: const TextStyle(
                              fontSize: 31,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: buildParsedText(
                                   context,
                                  displayDescription,
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 15,
                                    height: 1.45,
                                  ),
                                  softWrap: true,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (monthlyListeners != null &&
                                        monthlyListeners > 0)
                                      _buildAboutStat(
                                        'MONTHLY LISTENERS',
                                        _formatNumber(monthlyListeners),
                                      ),
                                    _buildAboutStat(
                                      'FOLLOWERS',
                                      _formatNumber(followers),
                                    ),
                                    _buildAboutStat(
                                      'ALBUMS',
                                      '${_artist?.albums.length ?? 0}',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
