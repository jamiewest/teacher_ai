import 'package:flutter/material.dart';

import '../../domain/models/models.dart';

/// Result of editing a student, so the caller can tell "saved" from "deleted".
class StudentEditorResult {
  const StudentEditorResult.saved(this.student, this.classIds) : delete = false;
  const StudentEditorResult.deleted(this.student)
    : delete = true,
      classIds = const {};

  final Student student;
  final bool delete;
  final Set<String> classIds;
}

/// Creates or edits a student, including which tags apply to them.
class StudentEditorDialog extends StatefulWidget {
  const StudentEditorDialog({
    required this.tags,
    this.student,
    this.classLabels = const {},
    this.initialClassIds = const {},
    super.key,
  });

  final List<StudentTag> tags;
  final Student? student;
  final Map<String, String> classLabels;
  final Set<String> initialClassIds;

  @override
  State<StudentEditorDialog> createState() => _StudentEditorDialogState();
}

class _StudentEditorDialogState extends State<StudentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _first = TextEditingController(
    text: widget.student?.firstName ?? '',
  );
  late final _last = TextEditingController(
    text: widget.student?.lastName ?? '',
  );
  late final _notes = TextEditingController(text: widget.student?.notes ?? '');
  late GradeLevel _grade = widget.student?.gradeLevel ?? GradeLevel.grade6;
  late final Set<String> _tagIds = {...?widget.student?.tagIds};
  late final Set<String> _classIds = {...widget.initialClassIds};

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.student;

    return AlertDialog(
      title: Text(existing == null ? 'Add student' : existing.fullName),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _first,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a first name'
                            : null,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _last,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<GradeLevel>(
                  initialValue: _grade,
                  decoration: const InputDecoration(
                    labelText: 'Grade level',
                    helperText: 'A class can mix grades',
                  ),
                  items: [
                    for (final g in GradeLevel.values)
                      DropdownMenuItem(value: g, child: Text(g.label)),
                  ],
                  onChanged: (v) => setState(() => _grade = v ?? _grade),
                ),
                const SizedBox(height: 16),
                Text(
                  'Periods and classes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Text('Select every class this student attends.'),
                if (widget.classLabels.isEmpty)
                  const Text(
                    'Add a class period in Schedule to start a roster.',
                  ),
                for (final entry in widget.classLabels.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(entry.value),
                    value: _classIds.contains(entry.key),
                    onChanged: (selected) => setState(() {
                      if (selected ?? false) {
                        _classIds.add(entry.key);
                      } else {
                        _classIds.remove(entry.key);
                      }
                    }),
                  ),
                const SizedBox(height: 16),
                Text('Tags', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                if (widget.tags.isEmpty)
                  const Text('No tags defined yet.')
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in widget.tags)
                        FilterChip(
                          avatar: CircleAvatar(
                            backgroundColor: Color(tag.colorValue),
                            radius: 7,
                          ),
                          label: Text(tag.label),
                          selected: _tagIds.contains(tag.id),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _tagIds.add(tag.id);
                            } else {
                              _tagIds.remove(tag.id);
                            }
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(StudentEditorResult.deleted(existing)),
            child: const Text('Delete student'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final first = _first.text.trim();
    if (first.isEmpty) return;
    final last = _last.text.trim();
    final tagIds = _tagIds.toList(growable: false);
    final existing = widget.student;

    Navigator.of(context).pop(
      StudentEditorResult.saved(
        existing == null
            ? Student.create(
                firstName: first,
                lastName: last,
                gradeLevel: _grade,
                tagIds: tagIds,
                notes: _notes.text.trim(),
              )
            : existing.copyWith(
                firstName: first,
                lastName: last,
                gradeLevel: _grade,
                tagIds: tagIds,
                notes: _notes.text.trim(),
              ),
        _classIds.toSet(),
      ),
    );
  }
}
