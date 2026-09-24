import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import 'student_editor_dialog.dart';
import 'tag_editor_dialog.dart';

/// Students and the tags applied to them.
///
/// Tags live beside the roster rather than buried in the seating editor: they
/// are class-wide knowledge the teacher builds up over time, and the seating
/// chart is only one of the things that will read them.
class RosterPage extends StatefulWidget {
  const RosterPage({required this.workspace, required this.section, super.key});

  final TeacherWorkspace workspace;
  final ClassSection? section;

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {
  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    if (section == null) {
      return const Center(child: Text('No class selected.'));
    }

    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final students = widget.workspace.rosterFor(section.id);
        final tags = widget.workspace.tags;

        // Wide windows show students and tags together; narrow windows tab
        // between them.
        if (context.isExpanded) {
          return Scaffold(
            appBar: AppBar(title: Text(section.name)),
            body: Row(
              children: [
                Expanded(child: _studentsList(students, tags, section)),
                const VerticalDivider(width: 1),
                SizedBox(width: 340, child: _tagsList(tags)),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _editStudent(null, section),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add student'),
            ),
          );
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(section.name),
              bottom: const TabBar(
                tabs: [Tab(text: 'Students'), Tab(text: 'Tags')],
              ),
            ),
            body: TabBarView(
              children: [
                _studentsList(students, tags, section),
                _tagsList(tags),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _editStudent(null, section),
              child: const Icon(Icons.person_add_alt),
            ),
          ),
        );
      },
    );
  }

  Widget _studentsList(
    List<Student> students,
    List<StudentTag> tags,
    ClassSection section,
  ) {
    if (students.isEmpty) {
      return const Center(child: Text('No students on this roster yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: students.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final student = students[index];
        final applied = [
          for (final id in student.tagIds) ?widget.workspace.tag(id),
        ];
        return ListTile(
          leading: CircleAvatar(child: Text(student.initials)),
          title: Text(student.fullName),
          subtitle: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(student.gradeLevel.label),
              for (final tag in applied)
                Chip(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                  avatar: CircleAvatar(
                    backgroundColor: Color(tag.colorValue),
                    radius: 6,
                  ),
                  label: Text(tag.label),
                ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editStudent(student, section),
        );
      },
    );
  }

  Widget _tagsList(List<StudentTag> tags) {
    return Column(
      children: [
        ListTile(
          title: Text(
            'Tags',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: const Text('Used when shuffling, and by AI later'),
          trailing: IconButton.filledTonal(
            tooltip: 'New tag',
            onPressed: () => _editTag(null),
            icon: const Icon(Icons.add),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: tags.isEmpty
              ? const Center(child: Text('No tags yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: tags.length,
                  itemBuilder: (context, index) {
                    final tag = tags[index];
                    final count = widget.workspace.students
                        .where((s) => s.hasTag(tag.id))
                        .length;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(tag.colorValue),
                        radius: 12,
                      ),
                      title: Text(tag.label),
                      subtitle: Text(
                        '${tag.category.label} · $count student(s)'
                        '${tag.hint == SeatingHint.none ? '' : '\n${tag.hint.label}'}',
                      ),
                      isThreeLine: tag.hint != SeatingHint.none,
                      trailing: IconButton(
                        tooltip: 'Delete tag',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDeleteTag(tag),
                      ),
                      onTap: () => _editTag(tag),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editStudent(Student? student, ClassSection section) async {
    final result = await showDialog<StudentEditorResult>(
      context: context,
      builder: (context) => StudentEditorDialog(
        tags: widget.workspace.tags,
        student: student,
      ),
    );
    if (result == null) return;

    if (result.delete) {
      widget.workspace.deleteStudent(result.student.id);
      return;
    }

    widget.workspace.upsertStudent(result.student);
    // A newly created student still has to join this class's roster.
    if (student == null) {
      widget.workspace.upsertClass(
        section.copyWith(
          studentIds: [...section.studentIds, result.student.id],
        ),
      );
    }
  }

  Future<void> _editTag(StudentTag? tag) async {
    final result = await showDialog<StudentTag>(
      context: context,
      builder: (context) => TagEditorDialog(tag: tag),
    );
    if (result != null) widget.workspace.upsertTag(result);
  }

  Future<void> _confirmDeleteTag(StudentTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${tag.label}"?'),
        content: const Text(
          'It will be removed from every student who has it. Saved seating '
          'history is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) widget.workspace.deleteTag(tag.id);
  }
}
