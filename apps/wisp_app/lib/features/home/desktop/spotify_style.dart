// Copyright © 2026 wizeshi

part of '../home_view.dart';

extension _DesktopSpotifyStyle on HomePageState {
  Widget _buildDesktopHomeContentSpotify() {
    final viewWidth = MediaQuery.sizeOf(context).width;
    const minWidthForSpecialCard = 1600.0;
    final canShowSpecialCard = viewWidth >= minWidthForSpecialCard;

    final quickRows = _buildDesktopQuickRows();
    final dynamicEntries =
        ((quickRows != null)
                ? _homeSections.entries.skip(1)
                : _homeSections.entries)
            .toList(growable: false);

    final newMusicIndex = dynamicEntries.indexWhere(
      (entry) => entry.key.trim().toLowerCase() == 'new music',
    );
    final shouldShowNewMusicSpecialCard =
        canShowSpecialCard &&
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
        ? _buildSection(
            dynamicEntries[rightSectionIndex].key,
            firstDynamicSectionItems,
            showTitle: !shouldShowNewMusicSpecialCard,
          )
        : null;

    final newMusicSpecialCard = shouldShowNewMusicSpecialCard
        ? _buildHomeCard(
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

    final dynamicSections = _buildDynamicHomeSections(
      skipFirst: quickRows != null,
      skipEntryIndexes: skipDynamicIndexes,
      allowSpecialCardStyle: canShowSpecialCard,
    );
    return WispListView(
      key: const PageStorageKey('home_desktop_spotify'),
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          _getRandomGreeting(context.read<MetadataManager>()),
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
