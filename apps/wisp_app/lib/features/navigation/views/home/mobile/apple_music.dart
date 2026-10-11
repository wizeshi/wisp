// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/layout/mobile_bottom_padding.dart';
import '../home_view_data.dart';
import '../home_widgets.dart';

class MobileAppleMusicHome extends StatelessWidget {
  final HomeViewData data;
  final HomeViewActions actions;

  const MobileAppleMusicHome({
    super.key,
    required this.data,
    required this.actions,
  });

  List<Widget> _buildDynamicSections() {
    if (data.homeSections.isEmpty) return const [];
    final widgets = <Widget>[];

    final entries = data.homeSections.entries.toList(growable: false);
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i];
      if (entry.value.isEmpty) continue;
      if (i == 0) {
        entry = MapEntry('Recents', entry.value);
      }
      widgets.add(
        buildHomeSection(
          entry.key,
          entry.value,
          showTitle: true,
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final dynamicSections = _buildDynamicSections();

    return SafeArea(
      bottom: false,
      child: WispCustomScrollView(
        key: const PageStorageKey('home_mobile_apple'),
        controller: data.scrollController,
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
                      ...buildHomeMobileHeaderActions(
                        context,
                        actions,
                        useAppleIcon: true,
                      ),
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

