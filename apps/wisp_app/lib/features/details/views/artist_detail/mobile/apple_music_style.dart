// Copyright © 2026 wizeshi

part of '../../artist_detail_view.dart';

extension _MobileAppleMusicStyle on _ArtistDetailViewState {
  Widget _buildMobileArtistContentApple({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
    return WispCustomScrollView(
      key: PageStorageKey('artist_mobile_apple_${widget.artistId}'),
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: _buildMobileAppleHero(
            imageUrl: imageUrl,
            name: name,
            followers: followers,
            monthlyListeners: _artist?.monthlyListeners,
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyActionBarDelegate(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF121212),
              child: _buildMobileActionsRow(useAppleIcons: true),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 26),
            child: Column(
              children: [
                _buildMobileAppleTopSongsGrid(),
                const SizedBox(height: 20),
                _buildMobileAppleAlbumsRow(),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildMobileAboutSection(),
                ),
              ],
            ),
          ),
        ),
        const MobileBottomPaddingSliver(extra: 0),
      ],
    );
  }

  Widget _buildMobileAppleHero({
    required String imageUrl,
    required String name,
    required int followers,
    required int? monthlyListeners,
  }) {
    final subtitle = (monthlyListeners != null && monthlyListeners > 0)
        ? '${_formatNumber(monthlyListeners)} monthly listeners'
        : '${_formatNumber(followers)} followers';

    return SizedBox(
      height: 430,
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
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black,
                ],
                stops: const [0, 0.72, 1],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      height: 1.04,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[300], fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
