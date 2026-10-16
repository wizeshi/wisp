import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

class GenericSlider extends StatelessWidget {
  final ValueChanged<double>? onChanged;
  final Color? activeTrackColor;
  final Color? inactiveTrackColor;
  final Color? thumbColor;
  final Color? overlayColor;
  final double? trackHeight;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final AppStyle? style;

  const GenericSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.overlayColor,
    this.trackHeight,
    required this.min,
    required this.max,
    this.divisions,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final AppStyle? style =
        this.style ??
        context.select<PreferencesProvider, AppStyle?>(
          (provider) => provider.style,
        );

    switch (style) {
      case AppStyle.Original:
        return M3ESlider(
          value: value, 
          onChanged: onChanged,
          divisions: divisions,
          min: min,
          max: max,
        );
      case AppStyle.Spotify:
        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor:
                activeTrackColor ?? Theme.of(context).colorScheme.primary,
            inactiveTrackColor: inactiveTrackColor ?? Colors.grey[800],
            thumbColor: thumbColor ?? Theme.of(context).colorScheme.primary,
            overlayColor:
                overlayColor ??
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            trackHeight: trackHeight ?? 4,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        );
      case AppStyle.AppleMusic:
        return LayoutBuilder(
          builder: ((context, constraints) => LiquidGlassSlider(
            value: value,
            minimumValue: min,
            maximumValue: max,
            onChanged: (value) {},
            onChangeEnd: onChanged,
            activeColor: activeTrackColor ?? Theme.of(context).colorScheme.primary,
            inactiveColor: inactiveTrackColor ?? Colors.grey,
            thumbColor: thumbColor ?? Colors.grey.shade400,
            isContinuous: false,
            width: constraints.maxWidth,
            height: trackHeight ?? 4,
          )),
        );
      case null:
        return SizedBox.shrink();
    }
  }
}
