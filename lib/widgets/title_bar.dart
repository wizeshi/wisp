import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:wisp/services/app_navigation.dart';
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
  final List<String> availableSources;
  final String selectedSource;
  final ValueChanged<String>? onSourceChanged;

  const WispTitleBar({
    super.key,
    this.onSettingsTap,
    this.onHomeTap,
    this.searchController,
    this.searchFocusNode,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSearchCleared,
    this.availableSources = const <String>[],
    this.selectedSource = 'Spotify',
    this.onSourceChanged,
  });

  IconData _sourceIcon(String source) {
    return source == 'YouTube' ? Icons.ondemand_video : Icons.music_note;
  }

  bool _isDesktop() {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  Size get preferredSize => Size.fromHeight(_isDesktop() ? 32 : 0);

  Widget buildNavButtons(BuildContext context, bool canGoBack, bool canGoForward, Route<dynamic>? route) {
    return Row(
      children: [
        Platform.isMacOS ? SizedBox(width: 8) : SizedBox(width: 16),
        // Build the home button on the left on Mac.
        if (Platform.isMacOS) Row(
          children: [
            _buildNavButton(route?.settings.name == "/home" ? Icons.home : Icons.home_outlined, () {
              if (onHomeTap != null) {
                onHomeTap!();
              }
            }),

            SizedBox(width: 8),
          ]
        ),
        _buildNavButton(
          Icons.chevron_left,
          canGoBack ? () => NavigationHistory.instance.goBack() : null,
          enabled: canGoBack,
        ),
        SizedBox(width: 8),
        _buildNavButton(
          Icons.chevron_right,
          canGoForward ? () => NavigationHistory.instance.goForward() : null,
          enabled: canGoForward,
        ),
        // Build the home button on the right on non-Mac.
        if (!Platform.isMacOS) Row(
          children: [
            SizedBox(width: 8),

            _buildNavButton(route?.settings.name == "/home" ? Icons.home : Icons.home_outlined, () {
              if (onHomeTap != null) {
                onHomeTap!();
              }
            }),

            SizedBox(width: 16),
          ]
        ),
      ]
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop()) {
      return SizedBox.shrink();
    }

    return ValueListenableBuilder<Route<dynamic>?> (
      valueListenable: NavigationHistory.instance.currentRoute,
      builder: (context, route, child) {
        final canGoBack = NavigationHistory.instance.canGoBack;
        final canGoForward = NavigationHistory.instance.canGoForward;
        final isMac = Platform.isMacOS;

        return Container(
          height: 32,
          decoration: BoxDecoration(
            color: Color(0xFF000000),
            border: Border(bottom: BorderSide(color: Colors.grey[900]!, width: 1)),
          ),
          child: Stack(
            children: [
              // Full-bar draggable background. Painted first (bottom of the
              // stack) so any real control drawn on top of it intercepts
              // taps before they reach this layer.
              Positioned.fill(child: _buildDragArea()),

              // Leading edge. Left empty on macOS — that space belongs to
              // the native traffic lights, which this widget can't
              // reposition, so nothing should be drawn under them.
              if (!isMac)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: buildNavButtons(context, canGoBack, canGoForward, route),
                ),

              // Search field: centered on the *whole* bar width, not just
              // the space between the leading/trailing content, so it stays
              // put even when those two sides are different widths.
              Center(child: _buildSearchField()),

              // Trailing edge.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Notifications button
                    _buildNotificationButton(context),

                    const SizedBox(width: 8),

                    _buildDebugButton(context),

                    const SizedBox(width: 8),

                    // Settings button
                    _buildActionButton(Icons.settings_outlined, () {
                      if (onSettingsTap != null) {
                        onSettingsTap!();
                      }
                    }),

                    // Nav buttons move here on macOS since the left side is
                    // reserved for the traffic lights.
                    if (isMac) ...[
                      buildNavButtons(context, canGoBack, canGoForward, route),
                    ],
                    // The traffic lights already provide minimize/maximize/
                    // close on macOS, so the custom window buttons only
                    // make sense on platforms without their own window
                    // chrome.
                    if (!isMac) ...[
                      const SizedBox(width: 8),
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
                    ] else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragArea() {
    return GestureDetector(
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
    );
  }

  Widget _buildDebugButton(BuildContext context) {
    return _buildActionButton(
      Icons.bug_report_outlined, 
      () { AppNavigation.instance.openDebug(context); }
    );
  }

  Widget _buildNavButton(
    IconData icon,
    VoidCallback? onPressed, {
    bool enabled = true,
  }) {
    final isEnabled = enabled && onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: isEnabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isEnabled ? Color(0xFF0A0A0A) : Color(0xFF0A0A0A),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isEnabled ? Colors.white : Colors.grey[600],
            size: 16,
          ),
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
          width: 24,
          height: 24,
          child: Icon(icon, color: Colors.grey[400], size: 16),
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
                  width: 24,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        color: Colors.grey[400],
                        size: 16,
                      ),
                      if (center.items.isNotEmpty)
                        Positioned(
                          right: 1,
                          top: 1,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 13,
                              minHeight: 13,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              center.items.length > 99
                                  ? '99+'
                                  : '${center.items.length}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                height: 1,
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
    // Show the notification dropdown menu centered below the notification button
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero);

    showMenu(
      color: Colors.transparent,
      elevation: 0,
      context: context,
      // Center the menu below the button
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + button.size.height,
        buttonPosition.dx + button.size.width,
        buttonPosition.dy,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: _NotificationDropdown(),
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
        hoverColor: isClose ? Colors.red.withValues(alpha: 0.8) : Colors.grey[800],
        child: SizedBox(
          width: 40,
          height: 32,
          child: Icon(icon, color: Colors.grey[400], size: 16),
        ),
      ),
    );
  }

  // Fixed height for the search pill. Comfortably inside the 32px bar with
  // a couple px of breathing room top and bottom.
  static const double _searchFieldHeight = 22;

  // Manual correction for the search field's text sitting low. strutStyle,
  // a fixed-height SizedBox, and textHeightBehavior were all tried and none
  // fully fixed it — something about this font stack isn't matching the
  // usual metrics assumptions. This is a blunt, guaranteed-to-work pixel
  // shift instead. Negative moves the text up. Tune by eye: try -1 or -3 if
  // -2 isn't quite right.
  static const double _searchTextVerticalNudge = -4;

  Widget _buildSearchField() {
    final controller = searchController;

    if (controller == null) {
      return _buildSearchFieldFor(null);
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => _buildSearchFieldFor(value),
    );
  }

  Widget _buildSearchFieldFor(TextEditingValue? value) {
    final controller = searchController;
    final showClear = controller != null && (value?.text.isNotEmpty ?? false);
    final showSourcePicker = availableSources.isNotEmpty;

    return Container(
      height: _searchFieldHeight,
      width: 400,
      decoration: BoxDecoration(
        color: Color(0xFF242424),
        borderRadius: BorderRadius.circular(500),
      ),
      // TextField's default prefixIcon/suffixIcon constraints reserve a
      // 48px min tap target, and default contentPadding adds another ~16px
      // of vertical space — either alone is taller than this whole bar.
      // The search icon is laid out as a plain Row child instead of via
      // InputDecoration's prefixIcon: prefixIcon has its own internal
      // vertical-centering math (tied to the decorator's line-height
      // calculations) that doesn't line up with a small isCollapsed field,
      // and its constraints control padding, not the icon-to-text gap. A
      // Row's default cross-axis centering handles alignment reliably, and
      // the SizedBox below gives an exact, predictable gap.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 10),
          Icon(Icons.search, color: Colors.grey[600], size: 16),
          const SizedBox(width: 6),
          Expanded(
            // Rather than forcing a hard pixel height (which overflowed
            // past its box and read as "text sinking toward the bottom"),
            // textHeightBehavior strips the font's built-in leading, which
            // is normally distributed unevenly — more space reserved below
            // the glyphs than above. That asymmetric leading, not box
            // sizing, was pushing the text down. TextField doesn't expose
            // textHeightBehavior directly (only Text/EditableText do), so
            // it's applied via DefaultTextHeightBehavior instead, which
            // explicitly documents that it also reaches descendant
            // EditableTexts — i.e. the one TextField builds internally.
            child: DefaultTextHeightBehavior(
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              child: Transform.translate(
                offset: const Offset(0, _searchTextVerticalNudge),
                child: TextField(
                  controller: controller,
                  focusNode: searchFocusNode,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Search songs, albums, artists...',
                    hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12, height: 1.2),
                    suffixIcon: (showClear || showSourcePicker)
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showClear) _buildSearchClearButton(controller!),
                              if (showSourcePicker) _buildSourcePicker(),
                              const SizedBox(width: 6),
                            ],
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: onSearchChanged,
                  onSubmitted: (_) {
                    if (onSearchSubmitted != null) {
                      onSearchSubmitted!();
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchClearButton(TextEditingController controller) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        controller.clear();
        if (onSearchCleared != null) {
          onSearchCleared!();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.close, color: Colors.grey[500], size: 15),
      ),
    );
  }

  Widget _buildSourcePicker() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: availableSources.contains(selectedSource)
            ? selectedSource
            : availableSources.first,
        dropdownColor: const Color(0xFF181818),
        iconEnabledColor: Colors.grey[400],
        iconSize: 16,
        isDense: true,
        selectedItemBuilder: (_) => availableSources
            .map(
              (source) => Icon(
                _sourceIcon(source),
                size: 15,
                color: Colors.white,
              ),
            )
            .toList(),
        items: availableSources
            .map(
              (source) => DropdownMenuItem<String>(
                value: source,
                child: Icon(
                  _sourceIcon(source),
                  size: 15,
                  color: Colors.white,
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null || onSourceChanged == null) return;
          onSourceChanged!(value);
        },
      ),
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
                color: Colors.black.withValues(alpha: 0.35),
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
                  vertical: 6,
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
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
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
                                      const SizedBox(height: 2),
                                      Text(
                                        item.body,
                                        style:
                                            (textTheme.bodySmall ??
                                                    const TextStyle())
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
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
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
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => center.dismiss(item.id),
                                  ),
                                ),
                              ]
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