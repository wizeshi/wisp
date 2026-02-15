import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import '../services/navigation_history.dart';
import '../services/desktop_notification_center.dart';

class WispTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onSettingsTap;
  final VoidCallback? onHomeTap;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchSubmitted;
  final VoidCallback? onSearchCleared;

  const WispTitleBar({
    super.key,
    this.onSettingsTap,
    this.onHomeTap,
    this.searchController,
    this.searchFocusNode,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSearchCleared,
  });

  bool _isDesktop() {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  Size get preferredSize => Size.fromHeight(_isDesktop() ? 48 : 0);

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop()) {
      return SizedBox.shrink();
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Color(0xFF000000),
        border: Border(bottom: BorderSide(color: Colors.grey[900]!, width: 1)),
      ),
      child: Row(
        children: [
          // Back/Forward/Home buttons
          SizedBox(width: 16),
          _buildNavButton(Icons.chevron_left, () {
            if (NavigationHistory.instance.canGoBack) {
              NavigationHistory.instance.goBack();
            }
          }),
          SizedBox(width: 8),
          _buildNavButton(Icons.chevron_right, () {
            if (NavigationHistory.instance.canGoForward) {
              NavigationHistory.instance.goForward();
            }
          }),
          SizedBox(width: 8),
          _buildNavButton(Icons.home, () {
            if (onHomeTap != null) {
              onHomeTap!();
            }
          }),
          SizedBox(width: 16),

          // Draggable area (left side)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => windowManager.startDragging(),
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                bool isMaximized = await windowManager.isMaximized();
                if (isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: Container(),
            ),
          ),

          // Search bar (not draggable)
          _buildSearchField(),

          // Draggable area (right side)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => windowManager.startDragging(),
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                bool isMaximized = await windowManager.isMaximized();
                if (isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: Container(),
            ),
          ),

          // Notifications button
          _buildNotificationButton(context),

          const SizedBox(width: 8),

          // Settings button
          _buildActionButton(Icons.settings_outlined, () {
            if (onSettingsTap != null) {
              onSettingsTap!();
            }
          }),

          const SizedBox(width: 8),

          // Window control buttons
          _buildWindowButton(Icons.minimize, () async {
            await windowManager.minimize();
          }),
          _buildWindowButton(Icons.crop_square, () async {
            bool isMaximized = await windowManager.isMaximized();
            if (isMaximized) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          }),
          _buildWindowButton(Icons.close, () async {
            await windowManager.close();
          }, isClose: true),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Color(0xFF0A0A0A),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, color: Colors.grey[400], size: 20),
        ),
      ),
    );
  }

  Widget _buildNotificationButton(BuildContext context) {
    return Consumer<DesktopNotificationCenter>(
      builder: (context, center, _) {
        return Builder(
          builder: (buttonContext) {
            return Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () => _showNotificationMenu(buttonContext),
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                      if (center.items.isNotEmpty)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${center.items.length}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showNotificationMenu(BuildContext context) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final menuTopLeft = topLeft + Offset(0, box.size.height + 8);
    final menuBottomRight =
        menuTopLeft + Offset(box.size.width, box.size.height);

    await showMenu<void>(
      context: context,
      color: Colors.transparent,
      elevation: 0,
      position: RelativeRect.fromRect(
        Rect.fromPoints(menuTopLeft, menuBottomRight),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: const _NotificationDropdown(),
        ),
      ],
    );
  }

  Widget _buildWindowButton(
    IconData icon,
    VoidCallback onPressed, {
    bool isClose = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        hoverColor: isClose ? Colors.red.withOpacity(0.8) : Colors.grey[800],
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.grey[400], size: 18),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final controller = searchController;

    if (controller == null) {
      return Container(
        height: 32,
        width: 400,
        decoration: BoxDecoration(
          color: Color(0xFF242424),
          borderRadius: BorderRadius.circular(500),
        ),
        child: TextField(
          focusNode: searchFocusNode,
          style: TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search songs, albums, artists...',
            hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
            prefixIcon: Icon(Icons.search, color: Colors.grey[600], size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            isDense: true,
          ),
        ),
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Container(
          height: 32,
          width: 400,
          decoration: BoxDecoration(
            color: Color(0xFF242424),
            borderRadius: BorderRadius.circular(500),
          ),
          child: TextField(
            controller: controller,
            focusNode: searchFocusNode,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search songs, albums, artists...',
              hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
              prefixIcon: Icon(Icons.search, color: Colors.grey[600], size: 20),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.grey[500],
                        size: 18,
                      ),
                      onPressed: () {
                        controller.clear();
                        if (onSearchCleared != null) {
                          onSearchCleared!();
                        }
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
            onChanged: onSearchChanged,
            onSubmitted: (_) {
              if (onSearchSubmitted != null) {
                onSearchSubmitted!();
              }
            },
          ),
        );
      },
    );
  }
}

class _NotificationDropdown extends StatelessWidget {
  const _NotificationDropdown();

  @override
  Widget build(BuildContext context) {
    return Consumer<DesktopNotificationCenter>(
      builder: (context, center, _) {
        final textTheme = Theme.of(context).textTheme;
        final items = center.items;

        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Notifications',
                        style: (textTheme.titleSmall ?? const TextStyle())
                            .copyWith(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed: center.clearAll,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[400],
                        textStyle: (textTheme.labelSmall ?? const TextStyle())
                            .copyWith(fontSize: 11),
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No notifications',
                          style: (textTheme.bodySmall ?? const TextStyle())
                              .copyWith(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final hasProgress =
                              item.maxProgress > 1 && !item.isComplete;
                          final progress = hasProgress
                              ? (item.progress / item.maxProgress).clamp(
                                  0.0,
                                  1.0,
                                )
                              : 1.0;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style:
                                            (textTheme.labelMedium ??
                                                    const TextStyle())
                                                .copyWith(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () => center.dismiss(item.id),
                                    ),
                                  ],
                                ),
                                Text(
                                  item.body,
                                  style:
                                      (textTheme.bodySmall ?? const TextStyle())
                                          .copyWith(
                                            color: Colors.grey[400],
                                            fontSize: 11,
                                          ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (hasProgress) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.grey[850],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                                if (item.isComplete) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Completed',
                                    style:
                                        (textTheme.labelSmall ??
                                                const TextStyle())
                                            .copyWith(
                                              color: Colors.grey[500],
                                              fontSize: 10,
                                            ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
