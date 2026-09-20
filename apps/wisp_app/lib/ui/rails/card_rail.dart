import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// A horizontally scrolling row of cards, with a title header, edge fade,
/// and hover-revealed scroll arrows on desktop.
///
/// This replaces three near-identical, independently built horizontal
/// scrollers (`_ScrollableCardSection` in home.dart, `_HorizontalRailSection`
/// in search.dart, `_HorizontalScrollableSection` in user_detail.dart) —
/// none of which virtualized their contents. All three laid every card out
/// via `SingleChildScrollView` + `Row`, so every card in every rail stayed
/// alive and laid out even while scrolled far off-screen.
///
/// `CardRail` builds items lazily with `ListView.builder` instead: pass
/// raw [items] and an [itemBuilder] that constructs a card from one item,
/// rather than a pre-built `List<Widget>`. Building cards is deferred to
/// exactly the items near the viewport — swap in `TrackCard`/`AlbumCard`/
/// etc. as the builder for each entity type.
class CardRail<T> extends StatefulWidget {
  final String title;
  final bool showTitle;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Width of each item. Used to size scroll steps and, when
  /// [expandItemsToRailWidth] is set, ignored in favor of the rail's own
  /// width. Should match the width the [itemBuilder]'s cards render at.
  final double itemWidth;

  /// Height reserved for the horizontally-scrolling row itself. A
  /// horizontal `ListView` (unlike `SingleChildScrollView`) always defers
  /// to whatever height its parent provides rather than sizing itself to
  /// its children — and since `CardRail` normally sits inside a vertically
  /// scrolling parent (which gives it *unbounded* height), it must be told
  /// an explicit height rather than trying to infer one.
  ///
  /// Defaults to a value that fits [GenericCard] at [itemWidth] (its
  /// square artwork, plus its padding/title/subtitle rows below). If the
  /// [itemBuilder] renders a different shape — e.g. [SpecialCard] via
  /// [expandItemsToRailWidth] — pass the height that shape actually needs
  /// instead of relying on the default.
  final double itemHeight;

  final double itemSpacing;

  /// When true, each item takes the full width of the rail instead of
  /// [itemWidth] — for a rail that's really just one full-bleed item at a
  /// time (e.g. a single promotional `SpecialCard`) rather than a strip of
  /// same-size cards.
  final bool expandItemsToRailWidth;

  const CardRail({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.showTitle = true,
    this.itemWidth = 160,
    double? itemHeight,
    this.itemSpacing = 12,
    this.expandItemsToRailWidth = false,
  }) : itemHeight = itemHeight ?? itemWidth + 52;

  @override
  State<CardRail<T>> createState() => _CardRailState<T>();
}

class _CardRailState<T> extends State<CardRail<T>> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void didUpdateWidget(CardRail<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final maxExtent = _controller.position.maxScrollExtent;
    final offset = _controller.offset;
    final canLeft = offset > 4;
    final canRight = offset < (maxExtent - 4);
    if (canLeft == _canScrollLeft && canRight == _canScrollRight) return;
    setState(() {
      _canScrollLeft = canLeft;
      _canScrollRight = canRight;
    });
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final isDesktop = _isDesktop;
    final showArrows = isDesktop && _isHovered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        SizedBox(
          height: widget.itemHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return MouseRegion(
                cursor: SystemMouseCursors.basic,
                onEnter: isDesktop
                    ? (_) => setState(() => _isHovered = true)
                    : null,
                onExit: isDesktop
                    ? (_) => setState(() => _isHovered = false)
                    : null,
                child: Stack(
                  children: [
                    ListView.separated(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 4),
                      itemCount: widget.items.length,
                      separatorBuilder: (context, index) =>
                          SizedBox(width: widget.itemSpacing),
                      itemBuilder: (context, index) {
                        final card = widget.itemBuilder(
                          context,
                          widget.items[index],
                        );
                        return widget.expandItemsToRailWidth
                            ? SizedBox(width: constraints.maxWidth, child: card)
                            : SizedBox(width: widget.itemWidth, child: card);
                      },
                    ),
                    if (_canScrollRight)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Container(
                            width: 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.transparent,
                                  const Color(
                                    0xFF121212,
                                  ).withValues(alpha: 0.78),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showArrows && _canScrollLeft)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _ScrollArrowButton(
                            icon: Icons.chevron_left,
                            onPressed: () => _scrollBy(-widget.itemWidth * 1.5),
                          ),
                        ),
                      ),
                    if (showArrows && _canScrollRight)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _ScrollArrowButton(
                            icon: Icons.chevron_right,
                            onPressed: () => _scrollBy(widget.itemWidth * 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(height: isDesktop ? 16 : 4),
      ],
    );
  }
}

class _ScrollArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ScrollArrowButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        splashRadius: 18,
      ),
    );
  }
}
