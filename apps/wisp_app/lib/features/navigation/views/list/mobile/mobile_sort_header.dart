// Copyright © 2026 wizeshi

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';

import '../view.dart' show ListSortMethod, SharedListType;

/// Horizontal sort mode header bar shown above mobile playlist/album tracks.
class MobileListSortHeader extends StatelessWidget {
  final SharedListType type;
  final ListSortMethod sortMethod;
  final bool sortAscending;
  final ValueChanged<ListSortMethod> onSort;
  final AppStyle style;

  const MobileListSortHeader({
    super.key,
    required this.type,
    required this.sortMethod,
    required this.sortAscending,
    required this.onSort,
    required this.style,
  });

  List<({ListSortMethod method, String label})> get _options {
    return [
      (method: ListSortMethod.title, label: 'Title'),
      (method: ListSortMethod.author, label: 'Artist'),
      if (type == SharedListType.playlist) ...[
        (method: ListSortMethod.album, label: 'Album'),
        (method: ListSortMethod.addedAt, label: 'Date added'),
      ],
      (method: ListSortMethod.duration, label: 'Duration'),
    ];
  }

  double get _pillRadius {
    switch (style) {
      case AppStyle.Spotify:
        return 18;
      case AppStyle.AppleMusic:
        return 12;
      case AppStyle.Original:
        return 22;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isApple = style == AppStyle.AppleMusic;
    final options = _options;
    final radius = _pillRadius;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _SortHeaderPill(
              key: ValueKey('mobile_sort_${options[i].method.name}'),
              label: options[i].label,
              selected: options[i].method == sortMethod,
              ascending: sortAscending,
              showDirection: options[i].method == sortMethod,
              isApple: isApple,
              radius: radius,
              primaryColor: colorScheme.primary,
              onTap: () => onSort(options[i].method),
            ),
          ],
        ],
      ),
    );
  }
}

class _SortHeaderPill extends StatelessWidget {
  final String label;
  final bool selected;
  final bool ascending;
  final bool showDirection;
  final bool isApple;
  final double radius;
  final Color primaryColor;
  final VoidCallback onTap;

  const _SortHeaderPill({
    super.key,
    required this.label,
    required this.selected,
    required this.ascending,
    required this.showDirection,
    required this.isApple,
    required this.radius,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bgColor = selected
        ? primaryColor.withValues(alpha: colors.isDark ? 0.2 : 0.14)
        : colors.surface;
    final borderColor = selected
        ? primaryColor.withValues(alpha: 0.7)
        : colors.borderSubtle;
    final textColor = selected ? primaryColor : colors.textSecondary;

    final directionIcon = isApple
        ? (ascending ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down)
        : (ascending
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (showDirection) ...[
                const SizedBox(width: 5),
                Icon(directionIcon, size: 15, color: textColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
