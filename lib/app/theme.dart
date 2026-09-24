import 'package:flutter/material.dart';

/// App theming. A single seed keeps the classroom canvas, panels, and group
/// colors coherent in both brightnesses.
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF247568);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final scheme = brightness == Brightness.light
        ? generated.copyWith(
            surface: const Color(0xFFFCFDFC),
            surfaceContainerLow: const Color(0xFFF1F5F3),
          )
        : generated;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    );
  }
}

/// Colors used when painting the classroom itself.
///
/// These are pulled off the [ColorScheme] so the canvas tracks light and dark
/// mode instead of hard-coding a paper-white room.
class RoomPalette {
  RoomPalette(this.scheme);

  final ColorScheme scheme;

  Color get floor => scheme.surfaceContainerLowest;
  Color get wall => scheme.outlineVariant;
  Color get gridLine => scheme.outlineVariant.withValues(alpha: 0.22);
  Color get gridLineMajor => scheme.outlineVariant.withValues(alpha: 0.4);
  Color get deskFill => scheme.surfaceContainerLowest;
  Color get deskBorder => scheme.outline;
  Color get deskText => scheme.onSurface;
  Color get fixtureFill => scheme.surfaceContainerHighest;
  Color get fixtureBorder => scheme.outlineVariant;
  Color get selection => scheme.primary;
  Color get selectionFill => scheme.primary.withValues(alpha: 0.14);
  Color get marquee => scheme.primary.withValues(alpha: 0.10);
  Color get emptySeat => scheme.onSurfaceVariant;
}
