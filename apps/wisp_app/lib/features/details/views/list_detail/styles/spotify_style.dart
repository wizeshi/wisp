// Copyright © 2026 wizeshi

part of '../../list_detail_view.dart';

class _SpotifyListDetailRenderer extends StatelessWidget {
  final _SharedListDetailViewState view;
  final String title;
  final String? subtitle;
  final GenericSimpleUser? subtitleUser;
  final String imageUrl;
  final String? subtitleImageUrl;
  final int total;
  final bool isDesktop;
  final String? description;

  const _SpotifyListDetailRenderer({
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
    final isMobile = !isDesktop;
    final padding = isMobile ? 12.0 : 24.0;

    if (isMobile) {
      view._scheduleStickyBarUpdate(view._mobileScrollController);
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    CustomScrollView(
                      key: PageStorageKey('spotify_mobile_${view.widget.type}_${view.widget.id}'),
                      controller: view._mobileScrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Container(
                            key: view._headerKey,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                padding,
                                padding,
                                padding,
                                0,
                              ),
                              child: view._buildMobileHeader(
                                title,
                                subtitle,
                                subtitleUser,
                                imageUrl,
                                total,
                                description,
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Container(
                            key: view._mobileActionsKey,
                            padding: EdgeInsets.symmetric(
                              horizontal: padding / 2,
                              vertical: 4,
                            ),
                            color: const Color(0xFF121212),
                            child: view._buildMobileActionsRow(),
                          ),
                        ),
                        view._buildSongsSliver(
                          availableWidth: availableWidth,
                          isMobile: true,
                          visualStyle: AppStyle.Spotify,
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                            child: view._buildRecommendedSection(isMobile: true),
                          ),
                        ),
                        const MobileBottomPaddingSliver(extra: 0),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    view._scheduleStickyBarUpdate(view._desktopScrollController);
    final stickyHeaderColor = view._stickyBarColor;
    final stickyHeaderColorHSL = HSLColor.fromColor(stickyHeaderColor);
    final actionsRowColor = stickyHeaderColorHSL
        .withLightness(stickyHeaderColorHSL.lightness * 0.5)
        .toColor();

    final contentSurfaceColor = Theme.of(context).colorScheme.surface;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.2, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.82),
                  Colors.black.withValues(alpha: 0.36),
                  Colors.black.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: WispSmoothScroll(
                  controller: view._desktopScrollController,
                  builder: (context, controller, physics) => CustomScrollView(
                    key: PageStorageKey('spotify_desktop_${view.widget.type}_${view.widget.id}'),
                    controller: controller,
                    physics: physics,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Container(
                          key: view._headerKey,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: stickyHeaderColor,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Column(
                            children: [
                              view._buildHeader(
                                title,
                                subtitle,
                                subtitleUser,
                                subtitleImageUrl,
                                imageUrl,
                                total,
                                description,
                              ),
                              const SizedBox(height: 12),
                              view._buildActionsRow(
                                isDesktop,
                                backgroundGradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: const [0, 1],
                                  colors: [actionsRowColor, contentSurfaceColor],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: ColoredBox(
                          color: contentSurfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: LayoutBuilder(
                              builder: (layoutContext, constraints) {
                                return Column(
                                  children: [
                                    view._buildListHeaderContent(
                                      availableWidth: constraints.maxWidth,
                                    ),
                                    const SizedBox(height: 2),
                                    const Divider(),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      SliverLayoutBuilder(
                        builder: (sliverContext, sliverConstraints) {
                          return DecoratedSliver(
                            decoration: BoxDecoration(color: contentSurfaceColor),
                            sliver: SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              sliver: view._buildSongsSliver(
                                availableWidth: sliverConstraints.crossAxisExtent - 24,
                                isMobile: false,
                                visualStyle: AppStyle.Spotify,
                              ),
                            ),
                          );
                        },
                      ),
                      SliverToBoxAdapter(
                        child: ColoredBox(
                          color: contentSurfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            child: view._buildRecommendedSection(
                              isMobile: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ),
            ],
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
}

