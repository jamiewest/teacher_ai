import 'package:flutter/material.dart';

import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';

/// Edits membership only; student records remain shared across class rosters.
class RosterMembershipDialog extends StatefulWidget {
  const RosterMembershipDialog({
    required this.workspace,
    required this.section,
    super.key,
  });
  final TeacherWorkspace workspace;
  final ClassSection section;

  @override
  State<RosterMembershipDialog> createState() => _RosterMembershipDialogState();
}

class _RosterMembershipDialogState extends State<RosterMembershipDialog> {
  late final _selected = widget.section.studentIds.toSet();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final students =
        widget.workspace.students
            .where(
              (student) =>
                  student.fullName.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return AlertDialog(
      title: const Text('Manage students'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.workspace.classLabel(widget.section)),
            const SizedBox(height: 8),
            Text(
              '${_selected.length} selected · Students can attend several classes.',
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search students',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: students.isEmpty
                  ? Center(
                      child: Text(
                        widget.workspace.students.isEmpty
                            ? 'Add students in Roster, then assign them here.'
                            : 'No students match your search.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final student = students[index];
                        return CheckboxListTile(
                          title: Text(student.fullName),
                          subtitle: Text(student.gradeLevel.label),
                          value: _selected.contains(student.id),
                          onChanged: (value) => setState(() {
                            if (value ?? false) {
                              _selected.add(student.id);
                            } else {
                              _selected.remove(student.id);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Save roster'),
        ),
      ],
    );
  }
}

Future<void> manageRoster(
  BuildContext context,
  TeacherWorkspace workspace,
  ClassSection section,
) async {
  final selected = await showDialog<Set<String>>(
    context: context,
    builder: (context) =>
        RosterMembershipDialog(workspace: workspace, section: section),
  );
  if (selected != null) workspace.setClassStudents(section.id, selected);
}
