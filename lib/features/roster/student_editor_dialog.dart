import 'package:flutter/material.dart';

import '../../domain/models/models.dart';

/// Result of editing a student, so the caller can tell "saved" from "deleted".
class StudentEditorResult {
  const StudentEditorResult.saved(this.student) : delete = false;
  const StudentEditorResult.deleted(this.student) : delete = true;

  final Student student;
  final bool delete;
}

/// Creates or edits a student, including which tags apply to them.
class StudentEditorDialog extends StatefulWidget {
  const StudentEditorDialog({required this.tags, this.student, super.key});

  final List<StudentTag> tags;
  final Student? student;

  @override
  State<StudentEditorDialog> createState() => _StudentEditorDialogState();
}

class _StudentEditorDialogState extends State<StudentEditorDialog> {
  late final _first = TextEditingController(text: widget.student?.firstName ?? '');
  late final _last = TextEditingController(text: widget.student?.lastName ?? '');
  late final _notes = TextEditingController(text: widget.student?.notes ?? '');
  late GradeLevel _grade = widget.student?.gradeLevel ?? GradeLevel.grade6;
  late final Set<String> _tagIds = {...?widget.student?.tagIds};

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _first,
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
      actions: [
        if (existing != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              StudentEditorResult.deleted(existing),
            ),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
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
      ),
    );
  }
}
