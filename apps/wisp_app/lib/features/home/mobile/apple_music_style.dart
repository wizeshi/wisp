// Copyright © 2026 wizeshi

part of '../home_view.dart';

extension _MobileAppleMusicStyle on HomePageState {
  Widget _buildMobileHomeContentApple() {
    final dynamicSections = _buildDynamicHomeSections(skipFirst: false);

    return SafeArea(
      bottom: false,
      child: WispCustomScrollView(
        key: const PageStorageKey('home_mobile_apple'),
        controller: _scrollController,
        slivers: [
          // iOS-style Large Title Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Home',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      ..._buildMobileHeaderActions(useAppleIcon: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Divider(color: Colors.white12, height: 1),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

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
