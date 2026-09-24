import 'package:flutter/material.dart';

import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';

class PeriodEditorDialog extends StatefulWidget {
  const PeriodEditorDialog({required this.workspace, this.period, super.key});
  final TeacherWorkspace workspace;
  final SchedulePeriod? period;

  @override
  State<PeriodEditorDialog> createState() => _PeriodEditorDialogState();
}

class _PeriodEditorDialogState extends State<PeriodEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.period?.name ?? '');
  late final _start = TextEditingController(
    text: widget.period?.start.format(use24Hour: true) ?? '08:00',
  );
  late final _end = TextEditingController(
    text: widget.period?.end.format(use24Hour: true) ?? '08:50',
  );
  final _className = TextEditingController();
  late final _subject = TextEditingController(
    text: widget.workspace.subjects.firstOrNull?.name ?? '',
  );
  late PeriodKind _kind = widget.period?.kind ?? PeriodKind.classTime;
  late String _classId =
      widget.workspace.classSection(widget.period?.classSectionId ?? '')?.id ??
      '';

  @override
  void dispose() {
    for (final controller in [_name, _start, _end, _className, _subject]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.period == null ? 'Add period' : 'Edit period'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Period name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a period name'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PeriodKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Period type'),
                items: [
                  for (final kind in PeriodKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (kind) {
                  if (kind != null) setState(() => _kind = kind);
                },
              ),
              const SizedBox(height: 12),
              _timeField(_start, 'Start time'),
              const SizedBox(height: 12),
              _timeField(_end, 'End time', isEnd: true),
              if (!_kind.isBreak) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Class roster'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Create a new roster'),
                    ),
                    for (final section in widget.workspace.classes)
                      DropdownMenuItem(
                        value: section.id,
                        child: Text(
                          section.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _classId = id ?? ''),
                ),
                const SizedBox(height: 12),
                if (_classId.isEmpty) ...[
                  TextFormField(
                    controller: _className,
                    decoration: const InputDecoration(
                      labelText: 'Class name (optional)',
                      helperText: 'Uses the period name if left blank',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _subject,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      hintText: 'e.g. Algebra I',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a subject'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A new roster starts empty, with its own seating layout. Add students after saving.',
                  ),
                ] else
                  Text(
                    'Uses the students and seating layouts of ${widget.workspace.classSection(_classId)!.name}. '
                    'Periods linked to this class share a roster. Choose a new roster for a separate group of students.',
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save period')),
    ],
  );

  Widget _timeField(
    TextEditingController controller,
    String label, {
    bool isEnd = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.datetime,
    decoration: InputDecoration(
      labelText: label,
      helperText: '24-hour time, e.g. 13:30',
      suffixIcon: IconButton(
        tooltip: 'Choose ${label.toLowerCase()}',
        icon: const Icon(Icons.schedule),
        onPressed: () async {
          final value =
              TimeOfDayMinutes.tryParse(controller.text) ??
              const TimeOfDayMinutes.at(8, 0);
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
          );
          if (picked != null && mounted)
            controller.text = TimeOfDayMinutes.at(
              picked.hour,
              picked.minute,
            ).format(use24Hour: true);
        },
      ),
    ),
    validator: (value) {
      final time = TimeOfDayMinutes.tryParse(value ?? '');
      if (time == null) return 'Enter a valid time (HH:MM)';
      final start = TimeOfDayMinutes.tryParse(_start.text);
      if (isEnd && start != null && time.minutes <= start.minutes)
        return 'End time must be after start time';
      return null;
    },
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final period =
        (widget.period ??
                SchedulePeriod.create(
                  name: '',
                  kind: _kind,
                  start: const TimeOfDayMinutes(0),
                  end: const TimeOfDayMinutes(0),
                ))
            .copyWith(
              name: _name.text.trim(),
              kind: _kind,
              start: TimeOfDayMinutes.tryParse(_start.text)!,
              end: TimeOfDayMinutes.tryParse(_end.text)!,
              classSectionId: _classId.isEmpty ? null : _classId,
              clearSection: _classId.isEmpty || _kind.isBreak,
            );
    final saved = widget.workspace.savePeriod(
      period,
      newClassName: _className.text.trim().isEmpty
          ? _name.text.trim()
          : _className.text.trim(),
      newSubjectName: _subject.text.trim(),
    );
    Navigator.of(context).pop(saved);
  }
}
