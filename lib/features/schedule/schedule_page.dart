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
      final classCount = periods.where((p) => !p.kind.isBreak).length;
      final breakCount = periods.length - classCount;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final isCompact = context.isCompact;
      final now = DateTime.now();

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
                Material(
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
                            if (periods.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer.withValues(
                                    alpha: 0.6,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$classCount ${classCount == 1 ? 'class' : 'classes'}'
                                  '${breakCount > 0 ? ' · $breakCount ${breakCount == 1 ? 'break' : 'breaks'}' : ''}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            if (workspace.schoolYearStart == null)
                              Text(
                                'Set a school year to number weeks.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
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
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                          itemCount: periods.length,
                          itemBuilder: (context, index) {
                            final period = periods[index];
                            final isCurrent =
                                !_allPeriods &&
                                schoolDate(now) == _date &&
                                workspace.currentPeriod(now)?.id == period.id;
                            final section = workspace.classSection(
                              period.classSectionId ?? '',
                            );
                            final subject = section == null
                                ? null
                                : workspace.subject(section.subjectId);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: period.kind.isBreak
                                  ? _BreakPeriodCard(
                                      period: period,
                                      onEdit: () => _edit(
                                        context,
                                        workspace.period(period.id),
                                      ),
                                      onDelete: () => _delete(context, period),
                                    )
                                  : _ClassPeriodCard(
                                      period: period,
                                      section: section,
                                      subject: subject,
                                      layoutCount: section == null
                                          ? 0
                                          : workspace
                                                .layoutsFor(section.id)
                                                .length,
                                      isCurrent: isCurrent,
                                      showWeekdays: _allPeriods,
                                      onEdit: () => _edit(
                                        context,
                                        workspace.period(period.id),
                                      ),
                                      onDelete: () => _delete(context, period),
                                      onManageRoster: section == null
                                          ? null
                                          : () => manageRoster(
                                              context,
                                              workspace,
                                              section,
                                            ),
                                      onOpenRoster:
                                          section == null ||
                                              onOpenRoster == null
                                          ? null
                                          : () => onOpenRoster!(section.id),
                                      onOpenSeating:
                                          section == null ||
                                              onOpenSeating == null
                                          ? null
                                          : () => onOpenSeating!(section.id),
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

class _PeriodMenuButton extends StatelessWidget {
  const _PeriodMenuButton({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Period options',
    onSelected: (action) => action == 'edit' ? onEdit() : onDelete(),
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'edit', child: Text('Edit period')),
      PopupMenuItem(value: 'delete', child: Text('Delete period')),
    ],
  );
}

class _BreakPeriodCard extends StatelessWidget {
  const _BreakPeriodCard({
    required this.period,
    required this.onEdit,
    required this.onDelete,
  });

  final SchedulePeriod period;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: ValueKey(period.id),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _breakIcon(period.kind),
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(period.name, style: theme.textTheme.titleSmall),
                        Text(
                          period.kind.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${period.start.format()} – ${period.end.format()} · ${period.durationMinutes} min',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              _PeriodMenuButton(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassPeriodCard extends StatelessWidget {
  const _ClassPeriodCard({
    required this.period,
    required this.section,
    required this.subject,
    required this.layoutCount,
    required this.isCurrent,
    required this.showWeekdays,
    required this.onEdit,
    required this.onDelete,
    this.onManageRoster,
    this.onOpenRoster,
    this.onOpenSeating,
  });

  final SchedulePeriod period;
  final ClassSection? section;
  final Subject? subject;
  final int layoutCount;
  final bool isCurrent;
  final bool showWeekdays;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onManageRoster;
  final VoidCallback? onOpenRoster;
  final VoidCallback? onOpenSeating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: ValueKey(period.id),
      color: isCurrent
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              scheme.surfaceContainerLow,
            )
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCurrent ? scheme.primary : scheme.outlineVariant,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? scheme.primary
                                    : scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${period.start.format()} – ${period.end.format()}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: isCurrent
                                      ? scheme.onPrimary
                                      : scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              '${period.durationMinutes} min',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Now',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onTertiaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (showWeekdays)
                              Text(
                                _weekdaysLabel(period.weekdays),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          period.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (section == null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'No roster linked — edit to set up',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _MetaPill(
                                icon: Icons.school_outlined,
                                label: subject?.name ?? section!.name,
                                background: scheme.secondaryContainer,
                                foreground: scheme.onSecondaryContainer,
                              ),
                              _MetaPill(
                                icon: Icons.people_outline,
                                label: '${section!.size} students',
                                background: scheme.surfaceContainerHighest,
                                foreground: scheme.onSurfaceVariant,
                              ),
                              _MetaPill(
                                icon: Icons.grid_view_outlined,
                                label:
                                    '$layoutCount ${layoutCount == 1 ? 'layout' : 'layouts'}',
                                background: scheme.surfaceContainerHighest,
                                foreground: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  _PeriodMenuButton(onEdit: onEdit, onDelete: onDelete),
                ],
              ),
            ),
          ),
          if (section != null) ...[
            const Divider(height: 1),
            ColoredBox(
              color: scheme.surfaceContainer.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (onOpenSeating != null)
                      Tooltip(
                        message: 'Open this class’s seating chart',
                        excludeFromSemantics: true,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onOpenSeating,
                          icon: const Icon(Icons.grid_view_rounded, size: 16),
                          label: const Text('Seating chart'),
                        ),
                      ),
                    if (onOpenRoster != null)
                      Tooltip(
                        message: 'Open this class in the Roster tab',
                        excludeFromSemantics: true,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onOpenRoster,
                          icon: const Icon(Icons.people_outline, size: 16),
                          label: const Text('View roster'),
                        ),
                      ),
                    if (onManageRoster != null)
                      Tooltip(
                        message: 'Check or uncheck students in this class',
                        excludeFromSemantics: true,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onManageRoster,
                          icon: const Icon(Icons.playlist_add_check, size: 16),
                          label: const Text('Manage students'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: foreground),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: foreground),
        ),
      ],
    ),
  );
}

IconData _breakIcon(PeriodKind kind) => switch (kind) {
  PeriodKind.passing => Icons.directions_walk,
  PeriodKind.lunch => Icons.restaurant_outlined,
  PeriodKind.recess => Icons.park_outlined,
  PeriodKind.prep => Icons.edit_note_outlined,
  PeriodKind.duty => Icons.assignment_ind_outlined,
  PeriodKind.classTime => Icons.school_outlined,
};

String _weekdaysLabel(List<int> weekdays) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final sorted = weekdays.toSet().toList()..sort();
  if (sorted.length == 5 && sorted.first == 1 && sorted.last == 5) {
    return 'Mon–Fri';
  }
  return [for (final day in sorted) names[day - 1]].join(', ');
}
