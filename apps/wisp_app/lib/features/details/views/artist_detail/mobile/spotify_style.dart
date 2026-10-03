// Copyright © 2026 wizeshi

part of '../../artist_detail_view.dart';

extension _MobileSpotifyStyle on _ArtistDetailViewState {
  Widget _buildMobileArtistContentSpotify({
    required String imageUrl,
    required String name,
    required int followers,
  }) {
    const padding = 20.0;
    return Column(
      children: [
        Expanded(
          child: WispCustomScrollView(
            key: PageStorageKey('artist_mobile_spotify_${widget.artistId}'),
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(padding),
                  child: _buildMobileHeader(
                    name,
                    imageUrl,
                    followers,
                    _artist?.monthlyListeners,
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyActionBarDelegate(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: padding,
                      vertical: padding / 2,
                    ),
                    color: const Color(0xFF121212),
                    child: _buildMobileActionsRow(useAppleIcons: false),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildTopTracksSection(),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      child: SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: padding),
                      child: _buildAlbumsGrid(false),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: padding),
                  child: _buildAboutSection(isMobile: true),
                ),
              ),
              const MobileBottomPaddingSliver(extra: 0),
            ],
          ),
        ),
      ],
    );
  }
}
