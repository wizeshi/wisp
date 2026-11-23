import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

class GenericSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeThumbColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final AppStyle? style;

  const GenericSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeThumbColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final AppStyle? style =
        this.style ??
        context.select<PreferencesProvider, AppStyle?>(
          (provider) => provider.style,
        );

    final colors = context.colors;
    final defaultActive = colors.isDark
        ? Colors.greenAccent
        : const Color(0xFF1DB954);

    switch (style) {
      case AppStyle.Original:
        return M3ESwitch(
          value: value,
          onChanged: onChanged,
          selectedIcon: Icon(
            Icons.check,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      case AppStyle.Spotify:
        return Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: activeThumbColor ?? defaultActive,
          inactiveThumbColor: inactiveThumbColor ?? colors.textMuted,
          inactiveTrackColor: inactiveTrackColor ?? colors.trackInactive,
        );
      case AppStyle.AppleMusic:
        return LiquidGlassSwitch(
          value: value,
          onChanged: onChanged,
          activeColor: activeThumbColor ?? defaultActive,
          inactiveColor: inactiveThumbColor ?? colors.textMuted,
          thumbColor: inactiveTrackColor ?? colors.trackInactive,
        );
      case null:
        return SizedBox.shrink();
    }
  }
}
