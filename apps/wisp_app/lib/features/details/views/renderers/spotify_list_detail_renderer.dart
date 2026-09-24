// Copyright © 2026 wizeshi

part of '../list_detail_view.dart';

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
      return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                WispSmoothScroll(
                  controller: view._mobileScrollController,
                  builder: (context, controller, physics) => CustomScrollView(
                    controller: controller,
                    physics: physics,
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
                    SliverLayoutBuilder(
                      builder: (sliverContext, sliverConstraints) {
                        // Real sliver, placed directly in this
                        // CustomScrollView's `slivers` list: Flutter's own
                        // viewport decides which rows to build, keep
                        // resident, and dispose as the user scrolls. We no
                        // longer track scroll offsets by hand or rebuild a
                        // manually-sliced window on every scroll tick.
                        return view._buildMobileSpotifySongsSliver(
                          availableWidth: sliverConstraints.crossAxisExtent,
                        );
                      },
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                        child: view._buildRecommendedSection(isMobile: true),
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
                  builder: (context, controller, physics) => ListView(
                    controller: controller,
                    physics: physics,
                    padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                    children: [
                    Container(
                      key: view._headerKey,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: stickyHeaderColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
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
                              stops: [0, 1],
                              colors: [actionsRowColor, contentSurfaceColor],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: contentSurfaceColor,
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: LayoutBuilder(
                          builder: (layoutContext, constraints) {
                            final availableWidth = constraints.maxWidth;
                            return Column(
                              children: [
                                view._buildListHeaderContent(
                                  availableWidth: availableWidth,
                                ),
                                const SizedBox(height: 2),
                                const Divider(),
                                AnimatedBuilder(
                                  animation: Listenable.merge([
                                    view._desktopScrollController,
                                    view._songListTopOffsetNotifier,
                                  ]),
                                  builder: (context, _) => view._buildSongList(
                                    isMobile: false,
                                    availableWidth: availableWidth,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: view._buildRecommendedSection(
                                    isMobile: false,
                                  ),
                                ),
                              ],
                            );
                          },
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

