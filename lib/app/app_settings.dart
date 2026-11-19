import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/key_value_store.dart';

/// Curated Material 3 seed colors tuned for daily classroom readability.
enum AppColorPreset {
  teal(Color(0xFF247568), 'Chalkboard Teal'),
  ocean(Color(0xFF1E6091), 'Ocean Blue'),
  indigo(Color(0xFF4355B9), 'Indigo Slate'),
  sage(Color(0xFF3A7D56), 'Forest Sage'),
  terracotta(Color(0xFFB85C38), 'Warm Terracotta'),
  plum(Color(0xFF8E4162), 'Berry Plum'),
  amber(Color(0xFFA66E1B), 'Amber Ochre'),
  graphite(Color(0xFF52606D), 'Graphite Neutral');

  const AppColorPreset(this.seedColor, this.label);

  final Color seedColor;
  final String label;

  static AppColorPreset fromJson(String? name) =>
      AppColorPreset.values.firstWhere(
        (preset) => preset.name == name,
        orElse: () => AppColorPreset.teal,
      );
}

/// Material 3 dynamic scheme variants controlling palette vibrancy.
enum PaletteStyle {
  balanced(DynamicSchemeVariant.tonalSpot, 'Balanced'),
  vibrant(DynamicSchemeVariant.vibrant, 'Vibrant'),
  muted(DynamicSchemeVariant.neutral, 'Soft'),
  expressive(DynamicSchemeVariant.expressive, 'Expressive');

  const PaletteStyle(this.variant, this.label);

  final DynamicSchemeVariant variant;
  final String label;

  static PaletteStyle fromJson(String? name) => PaletteStyle.values.firstWhere(
    (style) => style.name == name,
    orElse: () => PaletteStyle.balanced,
  );
}

/// Room canvas rendering contrast mode.
enum CanvasStyle {
  standard('Standard'),
  highContrast('Projector');

  const CanvasStyle(this.label);

  final String label;

  static CanvasStyle fromJson(String? name) => CanvasStyle.values.firstWhere(
    (style) => style.name == name,
    orElse: () => CanvasStyle.standard,
  );
}

/// User-customizable appearance and default canvas preferences.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.colorPreset = AppColorPreset.teal,
    this.paletteStyle = PaletteStyle.balanced,
    this.canvasStyle = CanvasStyle.standard,
    this.showGridByDefault = true,
    this.showTagDotsByDefault = true,
  });

  final ThemeMode themeMode;
  final AppColorPreset colorPreset;
  final PaletteStyle paletteStyle;
  final CanvasStyle canvasStyle;
  final bool showGridByDefault;
  final bool showTagDotsByDefault;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppColorPreset? colorPreset,
    PaletteStyle? paletteStyle,
    CanvasStyle? canvasStyle,
    bool? showGridByDefault,
    bool? showTagDotsByDefault,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    colorPreset: colorPreset ?? this.colorPreset,
    paletteStyle: paletteStyle ?? this.paletteStyle,
    canvasStyle: canvasStyle ?? this.canvasStyle,
    showGridByDefault: showGridByDefault ?? this.showGridByDefault,
    showTagDotsByDefault: showTagDotsByDefault ?? this.showTagDotsByDefault,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'colorPreset': colorPreset.name,
    'paletteStyle': paletteStyle.name,
    'canvasStyle': canvasStyle.name,
    'showGridByDefault': showGridByDefault,
    'showTagDotsByDefault': showTagDotsByDefault,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final modeName = json['themeMode'] as String?;
    final themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => ThemeMode.system,
    );
    return AppSettings(
      themeMode: themeMode,
      colorPreset: AppColorPreset.fromJson(json['colorPreset'] as String?),
      paletteStyle: PaletteStyle.fromJson(json['paletteStyle'] as String?),
      canvasStyle: CanvasStyle.fromJson(json['canvasStyle'] as String?),
      showGridByDefault: json['showGridByDefault'] as bool? ?? true,
      showTagDotsByDefault: json['showTagDotsByDefault'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          colorPreset == other.colorPreset &&
          paletteStyle == other.paletteStyle &&
          canvasStyle == other.canvasStyle &&
          showGridByDefault == other.showGridByDefault &&
          showTagDotsByDefault == other.showTagDotsByDefault;

  @override
  int get hashCode => Object.hash(
    themeMode,
    colorPreset,
    paletteStyle,
    canvasStyle,
    showGridByDefault,
    showTagDotsByDefault,
  );
}

/// Loads, holds, and persists [AppSettings] independently of [TeacherWorkspace].
class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this._store, [AppSettings initial = const AppSettings()])
    : _settings = initial;

  factory AppSettingsController.memory([
    AppSettings initial = const AppSettings(),
  ]) => AppSettingsController(InMemoryStore(), initial);

  static const String storageKey = 'teacher_ai.settings.v1';

  final KeyValueStore _store;
  AppSettings _settings;
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    try {
      final raw = await _store.read(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          _settings = AppSettings.fromJson(decoded);
        } else if (decoded is Map) {
          _settings = AppSettings.fromJson(Map<String, Object?>.from(decoded));
        }
      }
    } catch (_) {
      // Corrupt or unreadable settings fall back to defaults instead of
      // blocking startup.
      _settings = const AppSettings();
    }
    _loaded = true;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) =>
      _update(_settings.copyWith(themeMode: mode));

  void setColorPreset(AppColorPreset preset) =>
      _update(_settings.copyWith(colorPreset: preset));

  void setPaletteStyle(PaletteStyle style) =>
      _update(_settings.copyWith(paletteStyle: style));

  void setCanvasStyle(CanvasStyle style) =>
      _update(_settings.copyWith(canvasStyle: style));

  void setShowGridByDefault(bool show) =>
      _update(_settings.copyWith(showGridByDefault: show));

  void setShowTagDotsByDefault(bool show) =>
      _update(_settings.copyWith(showTagDotsByDefault: show));

  void resetDefaults() => _update(const AppSettings());

  void _update(AppSettings next) {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    unawaited(_persist(next));
  }

  Future<void> _persist(AppSettings snapshot) async {
    try {
      await _store.write(storageKey, jsonEncode(snapshot.toJson()));
    } catch (_) {
      // Persistence errors should not disrupt active UI styling.
    }
  }
}
