import 'package:flutter/material.dart';

import '../data/teacher_workspace.dart';
import '../domain/models/models.dart';
import '../features/roster/roster_page.dart';
import '../features/schedule/schedule_page.dart';
import '../features/seating/seating_page.dart';
import 'responsive.dart';

/// Top-level navigation.
///
/// The destinations are the same everywhere; only their presentation changes —
/// a bottom bar when the window is narrow, a rail when there is room, and an
/// extended rail with labels on a desktop.
class HomeShell extends StatefulWidget {
  const HomeShell({required this.workspace, super.key});

  final TeacherWorkspace workspace;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _bodyKey = GlobalKey();
  String? _classSectionId;

  static const _destinations = <_Destination>[
    _Destination('Seating', Icons.grid_view_outlined, Icons.grid_view),
    _Destination('Roster', Icons.people_outline, Icons.people),
    _Destination('Schedule', Icons.schedule_outlined, Icons.schedule),
  ];

  /// The class being worked on, defaulting to the first one the teacher has.
  ClassSection? get _section {
    final classes = widget.workspace.classes;
    if (classes.isEmpty) return null;
    final id = _classSectionId;
    if (id == null) return classes.first;
    return widget.workspace.classSection(id) ?? classes.first;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final formFactor = context.formFactor;
        final section = _section;

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
              onPickClass: _pickClass,
            ),
            RosterPage(
              workspace: widget.workspace,
              section: section,
              onSelectClass: (id) => setState(() => _classSectionId = id),
            ),
            SchedulePage(
              workspace: widget.workspace,
              onOpenRoster: (id) => _openClass(id, 1),
              onOpenSeating: (id) => _openClass(id, 0),
            ),
          ],
        );

        if (formFactor.isCompact) {
          return Scaffold(
            body: SafeArea(child: body),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Icon(
                      Icons.school_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickClass() async {
    final classes = widget.workspace.classes;
    if (classes.length < 2) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
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
    );
    if (picked != null && mounted) {
      setState(() => _classSectionId = picked);
    }
  }

  void _openClass(String classId, int destination) => setState(() {
    _classSectionId = classId;
    _index = destination;
  });
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
