// Copyright © 2026 wizeshi

/// Shared button abstractions that differentiate styles based on [AppStyle].
///
/// When the style is [AppStyle.AppleMusic], buttons are rendered using
/// Cupertino equivalents ([CupertinoButton], [CupertinoButton.filled], etc.)
/// with iOS-style pressed opacity, styling, and cursor handling.
///
/// When the style is [AppStyle.Spotify] or [AppStyle.Original], buttons are
/// rendered using Material Design equivalents ([IconButton], [FilledButton], etc.).
library;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/core/theme/app_theme.dart';

/// Button visual variant for [GenericButton].
enum GenericButtonVariant {
  /// Standard / text button (no solid fill, text/icon only).
  text,

  /// Filled solid background button (primary color by default).
  filled,

  /// Filled tonal background button (secondary container color).
  tonal,

  /// Outlined border button with transparent background.
  outlined,
}

/// An icon-only button that adapts between [CupertinoButton] and [IconButton]
/// based on [AppStyle].
///
/// Simply pass `style: this.style` (or omit it to automatically use the
/// ambient [context.appStyle]), and it will build the corresponding button correctly.
class GenericIconButton extends StatelessWidget {
  /// The app style. When null, defaults to [context.appStyle].
  final AppStyle? style;

  /// The icon widget to display.
  final Widget icon;

  /// The callback that is called when the button is tapped.
  /// If null, the button is disabled.
  final VoidCallback? onPressed;

  /// Optional callback for long-press.
  final VoidCallback? onLongPress;

  /// The size of the icon.
  final double? iconSize;

  /// The color to use for the icon when enabled.
  final Color? color;

  /// The color to use for the icon when disabled.
  final Color? disabledColor;

  /// Padding around the icon.
  final EdgeInsetsGeometry? padding;

  /// Alignment of the icon within the button.
  final AlignmentGeometry? alignment;

  /// Box constraints for the button size.
  final BoxConstraints? constraints;

  /// Minimum size for the button.
  final Size? minimumSize;

  /// Tooltip message shown on hover or long press.
  final String? tooltip;

  /// Cursor to use when hovering over the button.
  final MouseCursor? mouseCursor;

  /// Pressed opacity for Cupertino mode. Defaults to 0.5 (matching AM player).
  final double pressedOpacity;

  /// Optional background color (for circular or container icon buttons).
  final Color? backgroundColor;

  /// Border radius of the button background.
  final BorderRadius? borderRadius;

  /// Focus node for keyboard interactions.
  final FocusNode? focusNode;

  /// Whether to autofocus this button.
  final bool autofocus;

  /// Material splash radius override.
  final double? splashRadius;

  /// Material [ButtonStyle] override.
  final ButtonStyle? materialStyle;

  /// Toggle button selection state.
  final bool? isSelected;

  /// Icon to display when [isSelected] is true.
  final Widget? selectedIcon;

  const GenericIconButton({
    super.key,
    this.style,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.iconSize,
    this.color,
    this.disabledColor,
    this.padding,
    this.alignment,
    this.constraints,
    this.minimumSize,
    this.tooltip,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.backgroundColor,
    this.borderRadius,
    this.focusNode,
    this.autofocus = false,
    this.splashRadius,
    this.materialStyle,
    this.isSelected,
    this.selectedIcon,
  });

  bool _isApple(BuildContext context) {
    if (style != null) {
      return WispStyleTokens.fromStyle(style!).isApple;
    }
    return context.tokens.isApple;
  }

  @override
  Widget build(BuildContext context) {
    final isApple = _isApple(context);
    final isEnabled = onPressed != null || onLongPress != null;

    if (isApple) {
      final effectiveColor = isEnabled
          ? (color ?? Colors.white)
          : (disabledColor ??
              (color != null
                  ? color!.withValues(alpha: 0.38)
                  : Colors.grey[600]!));

      final activeIcon =
          (isSelected == true && selectedIcon != null) ? selectedIcon! : icon;

      Widget iconWidget = IconTheme.merge(
        data: IconThemeData(
          size: iconSize,
          color: effectiveColor,
        ),
        child: activeIcon,
      );

      final effectiveCursor = mouseCursor ??
          (isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic);

      final effectiveMinSize = minimumSize ??
          (constraints != null
              ? Size(constraints!.minWidth, constraints!.minHeight)
              : (padding == EdgeInsets.zero && iconSize != null
                  ? Size.square(iconSize!)
                  : Size.zero));

      Widget button = CupertinoButton(
        mouseCursor: effectiveCursor,
        padding: padding ?? EdgeInsets.zero,
        minimumSize: effectiveMinSize,
        pressedOpacity: pressedOpacity,
        color: backgroundColor,
        borderRadius: borderRadius ??
            (backgroundColor != null ? BorderRadius.circular(100) : null),
        alignment: alignment ?? Alignment.center,
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: onPressed,
        onLongPress: onLongPress,
        child: iconWidget,
      );

      if (constraints != null) {
        button = ConstrainedBox(
          constraints: constraints!,
          child: button,
        );
      }

      if (tooltip != null && tooltip!.isNotEmpty) {
        button = Tooltip(
          message: tooltip!,
          child: button,
        );
      }

      return button;
    }

    // Material mode (Spotify / Original)
    ButtonStyle? effectiveMaterialStyle = materialStyle;
    if (backgroundColor != null || borderRadius != null) {
      effectiveMaterialStyle = (effectiveMaterialStyle ?? const ButtonStyle())
          .copyWith(
        backgroundColor: backgroundColor != null
            ? WidgetStatePropertyAll<Color>(backgroundColor!)
            : null,
        shape: borderRadius != null
            ? WidgetStatePropertyAll<OutlinedBorder>(
                RoundedRectangleBorder(borderRadius: borderRadius!),
              )
            : null,
      );
    }

    return IconButton(
      icon: icon,
      selectedIcon: selectedIcon,
      isSelected: isSelected,
      onPressed: onPressed,
      onLongPress: onLongPress,
      iconSize: iconSize,
      color: color,
      disabledColor: disabledColor,
      padding: padding,
      alignment: alignment,
      splashRadius: splashRadius,
      focusNode: focusNode,
      autofocus: autofocus,
      tooltip: tooltip,
      constraints: constraints,
      style: effectiveMaterialStyle,
      mouseCursor: mouseCursor,
    );
  }
}

/// A filled button that adapts between [CupertinoButton.filled] / [CupertinoButton]
/// and [FilledButton] based on [AppStyle].
///
/// Pass `style: this.style` (or omit it to automatically use ambient [context.appStyle]).
class GenericFilledButton extends StatelessWidget {
  /// The app style. When null, defaults to [context.appStyle].
  final AppStyle? style;

  /// The callback that is called when the button is tapped.
  final VoidCallback? onPressed;

  /// Optional callback for long-press.
  final VoidCallback? onLongPress;

  /// The widget below this widget in the tree.
  final Widget? child;

  /// Optional icon when constructing with [GenericFilledButton.icon].
  final Widget? icon;

  /// Optional label when constructing with [GenericFilledButton.icon].
  final Widget? label;

  /// Background color. Defaults to theme's primary color.
  final Color? backgroundColor;

  /// Foreground/text color. Defaults to white or onPrimary.
  final Color? foregroundColor;

  /// Background color when disabled.
  final Color? disabledBackgroundColor;

  /// Foreground color when disabled.
  final Color? disabledForegroundColor;

  /// Padding around the button's content.
  final EdgeInsetsGeometry? padding;

  /// Border radius. When null, uses [WispStyleTokens.buttonRadius].
  final BorderRadius? borderRadius;

  /// Minimum size of the button.
  final Size? minimumSize;

  /// Cursor to use on hover.
  final MouseCursor? mouseCursor;

  /// Pressed opacity for Cupertino mode. Defaults to 0.5.
  final double pressedOpacity;

  /// Focus node for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether to autofocus this button.
  final bool autofocus;

  /// Material [ButtonStyle] override.
  final ButtonStyle? materialStyle;

  /// Optional tooltip.
  final String? tooltip;

  const GenericFilledButton({
    super.key,
    this.style,
    required this.onPressed,
    this.onLongPress,
    required Widget this.child,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.focusNode,
    this.autofocus = false,
    this.materialStyle,
    this.tooltip,
  })  : icon = null,
        label = null;

  const GenericFilledButton.icon({
    super.key,
    this.style,
    required this.onPressed,
    this.onLongPress,
    required Widget this.icon,
    required Widget this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.focusNode,
    this.autofocus = false,
    this.materialStyle,
    this.tooltip,
  }) : child = null;

  bool _isApple(BuildContext context) {
    if (style != null) {
      return WispStyleTokens.fromStyle(style!).isApple;
    }
    return context.tokens.isApple;
  }

  @override
  Widget build(BuildContext context) {
    final isApple = _isApple(context);
    final isEnabled = onPressed != null || onLongPress != null;
    final theme = Theme.of(context);
    final tokens = style != null ? WispStyleTokens.fromStyle(style!) : context.tokens;

    final effectiveBgColor = backgroundColor ?? theme.colorScheme.primary;
    final effectiveFgColor = foregroundColor ?? theme.colorScheme.onPrimary;
    final effectiveRadius = borderRadius ?? tokens.buttonRadius;

    final Widget buttonContent;
    if (icon != null && label != null) {
      buttonContent = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon!,
          const SizedBox(width: 8),
          label!,
        ],
      );
    } else {
      buttonContent = child ?? const SizedBox.shrink();
    }

    if (isApple) {
      final effectiveCursor = mouseCursor ??
          (isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic);

      final effectiveDisabledBg = disabledBackgroundColor ??
          CupertinoColors.quaternarySystemFill;
      final effectiveDisabledFg = disabledForegroundColor ??
          Colors.white38;

      Widget button = CupertinoButton(
        color: effectiveBgColor,
        disabledColor: effectiveDisabledBg,
        borderRadius: effectiveRadius,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: minimumSize ?? const Size(44, 36),
        pressedOpacity: pressedOpacity,
        mouseCursor: effectiveCursor,
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: onPressed,
        onLongPress: onLongPress,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: isEnabled ? effectiveFgColor : effectiveDisabledFg,
            fontWeight: FontWeight.w600,
          ),
          child: IconTheme.merge(
            data: IconThemeData(
              color: isEnabled ? effectiveFgColor : effectiveDisabledFg,
              size: 18,
            ),
            child: buttonContent,
          ),
        ),
      );

      if (tooltip != null && tooltip!.isNotEmpty) {
        button = Tooltip(
          message: tooltip!,
          child: button,
        );
      }

      return button;
    }

    // Material mode
    final baseStyle = FilledButton.styleFrom(
      backgroundColor: effectiveBgColor,
      foregroundColor: effectiveFgColor,
      disabledBackgroundColor: disabledBackgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      padding: padding,
      shape: RoundedRectangleBorder(borderRadius: effectiveRadius),
      minimumSize: minimumSize,
      enabledMouseCursor: mouseCursor ?? SystemMouseCursors.click,
      disabledMouseCursor: mouseCursor ?? SystemMouseCursors.basic,
    );

    final resolvedStyle = materialStyle != null
        ? baseStyle.merge(materialStyle)
        : baseStyle;

    Widget button;
    if (icon != null && label != null) {
      button = FilledButton.icon(
        onPressed: onPressed,
        onLongPress: onLongPress,
        icon: icon!,
        label: label!,
        style: resolvedStyle,
        focusNode: focusNode,
        autofocus: autofocus,
      );
    } else {
      button = FilledButton(
        onPressed: onPressed,
        onLongPress: onLongPress,
        style: resolvedStyle,
        focusNode: focusNode,
        autofocus: autofocus,
        child: buttonContent,
      );
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// A flexible adaptive button supporting multiple visual variants ([GenericButtonVariant])
/// and styles ([AppStyle]).
///
/// Provides factory/named constructors for [GenericButton.filled],
/// [GenericButton.tonal], [GenericButton.outlined], [GenericButton.text],
/// and [GenericButton.icon].
class GenericButton extends StatelessWidget {
  /// The app style. When null, defaults to [context.appStyle].
  final AppStyle? style;

  /// The button variant.
  final GenericButtonVariant variant;

  /// The child widget.
  final Widget? child;

  /// Optional icon.
  final Widget? icon;

  /// Optional label when used with [icon].
  final Widget? label;

  /// Tap callback.
  final VoidCallback? onPressed;

  /// Long-press callback.
  final VoidCallback? onLongPress;

  /// Background color.
  final Color? backgroundColor;

  /// Foreground/content color.
  final Color? foregroundColor;

  /// Disabled background color.
  final Color? disabledBackgroundColor;

  /// Disabled foreground color.
  final Color? disabledForegroundColor;

  /// Padding.
  final EdgeInsetsGeometry? padding;

  /// Border radius.
  final BorderRadius? borderRadius;

  /// Minimum button size.
  final Size? minimumSize;

  /// Hover cursor.
  final MouseCursor? mouseCursor;

  /// Cupertino pressed opacity. Defaults to 0.5.
  final double pressedOpacity;

  /// Material ButtonStyle override.
  final ButtonStyle? materialStyle;

  /// Optional tooltip.
  final String? tooltip;

  /// Focus node.
  final FocusNode? focusNode;

  /// Autofocus.
  final bool autofocus;

  const GenericButton({
    super.key,
    this.style,
    this.variant = GenericButtonVariant.text,
    required Widget this.child,
    required this.onPressed,
    this.onLongPress,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.materialStyle,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : icon = null,
        label = null;

  const GenericButton.text({
    super.key,
    this.style,
    required Widget this.child,
    required this.onPressed,
    this.onLongPress,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.materialStyle,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : variant = GenericButtonVariant.text,
        icon = null,
        label = null;

  const GenericButton.filled({
    super.key,
    this.style,
    required Widget this.child,
    required this.onPressed,
    this.onLongPress,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.materialStyle,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : variant = GenericButtonVariant.filled,
        icon = null,
        label = null;

  const GenericButton.tonal({
    super.key,
    this.style,
    required Widget this.child,
    required this.onPressed,
    this.onLongPress,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.materialStyle,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : variant = GenericButtonVariant.tonal,
        icon = null,
        label = null;

  const GenericButton.outlined({
    super.key,
    this.style,
    required Widget this.child,
    required this.onPressed,
    this.onLongPress,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.materialStyle,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : variant = GenericButtonVariant.outlined,
        icon = null,
        label = null;

  const GenericButton.icon({
    super.key,
    this.style,
    this.variant = GenericButtonVariant.filled,
    required Widget this.icon,
    required Widget this.label,
    required this.onPressed,
    this.onLongPress,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
    this.borderRadius,
    this.minimumSize,
    this.mouseCursor,
    this.pressedOpacity = 0.5,
    this.materialStyle,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  }) : child = null;

  /// Convenient factory to construct a [GenericIconButton].
  static Widget iconOnly({
    Key? key,
    AppStyle? style,
    required Widget icon,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    double? iconSize,
    Color? color,
    Color? disabledColor,
    EdgeInsetsGeometry? padding,
    AlignmentGeometry? alignment,
    BoxConstraints? constraints,
    Size? minimumSize,
    String? tooltip,
    MouseCursor? mouseCursor,
    double pressedOpacity = 0.5,
    Color? backgroundColor,
    BorderRadius? borderRadius,
    FocusNode? focusNode,
    bool autofocus = false,
    double? splashRadius,
    ButtonStyle? materialStyle,
    bool? isSelected,
    Widget? selectedIcon,
  }) {
    return GenericIconButton(
      key: key,
      style: style,
      icon: icon,
      onPressed: onPressed,
      onLongPress: onLongPress,
      iconSize: iconSize,
      color: color,
      disabledColor: disabledColor,
      padding: padding,
      alignment: alignment,
      constraints: constraints,
      minimumSize: minimumSize,
      tooltip: tooltip,
      mouseCursor: mouseCursor,
      pressedOpacity: pressedOpacity,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
      focusNode: focusNode,
      autofocus: autofocus,
      splashRadius: splashRadius,
      materialStyle: materialStyle,
      isSelected: isSelected,
      selectedIcon: selectedIcon,
    );
  }

  bool _isApple(BuildContext context) {
    if (style != null) {
      return WispStyleTokens.fromStyle(style!).isApple;
    }
    return context.tokens.isApple;
  }

  @override
  Widget build(BuildContext context) {
    // If it's a filled button, delegate directly to GenericFilledButton for consistency
    if (variant == GenericButtonVariant.filled) {
      if (icon != null && label != null) {
        return GenericFilledButton.icon(
          style: style,
          onPressed: onPressed,
          onLongPress: onLongPress,
          icon: icon!,
          label: label!,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          disabledForegroundColor: disabledForegroundColor,
          padding: padding,
          borderRadius: borderRadius,
          minimumSize: minimumSize,
          mouseCursor: mouseCursor,
          pressedOpacity: pressedOpacity,
          focusNode: focusNode,
          autofocus: autofocus,
          materialStyle: materialStyle,
          tooltip: tooltip,
        );
      }
      return GenericFilledButton(
        style: style,
        onPressed: onPressed,
        onLongPress: onLongPress,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: disabledBackgroundColor,
        disabledForegroundColor: disabledForegroundColor,
        padding: padding,
        borderRadius: borderRadius,
        minimumSize: minimumSize,
        mouseCursor: mouseCursor,
        pressedOpacity: pressedOpacity,
        focusNode: focusNode,
        autofocus: autofocus,
        materialStyle: materialStyle,
        tooltip: tooltip,
        child: child!,
      );
    }

    final isApple = _isApple(context);
    final isEnabled = onPressed != null || onLongPress != null;
    final theme = Theme.of(context);
    final tokens = style != null ? WispStyleTokens.fromStyle(style!) : context.tokens;
    final effectiveRadius = borderRadius ?? tokens.buttonRadius;

    final Widget buttonContent;
    if (icon != null && label != null) {
      buttonContent = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon!,
          const SizedBox(width: 8),
          label!,
        ],
      );
    } else {
      buttonContent = child ?? const SizedBox.shrink();
    }

    if (isApple) {
      final effectiveCursor = mouseCursor ??
          (isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic);

      Color? bg;
      Color fg = foregroundColor ?? theme.colorScheme.primary;

      switch (variant) {
        case GenericButtonVariant.tonal:
          bg = backgroundColor ??
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
          fg = foregroundColor ?? theme.colorScheme.onSurface;
          break;
        case GenericButtonVariant.outlined:
          bg = backgroundColor;
          fg = foregroundColor ?? theme.colorScheme.primary;
          break;
        case GenericButtonVariant.text:
        case GenericButtonVariant.filled:
          bg = backgroundColor;
          fg = foregroundColor ?? theme.colorScheme.primary;
          break;
      }

      Widget button = CupertinoButton(
        color: bg,
        borderRadius: effectiveRadius,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: minimumSize ?? const Size(44, 36),
        pressedOpacity: pressedOpacity,
        mouseCursor: effectiveCursor,
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: onPressed,
        onLongPress: onLongPress,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: isEnabled ? fg : Colors.white38,
            fontWeight: FontWeight.w600,
          ),
          child: IconTheme.merge(
            data: IconThemeData(
              color: isEnabled ? fg : Colors.white38,
              size: 18,
            ),
            child: buttonContent,
          ),
        ),
      );

      if (variant == GenericButtonVariant.outlined) {
        button = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: effectiveRadius,
            border: Border.all(
              color: isEnabled
                  ? (foregroundColor ?? theme.colorScheme.outline)
                  : Colors.white24,
            ),
          ),
          child: button,
        );
      }

      if (tooltip != null && tooltip!.isNotEmpty) {
        button = Tooltip(
          message: tooltip!,
          child: button,
        );
      }

      return button;
    }

    // Material mode
    Widget button;
    switch (variant) {
      case GenericButtonVariant.tonal:
        final tonalStyle = FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          disabledForegroundColor: disabledForegroundColor,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: effectiveRadius),
          minimumSize: minimumSize,
          enabledMouseCursor: mouseCursor ?? SystemMouseCursors.click,
          disabledMouseCursor: mouseCursor ?? SystemMouseCursors.basic,
        );
        final resolvedStyle = materialStyle != null
            ? tonalStyle.merge(materialStyle)
            : tonalStyle;

        if (icon != null && label != null) {
          button = FilledButton.tonalIcon(
            onPressed: onPressed,
            onLongPress: onLongPress,
            icon: icon!,
            label: label!,
            style: resolvedStyle,
            focusNode: focusNode,
            autofocus: autofocus,
          );
        } else {
          button = FilledButton.tonal(
            onPressed: onPressed,
            onLongPress: onLongPress,
            style: resolvedStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            child: buttonContent,
          );
        }
        break;

      case GenericButtonVariant.outlined:
        final outlinedStyle = OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          disabledForegroundColor: disabledForegroundColor,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: effectiveRadius),
          minimumSize: minimumSize,
          enabledMouseCursor: mouseCursor ?? SystemMouseCursors.click,
          disabledMouseCursor: mouseCursor ?? SystemMouseCursors.basic,
        );
        final resolvedStyle = materialStyle != null
            ? outlinedStyle.merge(materialStyle)
            : outlinedStyle;

        if (icon != null && label != null) {
          button = OutlinedButton.icon(
            onPressed: onPressed,
            onLongPress: onLongPress,
            icon: icon!,
            label: label!,
            style: resolvedStyle,
            focusNode: focusNode,
            autofocus: autofocus,
          );
        } else {
          button = OutlinedButton(
            onPressed: onPressed,
            onLongPress: onLongPress,
            style: resolvedStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            child: buttonContent,
          );
        }
        break;

      case GenericButtonVariant.text:
      case GenericButtonVariant.filled:
        final textStyle = TextButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          disabledForegroundColor: disabledForegroundColor,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: effectiveRadius),
          minimumSize: minimumSize,
          enabledMouseCursor: mouseCursor ?? SystemMouseCursors.click,
          disabledMouseCursor: mouseCursor ?? SystemMouseCursors.basic,
        );
        final resolvedStyle = materialStyle != null
            ? textStyle.merge(materialStyle)
            : textStyle;

        if (icon != null && label != null) {
          button = TextButton.icon(
            onPressed: onPressed,
            onLongPress: onLongPress,
            icon: icon!,
            label: label!,
            style: resolvedStyle,
            focusNode: focusNode,
            autofocus: autofocus,
          );
        } else {
          button = TextButton(
            onPressed: onPressed,
            onLongPress: onLongPress,
            style: resolvedStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            child: buttonContent,
          );
        }
        break;
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}
