import 'package:flutter/material.dart';

import '../../../data/teacher_workspace.dart';
import '../../../domain/models/models.dart';
import '../seating_editor_controller.dart';

/// The class roster beside the chart, showing who is seated and who is not.
///
/// Tapping a student seats them in the selected desk, or jumps to their seat
/// when nothing is selected — the two things a teacher actually wants from a
/// name list next to a seating chart.
class RosterPanel extends StatefulWidget {
  const RosterPanel({
    required this.editor,
    required this.workspace,
    this.onFocusDesk,
    this.onStudentPicked,
    super.key,
  });

  final SeatingEditorController editor;
  final TeacherWorkspace workspace;
  final VoidCallback? onStudentPicked;

  /// Called with a desk id when the panel wants the canvas to reveal a seat.
  final void Function(String deskId)? onFocusDesk;

  @override
  State<RosterPanel> createState() => _RosterPanelState();
}

class _RosterPanelState extends State<RosterPanel> {
  String _query = '';
  bool _onlyUnseated = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.editor,
      builder: (context, _) {
        final editor = widget.editor;
        final roster = editor.roster;
        final unseated = editor.unseatedStudents.map((s) => s.id).toSet();
        final needle = _query.trim().toLowerCase();
        final visible = roster
            .where(
              (student) =>
                  (!_onlyUnseated || unseated.contains(student.id)) &&
                  (needle.isEmpty ||
                      student.fullName.toLowerCase().contains(needle)),
            )
            .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Students', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${roster.length} students · '
                    '${unseated.length} need a seat',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Find a student',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text('All ${roster.length}'),
                        selected: !_onlyUnseated,
                        onSelected: (_) =>
                            setState(() => _onlyUnseated = false),
                      ),
                      ChoiceChip(
                        label: Text('Unseated ${unseated.length}'),
                        selected: _onlyUnseated,
                        onSelected: (_) => setState(() => _onlyUnseated = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    editor.pendingStudent == null
                        ? 'Choose a student, then tap their seat.'
                        : 'Tap a seat to place them. A seated student can swap places.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        roster.isEmpty
                            ? 'No students on this roster yet.'
                            : _onlyUnseated && needle.isEmpty
                            ? 'Everyone has a seat.'
                            : 'No match for "$_query".',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final student = visible[index];
                        return _StudentTile(
                          student: student,
                          workspace: widget.workspace,
                          editor: editor,
                          isUnseated: unseated.contains(student.id),
                          onTap: () => _onStudentTap(student),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _onStudentTap(Student student) {
    final editor = widget.editor;
    editor.pickStudent(
      editor.pendingStudentId == student.id ? null : student.id,
    );
    widget.onStudentPicked?.call();
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.student,
    required this.workspace,
    required this.editor,
    required this.isUnseated,
    required this.onTap,
  });

  final Student student;
  final TeacherWorkspace workspace;
  final SeatingEditorController editor;
  final bool isUnseated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deskId = editor.snapshot.deskForStudent(student.id);
    final group = deskId == null ? null : editor.layout.groupForDesk(deskId);
    final tags = [for (final id in student.tagIds) ?workspace.tag(id)];

    return ListTile(
      dense: true,
      selected: editor.pendingStudentId == student.id,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isUnseated
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        child: Text(
          student.initials,
          style: TextStyle(
            fontSize: 12,
            color: isUnseated
                ? scheme.onSurfaceVariant
                : scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(student.fullName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${student.gradeLevel.code} · ${group?.name ?? (isUnseated ? 'Needs a seat' : 'Seated')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      trailing: tags.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tag in tags.take(3))
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Tooltip(
                      message: tag.label,
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: Color(tag.colorValue),
                      ),
                    ),
                  ),
              ],
            ),
      onTap: onTap,
    );
  }
}
