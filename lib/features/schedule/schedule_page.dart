import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import '../roster/roster_membership_dialog.dart';
import 'period_editor_dialog.dart';

/// Schedule blocks connect the teaching day to reusable class rosters.
class SchedulePage extends StatefulWidget {
  const SchedulePage({
    required this.workspace,
    this.onOpenRoster,
    this.onOpenSeating,
    this.onOpenSettings,
    super.key,
  });

  final TeacherWorkspace workspace;
  final ValueChanged<String>? onOpenRoster;
  final ValueChanged<String>? onOpenSeating;
  final VoidCallback? onOpenSettings;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  TeacherWorkspace get workspace => widget.workspace;
  ValueChanged<String>? get onOpenRoster => widget.onOpenRoster;
  ValueChanged<String>? get onOpenSeating => widget.onOpenSeating;
  DateTime _date = schoolDate(DateTime.now());
  bool _allPeriods = false;

  Future<void> _schoolYear() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'School year',
      initialDateRange:
          workspace.schoolYearStart == null || workspace.schoolYearEnd == null
          ? null
          : DateTimeRange(
              start: workspace.schoolYearStart!,
              end: workspace.schoolYearEnd!,
            ),
    );
    if (range != null) workspace.setSchoolYear(range.start, range.end);
  }

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
      final periods = _allPeriods
          ? workspace.orderedPeriods
          : workspace.periodsOn(_date);
      final isCompact = context.isCompact;

      return Scaffold(
        appBar: AppBar(
          title: const Text('Schedule'),
          actions: [
            Tooltip(
              message: 'Set start and end dates to number school weeks',
              excludeFromSemantics: true,
              child: TextButton(
                onPressed: _schoolYear,
                child: const Text('School year'),
              ),
            ),
            if (isCompact && widget.onOpenSettings != null)
              IconButton(
                tooltip: 'Settings',
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        floatingActionButton: Tooltip(
          message: 'Add a class period or break to your weekly schedule',
          excludeFromSemantics: true,
          child: FloatingActionButton.extended(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Add period'),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous week',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(
                              () => _date = DateTime(
                                _date.year,
                                _date.month,
                                _date.day - 7,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Tooltip(
                              message: 'Pick a date on the calendar',
                              excludeFromSemantics: true,
                              child: TextButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _date,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() => _date = picked);
                                  }
                                },
                                child: Text(
                                  '${workspace.schoolWeek(_date) == null ? 'Week of' : 'Week ${workspace.schoolWeek(_date)} ·'} ${weekStart(_date).month}/${weekStart(_date).day}/${weekStart(_date).year}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next week',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(
                              () => _date = DateTime(
                                _date.year,
                                _date.month,
                                _date.day + 7,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_right),
                          ),
                          Tooltip(
                            message: 'Jump back to today',
                            excludeFromSemantics: true,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => setState(
                                () => _date = schoolDate(DateTime.now()),
                              ),
                              child: const Text('Today'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var day = 1; day <= 7; day++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Tooltip(
                                  message:
                                      'View schedule for ${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1]}',
                                  excludeFromSemantics: true,
                                  child: ChoiceChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      const [
                                        'Mon',
                                        'Tue',
                                        'Wed',
                                        'Thu',
                                        'Fri',
                                        'Sat',
                                        'Sun',
                                      ][day - 1],
                                    ),
                                    selected: _date.weekday == day,
                                    onSelected: (_) => setState(
                                      () => _date = DateTime(
                                        _date.year,
                                        _date.month,
                                        _date.day - _date.weekday + day,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tooltip(
                            message:
                                'Show every repeating period, including other weekdays',
                            excludeFromSemantics: true,
                            child: FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('Edit all periods'),
                              selected: _allPeriods,
                              onSelected: (value) =>
                                  setState(() => _allPeriods = value),
                            ),
                          ),
                          Tooltip(
                            message: 'Mark this date as a holiday or day off',
                            excludeFromSemantics: true,
                            child: FilterChip(
                              key: const ValueKey('day-off'),
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                'No school ${_date.month}/${_date.day}',
                              ),
                              selected: workspace.daysOff.contains(_date),
                              onSelected: (value) =>
                                  workspace.setDayOff(_date, value),
                            ),
                          ),
                          if (workspace.schoolYearStart == null)
                            Text(
                              'Set a school year to number weeks.',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: periods.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'No periods on this day.\nUse Edit all periods to manage the weekly schedule.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
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
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLow
                                  : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ListTile(
                                    onTap: () => _edit(
                                      context,
                                      workspace.period(period.id),
                                    ),
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
                                          ? _edit(
                                              context,
                                              workspace.period(period.id),
                                            )
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
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        8,
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        children: [
                                          Tooltip(
                                            message:
                                                'Check or uncheck students in this class',
                                            excludeFromSemantics: true,
                                            child: TextButton.icon(
                                              onPressed: () => manageRoster(
                                                context,
                                                workspace,
                                                section,
                                              ),
                                              icon: const Icon(
                                                Icons.playlist_add_check,
                                              ),
                                              label: const Text(
                                                'Manage students',
                                              ),
                                            ),
                                          ),
                                          if (onOpenRoster != null)
                                            Tooltip(
                                              message:
                                                  'Open this class in the Roster tab',
                                              excludeFromSemantics: true,
                                              child: TextButton(
                                                onPressed: () =>
                                                    onOpenRoster!(section.id),
                                                child: const Text(
                                                  'View roster',
                                                ),
                                              ),
                                            ),
                                          if (onOpenSeating != null)
                                            Tooltip(
                                              message:
                                                  'Open this class’s seating chart',
                                              excludeFromSemantics: true,
                                              child: TextButton(
                                                onPressed: () =>
                                                    onOpenSeating!(section.id),
                                                child: const Text(
                                                  'Seating chart',
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
