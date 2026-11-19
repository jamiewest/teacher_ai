import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';

/// Opens appearance and canvas settings in a bottom sheet on phones and a
/// centered dialog on tablets/desktops.
Future<void> openSettings(
  BuildContext context,
  AppSettingsController settings,
  Widget classroomFiles, {
  Widget? accountSettings,
}) async {
  if (context.isCompact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _SettingsBody(
          settings: settings,
          classroomFiles: classroomFiles,
          accountSettings: accountSettings,
          isDialog: false,
        ),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: _SettingsBody(
          settings: settings,
          classroomFiles: classroomFiles,
          accountSettings: accountSettings,
          isDialog: true,
        ),
      ),
    ),
  );
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.settings,
    required this.isDialog,
    required this.classroomFiles,
    this.accountSettings,
  });

  final AppSettingsController settings;
  final bool isDialog;
  final Widget classroomFiles;
  final Widget? accountSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final current = settings.settings;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, isDialog ? 16 : 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Settings', style: theme.textTheme.titleLarge),
                  ),
                  Tooltip(
                    message: 'Restore default appearance and canvas settings',
                    excludeFromSemantics: true,
                    child: TextButton(
                      onPressed: current == const AppSettings()
                          ? null
                          : settings.resetDefaults,
                      child: const Text('Reset'),
                    ),
                  ),
                  if (isDialog)
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (accountSettings != null) ...[
                    _SectionHeader('Account & sync', scheme),
                    accountSettings!,
                    const Divider(),
                    const SizedBox(height: 20),
                  ],
                  const _ClassroomPreviewCard(),
                  const SizedBox(height: 20),
                  _SectionHeader('Appearance', scheme),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        tooltip: 'Match your device appearance',
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        tooltip: 'Always use light theme',
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        tooltip: 'Always use dark theme',
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {current.themeMode},
                    onSelectionChanged: (values) =>
                        settings.setThemeMode(values.first),
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader('Color theme', scheme),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in AppColorPreset.values)
                        _ColorPresetChip(
                          preset: preset,
                          selected: current.colorPreset == preset,
                          onTap: () => settings.setColorPreset(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader('Color vibrancy', scheme),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final style in PaletteStyle.values)
                        Tooltip(
                          message: switch (style) {
                            PaletteStyle.balanced =>
                              'Balanced Material colors for everyday use',
                            PaletteStyle.vibrant =>
                              'Higher-saturation accent colors',
                            PaletteStyle.muted =>
                              'Softer, low-contrast pastel accents',
                            PaletteStyle.expressive =>
                              'Bolder complementary accent contrast',
                          },
                          excludeFromSemantics: true,
                          child: ChoiceChip(
                            label: Text(style.label),
                            selected: current.paletteStyle == style,
                            onSelected: (_) => settings.setPaletteStyle(style),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader('Classroom canvas', scheme),
                  const SizedBox(height: 8),
                  SegmentedButton<CanvasStyle>(
                    showSelectedIcon: false,
                    segments: [
                      for (final style in CanvasStyle.values)
                        ButtonSegment(
                          value: style,
                          tooltip: style == CanvasStyle.standard
                              ? 'Subtle borders for laptop and tablet screens'
                              : 'High-contrast desk outlines for classroom projectors',
                          icon: Icon(
                            style == CanvasStyle.standard
                                ? Icons.grid_view_outlined
                                : Icons.contrast,
                          ),
                          label: Text(style.label),
                        ),
                    ],
                    selected: {current.canvasStyle},
                    onSelectionChanged: (values) =>
                        settings.setCanvasStyle(values.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Projector mode darkens desk borders for classroom displays.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show room grid by default'),
                    subtitle: const Text(
                      'Displays grid lines when designing layouts',
                    ),
                    value: current.showGridByDefault,
                    onChanged: settings.setShowGridByDefault,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show student tag dots by default'),
                    subtitle: const Text(
                      'Displays colored student tag markers on zoomed desks',
                    ),
                    value: current.showTagDotsByDefault,
                    onChanged: settings.setShowTagDotsByDefault,
                  ),
                  const SizedBox(height: 16),
                  _SectionHeader('Teacher AI Pro', scheme),
                  const SizedBox(height: 8),
                  Card(
                    color: scheme.secondaryContainer.withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              size: 20,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Classroom & Seating Assistant',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Optional subscription tier for smart seating charts, Kagan team balancing, and AI room layout suggestions.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader('Classroom files', scheme),
                  const SizedBox(height: 4),
                  Text(
                    'Back up your classroom as JSON or move data between devices.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  classroomFiles,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.scheme);

  final String title;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 0.9,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _ColorPresetChip extends StatelessWidget {
  const _ColorPresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppColorPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: preset.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: preset.seedColor,
                radius: 10,
                child: selected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                preset.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassroomPreviewCard extends StatelessWidget {
  const _ClassroomPreviewCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = RoomPalette.of(context);
    final borderWidth = palette.highContrast ? 1.8 : 1.0;

    return Container(
      height: 88,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.canvasBackdrop,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.floor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.wall),
          boxShadow: [
            BoxShadow(
              color: palette.floorShadow,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _MiniDesk(
                    label: 'Ava M.',
                    tint: scheme.primary,
                    palette: palette,
                    borderWidth: borderWidth,
                    badgeText: '+2',
                    badgeBg: palette.positiveBg,
                    badgeFg: palette.positiveFg,
                  ),
                  const SizedBox(width: 8),
                  _MiniDesk(
                    label: 'Noah B.',
                    tint: scheme.secondary,
                    palette: palette,
                    borderWidth: borderWidth,
                    badgeText: '−1',
                    badgeBg: palette.negativeBg,
                    badgeFg: palette.negativeFg,
                  ),
                  const SizedBox(width: 8),
                  _MiniDesk(
                    label: 'Sofia D.',
                    tint: null,
                    palette: palette,
                    borderWidth: borderWidth,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Preview',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDesk extends StatelessWidget {
  const _MiniDesk({
    required this.label,
    required this.tint,
    required this.palette,
    required this.borderWidth,
    this.badgeText,
    this.badgeBg,
    this.badgeFg,
  });

  final String label;
  final Color? tint;
  final RoomPalette palette;
  final double borderWidth;
  final String? badgeText;
  final Color? badgeBg;
  final Color? badgeFg;

  @override
  Widget build(BuildContext context) {
    final fill = tint == null
        ? palette.deskFill
        : Color.alphaBlend(tint!.withValues(alpha: 0.16), palette.deskFill);

    return Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.deskBorder, width: borderWidth),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: palette.deskText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (badgeText != null && badgeBg != null && badgeFg != null)
            Positioned(
              top: -6,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  badgeText!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeFg,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
