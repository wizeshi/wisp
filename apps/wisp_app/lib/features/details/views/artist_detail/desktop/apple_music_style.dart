// Copyright © 2026 wizeshi

part of '../../artist_detail_view.dart';

extension _DesktopAppleMusicStyle on _ArtistDetailViewState {
  Widget _buildDesktopArtistContentApple({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
    final hasTopSongs = (_artist?.topSongs ?? []).isNotEmpty;
    final hasAlbums = (_artist?.albums ?? []).isNotEmpty;

    return Stack(
      children: [
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Opacity(
                opacity: 0.35,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      Container(color: Colors.grey[900]),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.9),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: WispCustomScrollView(
            key: PageStorageKey('artist_desktop_apple_${widget.artistId}'),
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildDesktopHero(
                    name,
                    imageUrl,
                    followers,
                    _artist?.monthlyListeners,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasTopSongs) ...[
                        _buildDesktopTopSongsSection(),
                        const SizedBox(height: 36),
                      ],
                      if (hasAlbums) ...[
                        _buildAlbumsGrid(true),
                        const SizedBox(height: 36),
                      ],
                      _buildAboutSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHero(
    String name,
    String imageUrl,
    int followers,
    int? monthlyListeners,
  ) {
    final subtitle = (monthlyListeners != null && monthlyListeners > 0)
        ? '${_formatNumber(monthlyListeners)} monthly listeners'
        : '${_formatNumber(followers)} followers';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 360,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    Container(color: Colors.grey[900]),
              )
            else
              Container(color: Colors.grey[900]),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                  stops: const [0, 0.62, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[300], fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  _buildActionsRow(useAppleIcons: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
