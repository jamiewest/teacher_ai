import 'package:flutter/material.dart';

import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import '../roster/roster_membership_dialog.dart';
import 'period_editor_dialog.dart';

/// Schedule blocks connect the teaching day to reusable class rosters.
class SchedulePage extends StatelessWidget {
  const SchedulePage({
    required this.workspace,
    this.onOpenRoster,
    this.onOpenSeating,
    super.key,
  });
  final TeacherWorkspace workspace;
  final ValueChanged<String>? onOpenRoster;
  final ValueChanged<String>? onOpenSeating;

  Future<void> _edit(BuildContext context, SchedulePeriod? period) async {
    await showDialog<SchedulePeriod>(
      context: context,
      builder: (context) =>
          PeriodEditorDialog(workspace: workspace, period: period),
    );
  }

  Future<void> _delete(BuildContext context, SchedulePeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${period.name}"?'),
        content: const Text(
          'Remove this period from the schedule? Its student records, class roster, and saved seating charts will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete period'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) workspace.deletePeriod(period.id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: workspace,
    builder: (context, _) {
      final periods = workspace.orderedPeriods;
      return Scaffold(
        appBar: AppBar(title: const Text('Schedule')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Add period'),
        ),
        body: periods.isEmpty
            ? const Center(
                child: Text('Add a period to set up your teaching day.'),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: periods.length,
                itemBuilder: (context, index) {
                  final period = periods[index];
                  final section = workspace.classSection(
                    period.classSectionId ?? '',
                  );
                  final subject = section == null
                      ? null
                      : workspace.subject(section.subjectId);
                  return Card(
                    key: ValueKey(period.id),
                    color: period.kind.isBreak
                        ? Theme.of(context).colorScheme.surfaceContainerLow
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          onTap: () => _edit(context, period),
                          title: Text(period.name),
                          subtitle: Text(
                            '${period.start.format()} – ${period.end.format()} · ${period.durationMinutes} min'
                            '\n${period.kind.isBreak
                                ? period.kind.label
                                : section == null
                                ? "No roster linked — edit to set up"
                                : "${subject?.name ?? section.name} · ${section.size} students"}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Period options',
                            onSelected: (action) => action == 'edit'
                                ? _edit(context, period)
                                : _delete(context, period),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit period'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete period'),
                              ),
                            ],
                          ),
                        ),
                        if (!period.kind.isBreak && section != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      manageRoster(context, workspace, section),
                                  icon: const Icon(Icons.playlist_add_check),
                                  label: const Text('Manage students'),
                                ),
                                if (onOpenRoster != null)
                                  TextButton(
                                    onPressed: () => onOpenRoster!(section.id),
                                    child: const Text('View roster'),
                                  ),
                                if (onOpenSeating != null)
                                  TextButton(
                                    onPressed: () => onOpenSeating!(section.id),
                                    child: const Text('Seating chart'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      );
    },
  );
}
