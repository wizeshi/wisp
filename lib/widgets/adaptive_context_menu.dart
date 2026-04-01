library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef ContextMenuActionCallback = FutureOr<void> Function(BuildContext context);
typedef ContextMenuHeaderBuilder = Widget Function(BuildContext context);

class ContextMenuAction {
  final String id;
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final bool enabled;
  final bool destructive;
  final List<ContextMenuAction> children;
  final ContextMenuActionCallback? onSelected;

  const ContextMenuAction({
    required this.id,
    required this.label,
    this.icon,
    this.iconColor,
    this.enabled = true,
    this.destructive = false,
    this.children = const [],
    this.onSelected,
  });

  bool get hasChildren => children.isNotEmpty;
}

Future<void> showAdaptiveContextMenu({
  required BuildContext context,
  required List<ContextMenuAction> actions,
  Offset? globalPosition,
  Rect? anchorRect,
  ContextMenuHeaderBuilder? mobileHeaderBuilder,
  String? barrierLabel,
}) async {
  if (actions.isEmpty) return;
  final desktop = _isDesktop;
  if (desktop) {
    final overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox;
    final anchor = anchorRect ?? Rect.fromLTWH(globalPosition?.dx ?? 0, globalPosition?.dy ?? 0, 1, 1);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel ?? 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _DesktopContextMenuDialog(
          anchorRect: anchor,
          overlaySize: overlay.size,
          actions: actions,
        );
      },
    );
    return;
  }

  await _showMobileContextMenu(
    context,
    actions: actions,
    headerBuilder: mobileHeaderBuilder,
  );
}

bool get _isDesktop => Platform.isLinux || Platform.isMacOS || Platform.isWindows;

Future<void> _showMobileContextMenu(
  BuildContext context, {
  required List<ContextMenuAction> actions,
  ContextMenuHeaderBuilder? headerBuilder,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: const Color(0xFF282828),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (headerBuilder != null) ...[
              const SizedBox(height: 12),
              headerBuilder(sheetContext),
              const SizedBox(height: 8),
              Divider(height: 1, color: Colors.grey[800]),
            ],
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final action in actions)
                    _MobileMenuTile(
                      action: action,
                      onSelected: () async {
                        if (!action.enabled) return;
                        if (action.hasChildren) {
                          Navigator.of(sheetContext).pop();
                          await _showMobileContextMenu(
                            context,
                            actions: action.children,
                          );
                          return;
                        }
                        Navigator.of(sheetContext).pop();
                        await action.onSelected?.call(context);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MobileMenuTile extends StatelessWidget {
  final ContextMenuAction action;
  final Future<void> Function() onSelected;

  const _MobileMenuTile({
    required this.action,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? Colors.redAccent : Colors.white;
    final resolvedIconColor = action.iconColor ?? color;
    return ListTile(
      enabled: action.enabled,
      leading: action.icon != null
          ? Icon(
              action.icon,
              color: action.enabled ? resolvedIconColor : Colors.grey[500],
            )
          : null,
      title: Text(
        action.label,
        style: TextStyle(color: action.enabled ? color : Colors.grey[500]),
      ),
      trailing: action.hasChildren
          ? const Icon(Icons.chevron_right, color: Colors.white70)
          : null,
      onTap: onSelected,
    );
  }
}

class _DesktopContextMenuDialog extends StatefulWidget {
  final Rect anchorRect;
  final Size overlaySize;
  final List<ContextMenuAction> actions;

  const _DesktopContextMenuDialog({
    required this.anchorRect,
    required this.overlaySize,
    required this.actions,
  });

  @override
  State<_DesktopContextMenuDialog> createState() => _DesktopContextMenuDialogState();
}

class _DesktopContextMenuDialogState extends State<_DesktopContextMenuDialog> {
  static const double _menuWidth = 260;
  static const double _itemHeight = 42;
  static const double _menuVerticalPadding = 8;
  static const double _screenMargin = 8;

  final List<_DesktopMenuLevelState> _levels = [];
  final Set<int> _hoveredLevels = <int>{};

  Timer? _closeSubmenuTimer;
  Offset _pointerPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    final rootPosition = _clampMenuPosition(
      Offset(widget.anchorRect.left, widget.anchorRect.bottom),
      itemCount: widget.actions.length,
    );
    _levels.add(
      _DesktopMenuLevelState(
        level: 0,
        actions: widget.actions,
        position: rootPosition,
        rect: _menuRect(rootPosition, widget.actions.length),
      ),
    );
  }

  @override
  void dispose() {
    _closeSubmenuTimer?.cancel();
    super.dispose();
  }

  Rect _menuRect(Offset position, int itemCount) {
    final height = _menuHeight(itemCount);
    return Rect.fromLTWH(position.dx, position.dy, _menuWidth, height);
  }

  double _menuHeight(int itemCount) {
    return itemCount * _itemHeight + (_menuVerticalPadding * 2);
  }

  Offset _clampMenuPosition(Offset proposed, {required int itemCount}) {
    final height = _menuHeight(itemCount);
    final maxLeft = math.max(_screenMargin, widget.overlaySize.width - _menuWidth - _screenMargin);
    final maxTop = math.max(_screenMargin, widget.overlaySize.height - height - _screenMargin);
    return Offset(
      proposed.dx.clamp(_screenMargin, maxLeft),
      proposed.dy.clamp(_screenMargin, maxTop),
    );
  }

  void _onActionHovered({
    required int level,
    required ContextMenuAction action,
    required Rect rowRect,
  }) {
    _closeSubmenuTimer?.cancel();

    if (!action.hasChildren) {
      if (_levels.length > level + 1) {
        setState(() {
          _levels.removeRange(level + 1, _levels.length);
        });
      }
      return;
    }

    final openRightX = rowRect.right + 2;
    final openLeftX = rowRect.left - _menuWidth - 2;
    final submenuItems = action.children;

    var target = Offset(openRightX, rowRect.top - _menuVerticalPadding);
    if (openRightX + _menuWidth > widget.overlaySize.width - _screenMargin) {
      target = Offset(openLeftX, target.dy);
    }
    target = _clampMenuPosition(target, itemCount: submenuItems.length);

    final submenu = _DesktopMenuLevelState(
      level: level + 1,
      actions: submenuItems,
      position: target,
      parentRowRect: rowRect,
      rect: _menuRect(target, submenuItems.length),
    );

    setState(() {
      if (_levels.length > level + 1) {
        _levels.removeRange(level + 1, _levels.length);
      }
      _levels.add(submenu);
    });
  }

  void _scheduleSubmenuClose({
    required int level,
    required Rect parentRowRect,
  }) {
    _closeSubmenuTimer?.cancel();
    _closeSubmenuTimer = Timer(const Duration(milliseconds: 220), () {
      final submenuLevel = level + 1;
      if (_hoveredLevels.contains(submenuLevel)) {
        return;
      }

      _DesktopMenuLevelState? submenu;
      for (final entry in _levels) {
        if (entry.level == submenuLevel) {
          submenu = entry;
          break;
        }
      }
      if (submenu == null) {
        return;
      }

      final shouldKeepOpen = _isPointerInGraceZone(
        pointer: _pointerPosition,
        parentRect: parentRowRect,
        submenuRect: submenu.rect,
      );
      if (shouldKeepOpen) {
        _scheduleSubmenuClose(level: level, parentRowRect: parentRowRect);
        return;
      }

      if (!mounted) return;
      setState(() {
        _levels.removeWhere((entry) => entry.level >= submenuLevel);
      });
    });
  }

  bool _isPointerInGraceZone({
    required Offset pointer,
    required Rect parentRect,
    required Rect submenuRect,
  }) {
    if (submenuRect.contains(pointer)) return true;

    final bridgeRect = Rect.fromLTRB(
      math.min(parentRect.right, submenuRect.left) - 10,
      math.min(parentRect.top, submenuRect.top) - 12,
      math.max(parentRect.right, submenuRect.left) + 10,
      math.max(parentRect.bottom, submenuRect.bottom) + 12,
    );

    if (bridgeRect.contains(pointer)) return true;

    final upperTriangle = _Triangle(
      parentRect.topRight,
      parentRect.bottomRight,
      submenuRect.topLeft,
    );
    final lowerTriangle = _Triangle(
      parentRect.topRight,
      parentRect.bottomRight,
      submenuRect.bottomLeft,
    );

    return upperTriangle.contains(pointer) || lowerTriangle.contains(pointer);
  }

  Future<void> _onActionSelected(ContextMenuAction action) async {
    if (!action.enabled || action.hasChildren) return;
    Navigator.of(context).pop();
    await action.onSelected?.call(context);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        _pointerPosition = event.position;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          for (final levelState in _levels)
            Positioned(
              left: levelState.position.dx,
              top: levelState.position.dy,
              width: _menuWidth,
              child: MouseRegion(
                onEnter: (_) {
                  _hoveredLevels.add(levelState.level);
                  _closeSubmenuTimer?.cancel();
                },
                onExit: (_) {
                  _hoveredLevels.remove(levelState.level);
                },
                child: Material(
                  color: const Color(0xFF282828),
                  borderRadius: BorderRadius.circular(8),
                  elevation: 14,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: _menuVerticalPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action in levelState.actions)
                          _DesktopActionTile(
                            action: action,
                            onHovered: (rowRect) {
                              _onActionHovered(
                                level: levelState.level,
                                action: action,
                                rowRect: rowRect,
                              );
                            },
                            onExit: (rowRect) {
                              if (!action.hasChildren) return;
                              _scheduleSubmenuClose(
                                level: levelState.level,
                                parentRowRect: rowRect,
                              );
                            },
                            onTap: () => _onActionSelected(action),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopActionTile extends StatelessWidget {
  final ContextMenuAction action;
  final ValueChanged<Rect> onHovered;
  final ValueChanged<Rect> onExit;
  final VoidCallback onTap;

  const _DesktopActionTile({
    required this.action,
    required this.onHovered,
    required this.onExit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? Colors.redAccent : Colors.white;
    final iconColor = action.enabled
        ? (action.iconColor ?? color.withValues(alpha: 0.9))
        : Colors.grey[500];

    return Builder(
      builder: (tileContext) {
        return MouseRegion(
          onEnter: (_) {
            final box = tileContext.findRenderObject() as RenderBox?;
            if (box == null) return;
            final rect = Rect.fromPoints(
              box.localToGlobal(Offset.zero),
              box.localToGlobal(box.size.bottomRight(Offset.zero)),
            );
            onHovered(rect);
          },
          onExit: (_) {
            final box = tileContext.findRenderObject() as RenderBox?;
            if (box == null) return;
            final rect = Rect.fromPoints(
              box.localToGlobal(Offset.zero),
              box.localToGlobal(box.size.bottomRight(Offset.zero)),
            );
            onExit(rect);
          },
          child: InkWell(
            onTap: action.enabled ? onTap : null,
            child: SizedBox(
              height: _DesktopContextMenuDialogState._itemHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    if (action.icon != null)
                      Icon(action.icon, color: iconColor, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        action.label,
                        style: TextStyle(
                          color: action.enabled ? color : Colors.grey[500],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (action.hasChildren)
                      Icon(
                        Icons.chevron_right,
                        color: action.enabled ? Colors.white70 : Colors.grey[600],
                        size: 18,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopMenuLevelState {
  final int level;
  final List<ContextMenuAction> actions;
  final Offset position;
  final Rect rect;
  final Rect? parentRowRect;

  _DesktopMenuLevelState({
    required this.level,
    required this.actions,
    required this.position,
    required this.rect,
    this.parentRowRect,
  });
}

class _Triangle {
  final Offset a;
  final Offset b;
  final Offset c;

  const _Triangle(this.a, this.b, this.c);

  bool contains(Offset point) {
    final denominator = ((b.dy - c.dy) * (a.dx - c.dx) + (c.dx - b.dx) * (a.dy - c.dy));
    if (denominator == 0) return false;
    final w1 = ((b.dy - c.dy) * (point.dx - c.dx) + (c.dx - b.dx) * (point.dy - c.dy)) / denominator;
    final w2 = ((c.dy - a.dy) * (point.dx - c.dx) + (a.dx - c.dx) * (point.dy - c.dy)) / denominator;
    final w3 = 1 - w1 - w2;
    return w1 >= 0 && w2 >= 0 && w3 >= 0;
  }
}