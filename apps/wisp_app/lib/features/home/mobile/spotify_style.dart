// Copyright © 2026 wizeshi

part of '../home_view.dart';

extension _MobileSpotifyStyle on HomePageState {
  Widget _buildMobileHomeContentSpotify() {
    final metadata = context.read<MetadataManager>();
    final greeting = _getRandomGreeting(metadata);
    final dynamicSections = _buildDynamicHomeSections(skipFirst: true);
    final quickTiles = _buildMobileQuickGridTiles();
    final leftQuickTiles = <Widget>[];
    final rightQuickTiles = <Widget>[];

    for (var i = 0; i < quickTiles.length; i++) {
      if (i.isEven) {
        leftQuickTiles.add(quickTiles[i]);
      } else {
        rightQuickTiles.add(quickTiles[i]);
      }
    }

    return SafeArea(
      bottom: false,
      child: WispCustomScrollView(
        key: const PageStorageKey('home_mobile_spotify'),
        controller: _scrollController,
        slivers: [
          // Header with settings icon
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      greeting,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ..._buildMobileHeaderActions(useAppleIcon: false),
                ],
              ),
            ),
          ),

          // 2-column grid for playlists and albums
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column - mixed quick tiles
                  Expanded(child: Column(children: leftQuickTiles)),
                  const SizedBox(width: 12),
                  // Right column - mixed quick tiles
                  Expanded(child: Column(children: rightQuickTiles)),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 4)),

          ...dynamicSections.map(
            (section) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: section,
              ),
            ),
          ),

          // Bottom padding
          const MobileBottomPaddingSliver(extra: 0),
        ],
      ),
    );
  }
}
