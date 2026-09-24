import 'package:flutter/material.dart';

import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';

/// The teaching day, including the breaks between classes.
///
/// Breaks are modelled, not implied by the gaps, because passing time and
/// lunch are real constraints on what a lesson can ask for — something the
/// lesson planner will lean on.
class SchedulePage extends StatelessWidget {
  const SchedulePage({required this.workspace, super.key});

  final TeacherWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        final periods = workspace.orderedPeriods;

        return Scaffold(
          appBar: AppBar(title: const Text('Schedule')),
          body: periods.isEmpty
              ? const Center(child: Text('No periods set up yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: periods.length,
                  itemBuilder: (context, index) =>
                      _PeriodTile(period: periods[index], workspace: workspace),
                ),
        );
      },
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({required this.period, required this.workspace});

  final SchedulePeriod period;
  final TeacherWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final section = period.classSectionId == null
        ? null
        : workspace.classSection(period.classSectionId!);
    final subject = section == null ? null : workspace.subject(section.subjectId);
    final isBreak = period.kind.isBreak;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isBreak ? scheme.surfaceContainerLow : null,
      child: ListTile(
        leading: Container(
          width: 6,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: isBreak
                ? scheme.outlineVariant
                : Color(subject?.colorValue ?? scheme.primary.toARGB32()),
          ),
        ),
        title: Text(period.name),
        subtitle: Text(
          '${period.start.format()} – ${period.end.format()} '
          '· ${period.durationMinutes} min'
          '${section == null ? '' : ' · ${section.size} students'}',
        ),
        trailing: isBreak
            ? Chip(
                visualDensity: VisualDensity.compact,
                label: Text(period.kind.label),
              )
            : null,
      ),
    );
  }
}
