import 'dart:async';

import 'package:flutter/material.dart';

import '../data/teacher_workspace.dart';
import '../domain/models/models.dart';
import '../features/roster/roster_page.dart';
import '../features/schedule/schedule_page.dart';
import '../features/seating/seating_page.dart';
import '../features/settings/settings_sheet.dart';
import '../features/settings/classroom_files.dart';
import 'app_settings.dart';
import 'responsive.dart';

/// Top-level navigation.
///
/// The destinations are the same everywhere; only their presentation changes —
/// a compact bottom bar on narrow viewports and a rail with Settings access on
/// wider viewports, both hidden in fullscreen canvas mode.
class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.workspace,
    this.settings,
    this.classroomFiles,
    this.accountSettings,
    this.now,
    super.key,
  });

  final TeacherWorkspace workspace;
  final ClassroomFiles? classroomFiles;
  final Widget? accountSettings;
  final AppSettingsController? settings;
  final DateTime Function()? now;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _bodyKey = GlobalKey();
  String? _classSectionId;
  String? _editingClassId;
  bool _fullscreen = false;
  Timer? _clock;
  AppSettingsController? _ownedSettings;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  AppSettingsController get _settings =>
      widget.settings ?? (_ownedSettings ??= AppSettingsController.memory());

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _ownedSettings?.dispose();
    super.dispose();
  }

  static const _destinations = <_Destination>[
    _Destination(
      'Seating',
      Icons.grid_view_outlined,
      Icons.grid_view,
      'Live participation, seating charts, and room layout',
    ),
    _Destination(
      'Roster',
      Icons.people_outline,
      Icons.people,
      'Students, class memberships, and seating tags',
    ),
    _Destination(
      'Schedule',
      Icons.schedule_outlined,
      Icons.schedule,
      'Weekly periods, school year, and days off',
    ),
  ];

  /// The class being worked on, defaulting to the current period or first one.
  ClassSection? get _section {
    final classes = widget.workspace.classes;
    if (classes.isEmpty) return null;
    final id = _editingClassId ?? _classSectionId;
    if (id == null) {
      return widget.workspace.currentClass(_now) ?? classes.first;
    }
    return widget.workspace.classSection(id) ?? classes.first;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final formFactor = context.formFactor;
        final section = _section;
        final isFullscreen = _fullscreen && _index == 0;
        final current = widget.workspace.currentPeriod(_now);

        // IndexedStack, not a switch: swapping the child would unmount the
        // seating editor and take its unsaved layout edits, undo history, and
        // scroll positions with it.
        final body = IndexedStack(
          key: _bodyKey,
          index: _index,
          children: [
            SeatingPage(
              workspace: widget.workspace,
              section: section,
              settings: _settings,
              isFollowingSchedule:
                  _classSectionId == null && _editingClassId == null,
              isHeldWhileEditing: _editingClassId != null,
              currentPeriod: current,
              isFullscreen: _fullscreen,
              onFullscreenChanged: (v) => setState(() => _fullscreen = v),
              onPickClass: _pickClass,
              onOpenSettings: _openSettings,
              onEditingChanged: (editing) => setState(
                () => _editingClassId = editing ? _section?.id : null,
              ),
            ),
            RosterPage(
              workspace: widget.workspace,
              section: section,
              onOpenSettings: _openSettings,
              onSelectClass: (id) => setState(() {
                _classSectionId = id;
                if (_editingClassId != null) _editingClassId = id;
              }),
            ),
            SchedulePage(
              workspace: widget.workspace,
              onOpenSettings: _openSettings,
              onOpenRoster: (id) => _openClass(id, 1),
              onOpenSeating: (id) => _openClass(id, 0),
            ),
          ],
        );

        if (formFactor.isCompact) {
          return Scaffold(
            body: SafeArea(child: body),
            bottomNavigationBar: isFullscreen
                ? null
                : NavigationBar(
                    height: 64,
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    destinations: [
                      for (final d in _destinations)
                        NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: d.label,
                          tooltip: d.tooltip,
                        ),
                    ],
                  ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (!isFullscreen) ...[
                  NavigationRail(
                    minWidth: 72,
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Tooltip(
                        message: 'Teacher AI',
                        excludeFromSemantics: true,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.school_outlined,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    trailing: Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: IconButton(
                            tooltip: 'Settings',
                            icon: const Icon(Icons.settings_outlined),
                            onPressed: _openSettings,
                          ),
                        ),
                      ),
                    ),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Tooltip(
                            message: d.tooltip,
                            excludeFromSemantics: true,
                            child: Icon(d.icon),
                          ),
                          selectedIcon: Tooltip(
                            message: d.tooltip,
                            excludeFromSemantics: true,
                            child: Icon(d.selectedIcon),
                          ),
                          label: Tooltip(
                            message: d.tooltip,
                            excludeFromSemantics: true,
                            child: Text(d.label),
                          ),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                ],
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettings() => openSettings(
    context,
    _settings,
    widget.classroomFiles ?? ClassroomFiles(workspace: widget.workspace),
    accountSettings: widget.accountSettings,
  );

  Future<void> _pickClass() async {
    final classes = widget.workspace.classes;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Switch class', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'Choose a class to view, or follow your schedule automatically.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('Follow current period'),
                      subtitle: const Text(
                        'Use the weekday schedule and local time',
                      ),
                      selected: _classSectionId == null,
                      onTap: () => Navigator.of(context).pop('__auto__'),
                    ),
                    for (final c in classes)
                      ListTile(
                        title: Text(widget.workspace.classLabel(c)),
                        subtitle: Text('${c.size} students'),
                        selected: c.id == _section?.id,
                        onTap: () => Navigator.of(context).pop(c.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _classSectionId = picked == '__auto__' ? null : picked;
        if (_editingClassId != null) {
          _editingClassId =
              _classSectionId ??
              widget.workspace.currentClass(_now)?.id ??
              classes.firstOrNull?.id;
        }
      });
    }
  }

  void _openClass(String classId, int destination) => setState(() {
    _classSectionId = classId;
    if (_editingClassId != null) _editingClassId = classId;
    _fullscreen = false;
    _index = destination;
  });
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.tooltip);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String tooltip;
}
