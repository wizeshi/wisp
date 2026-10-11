// Copyright © 2026 wizeshi

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import '../home_view_data.dart';
import '../home_widgets.dart';

class DesktopSpotifyHome extends StatelessWidget {
  final HomeViewData data;
  final HomeViewActions actions;

  const DesktopSpotifyHome({
    super.key,
    required this.data,
    required this.actions,
  });

  Widget? _buildDesktopQuickRows() {
    if (data.homeSections.isEmpty) return null;
    final firstSection = data.homeSections.entries.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemsPerRow = (maxWidth / 220).floor().clamp(1, 4);
        final maxItems = min(itemsPerRow * 2, 8);
        final cards = firstSection.value
            .map<Widget?>((item) => buildHomeQuickTile(item, isMobile: false, actions: actions))
            .whereType<Widget>()
            .take(maxItems)
            .toList();
        if (cards.isEmpty) return const SizedBox.shrink();

        final rowCount = ((cards.length + itemsPerRow - 1) / itemsPerRow).floor();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int row = 0; row < rowCount; row++)
              Padding(
                padding: EdgeInsets.only(bottom: row == rowCount - 1 ? 24 : 16),
                child: Row(
                  children: List.generate(itemsPerRow, (col) {
                    final index = row * itemsPerRow + col;
                    final item = index < cards.length
                        ? cards[index]
                        : const SizedBox.shrink();
                    if (col == itemsPerRow - 1) {
                      return Expanded(child: item);
                    }
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: item,
                      ),
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildDynamicSections({
    bool skipFirst = false,
    Set<int> skipEntryIndexes = const <int>{},
    bool allowSpecialCardStyle = true,
  }) {
    if (data.homeSections.isEmpty) return const [];
    final widgets = <Widget>[];

    final entries = (skipFirst
            ? data.homeSections.entries.skip(1)
            : data.homeSections.entries)
        .toList(growable: false);

    for (var i = 0; i < entries.length; i++) {
      if (skipEntryIndexes.contains(i)) continue;
      var entry = entries[i];
      if (entry.value.isEmpty) continue;
      if (!skipFirst && i == 0) {
        entry = MapEntry('Recents', entry.value);
      }
      final useSpecialCardStyle = allowSpecialCardStyle &&
          i == 0 &&
          entry.key.trim().toLowerCase() == 'new music';
      widgets.add(
        buildHomeSection(
          entry.key,
          entry.value,
          showTitle: !useSpecialCardStyle,
          expandCardsToRowWidth: useSpecialCardStyle,
          useSpecialCardStyle: useSpecialCardStyle,
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final viewWidth = MediaQuery.sizeOf(context).width;
    const minWidthForSpecialCard = 1600.0;
    final canShowSpecialCard = viewWidth >= minWidthForSpecialCard;

    final quickRows = _buildDesktopQuickRows();
    final dynamicEntries = ((quickRows != null)
            ? data.homeSections.entries.skip(1)
            : data.homeSections.entries)
        .toList(growable: false);

    final newMusicIndex = dynamicEntries.indexWhere(
      (entry) => entry.key.trim().toLowerCase() == 'new music',
    );
    final shouldShowNewMusicSpecialCard = canShowSpecialCard &&
        newMusicIndex >= 0 &&
        dynamicEntries[newMusicIndex].value.isNotEmpty;
    final rightSectionIndex = (newMusicIndex == 0 && dynamicEntries.length > 1)
        ? 1
        : 0;

    final firstDynamicSectionItems =
        (dynamicEntries.isNotEmpty && rightSectionIndex < dynamicEntries.length)
            ? dynamicEntries[rightSectionIndex].value
            : const <dynamic>[];
    final firstDynamicSectionWidget =
        dynamicEntries.isNotEmpty && firstDynamicSectionItems.isNotEmpty
            ? buildHomeSection(
                dynamicEntries[rightSectionIndex].key,
                firstDynamicSectionItems,
                showTitle: !shouldShowNewMusicSpecialCard,
              )
            : null;

    final newMusicSpecialCard = shouldShowNewMusicSpecialCard
        ? buildHomeCard(
            dynamicEntries[newMusicIndex].value.first,
            useSpecialCardStyle: true,
          )
        : null;

    final skipDynamicIndexes = <int>{};
    if (firstDynamicSectionWidget != null &&
        dynamicEntries.isNotEmpty &&
        rightSectionIndex < dynamicEntries.length) {
      skipDynamicIndexes.add(rightSectionIndex);
    }
    if (newMusicSpecialCard != null && newMusicIndex >= 0) {
      skipDynamicIndexes.add(newMusicIndex);
    }

    final dynamicSections = _buildDynamicSections(
      skipFirst: quickRows != null,
      skipEntryIndexes: skipDynamicIndexes,
      allowSpecialCardStyle: canShowSpecialCard,
    );

    return WispListView(
      key: const PageStorageKey('home_desktop_spotify'),
      controller: data.scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          data.greeting,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        ?quickRows,
        if (newMusicSpecialCard != null && firstDynamicSectionWidget != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: SizedBox(height: 230, child: newMusicSpecialCard),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: firstDynamicSectionWidget),
            ],
          )
        else if (newMusicSpecialCard != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: newMusicSpecialCard,
          )
        else
          ?firstDynamicSectionWidget,
        ...dynamicSections,
      ],
    );
  }
}

