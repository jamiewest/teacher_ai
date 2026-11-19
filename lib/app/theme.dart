import 'package:flutter/material.dart';

import 'app_settings.dart';

/// App theming. A user-chosen seed and dynamic variant keep the classroom
/// canvas, panels, and controls coherent across light and dark modes.
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF247568);

  static ThemeData light([AppSettings settings = const AppSettings()]) =>
      _build(Brightness.light, settings);

  static ThemeData dark([AppSettings settings = const AppSettings()]) =>
      _build(Brightness.dark, settings);

  static ThemeData _build(Brightness brightness, AppSettings settings) {
    final scheme = ColorScheme.fromSeed(
      seedColor: settings.colorPreset.seedColor,
      brightness: brightness,
      dynamicSchemeVariant: settings.paletteStyle.variant,
    );
    final highContrast = settings.canvasStyle == CanvasStyle.highContrast;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [
        RoomThemeExtension.fromScheme(scheme, highContrast: highContrast),
      ],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      segmentedButtonTheme: const SegmentedButtonThemeData(
        style: ButtonStyle(visualDensity: VisualDensity.compact),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(milliseconds: 2500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 12),
        constraints: const BoxConstraints(minHeight: 28, maxWidth: 260),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 12,
          height: 1.3,
        ),
      ),
    );
  }
}

/// Theme extension carrying room-specific colors that adapt across light/dark
/// brightnesses and projector contrast mode.
@immutable
class RoomThemeExtension extends ThemeExtension<RoomThemeExtension> {
  const RoomThemeExtension({
    required this.canvasBackdrop,
    required this.floor,
    required this.floorShadow,
    required this.positiveBg,
    required this.positiveFg,
    required this.negativeBg,
    required this.negativeFg,
    required this.highContrast,
  });

  factory RoomThemeExtension.fromScheme(
    ColorScheme scheme, {
    bool highContrast = false,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    return RoomThemeExtension(
      canvasBackdrop: scheme.surfaceContainer,
      floor: scheme.surfaceContainerLowest,
      floorShadow: isDark
          ? Colors.black.withValues(alpha: 0.36)
          : Colors.black.withValues(alpha: 0.08),
      positiveBg: isDark ? const Color(0xFF174434) : const Color(0xFFE0F5EA),
      positiveFg: isDark ? const Color(0xFF8BE2BC) : const Color(0xFF155E45),
      negativeBg: isDark ? const Color(0xFF561D22) : const Color(0xFFFFE9E9),
      negativeFg: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFA4262C),
      highContrast: highContrast,
    );
  }

  final Color canvasBackdrop;
  final Color floor;
  final Color floorShadow;
  final Color positiveBg;
  final Color positiveFg;
  final Color negativeBg;
  final Color negativeFg;
  final bool highContrast;

  @override
  RoomThemeExtension copyWith({
    Color? canvasBackdrop,
    Color? floor,
    Color? floorShadow,
    Color? positiveBg,
    Color? positiveFg,
    Color? negativeBg,
    Color? negativeFg,
    bool? highContrast,
  }) => RoomThemeExtension(
    canvasBackdrop: canvasBackdrop ?? this.canvasBackdrop,
    floor: floor ?? this.floor,
    floorShadow: floorShadow ?? this.floorShadow,
    positiveBg: positiveBg ?? this.positiveBg,
    positiveFg: positiveFg ?? this.positiveFg,
    negativeBg: negativeBg ?? this.negativeBg,
    negativeFg: negativeFg ?? this.negativeFg,
    highContrast: highContrast ?? this.highContrast,
  );

  @override
  RoomThemeExtension lerp(
    covariant ThemeExtension<RoomThemeExtension>? other,
    double t,
  ) {
    if (other is! RoomThemeExtension) return this;
    return RoomThemeExtension(
      canvasBackdrop: Color.lerp(canvasBackdrop, other.canvasBackdrop, t)!,
      floor: Color.lerp(floor, other.floor, t)!,
      floorShadow: Color.lerp(floorShadow, other.floorShadow, t)!,
      positiveBg: Color.lerp(positiveBg, other.positiveBg, t)!,
      positiveFg: Color.lerp(positiveFg, other.positiveFg, t)!,
      negativeBg: Color.lerp(negativeBg, other.negativeBg, t)!,
      negativeFg: Color.lerp(negativeFg, other.negativeFg, t)!,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
    );
  }
}

/// Colors used when painting the classroom itself.
///
/// Pulled off the [ColorScheme] and [RoomThemeExtension] so the canvas tracks
/// light mode, dark mode, color presets, and projector contrast cleanly.
class RoomPalette {
  RoomPalette(this.scheme, [RoomThemeExtension? roomTheme])
    : _roomTheme = roomTheme ?? RoomThemeExtension.fromScheme(scheme);

  factory RoomPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    return RoomPalette(
      theme.colorScheme,
      theme.extension<RoomThemeExtension>(),
    );
  }

  final ColorScheme scheme;
  final RoomThemeExtension _roomTheme;

  Color get canvasBackdrop => _roomTheme.canvasBackdrop;
  Color get floor => _roomTheme.floor;
  Color get floorShadow => _roomTheme.floorShadow;
  Color get wall => highContrast
      ? scheme.onSurface.withValues(alpha: 0.68)
      : scheme.outlineVariant;
  Color get gridLine =>
      scheme.outlineVariant.withValues(alpha: highContrast ? 0.36 : 0.22);
  Color get gridLineMajor =>
      scheme.outlineVariant.withValues(alpha: highContrast ? 0.58 : 0.40);
  Color get deskFill => scheme.surfaceContainerLowest;
  Color get deskBorder => highContrast ? scheme.onSurface : scheme.outline;
  Color get deskText => scheme.onSurface;
  Color get fixtureFill => scheme.surfaceContainerHighest;
  Color get fixtureBorder =>
      highContrast ? scheme.onSurfaceVariant : scheme.outlineVariant;
  Color get selection => scheme.primary;
  Color get selectionFill => scheme.primary.withValues(alpha: 0.14);
  Color get marquee => scheme.primary.withValues(alpha: 0.10);
  Color get emptySeat => scheme.onSurfaceVariant;
  Color get positiveBg => _roomTheme.positiveBg;
  Color get positiveFg => _roomTheme.positiveFg;
  Color get negativeBg => _roomTheme.negativeBg;
  Color get negativeFg => _roomTheme.negativeFg;
  bool get highContrast => _roomTheme.highContrast;
}
