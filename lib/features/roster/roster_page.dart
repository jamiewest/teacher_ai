import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import 'roster_membership_dialog.dart';
import 'student_editor_dialog.dart';
import 'tag_editor_dialog.dart';

/// Students and the tags applied to them.
///
/// Tags live beside the roster rather than buried in the seating editor: they
/// are class-wide knowledge the teacher builds up over time, and the seating
/// chart is only one of the things that will read them.
class RosterPage extends StatefulWidget {
  const RosterPage({
    required this.workspace,
    required this.section,
    this.onSelectClass,
    this.onOpenSettings,
    super.key,
  });

  final TeacherWorkspace workspace;
  final ClassSection? section;
  final ValueChanged<String>? onSelectClass;
  final VoidCallback? onOpenSettings;

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage>
    with SingleTickerProviderStateMixin {
  String? _filter;
  String _query = '';
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  )..addListener(_onTabChanged);

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(RosterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section?.id != widget.section?.id) {
      _filter = null;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.workspace,
    builder: (context, _) {
      final workspace = widget.workspace;
      final filter = _filter ?? widget.section?.id ?? 'all';
      final section = workspace.classSection(filter);
      final students =
          (section != null
                  ? workspace.rosterFor(section.id)
                  : workspace.students)
              .where(
                (student) =>
                    (filter != 'unassigned' ||
                        workspace.classesForStudent(student.id).isEmpty) &&
                    student.fullName.toLowerCase().contains(
                      _query.toLowerCase(),
                    ),
              )
              .toList();

      final classDropdown = DropdownButtonFormField<String>(
        key: ValueKey(filter),
        initialValue:
            section?.id ?? (filter == 'unassigned' ? 'unassigned' : 'all'),
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Period / class',
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: 'all', child: Text('All students')),
          const DropdownMenuItem(
            value: 'unassigned',
            child: Text('Unassigned students'),
          ),
          for (final item in workspace.classes)
            DropdownMenuItem(
              value: item.id,
              child: Text(
                workspace.classLabel(item),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => _filter = value);
          if (workspace.classSection(value) != null) {
            widget.onSelectClass?.call(value);
          }
        },
      );

      final searchField = TextField(
        decoration: const InputDecoration(
          labelText: 'Search students',
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _query = value),
      );

      final roster = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (context.isCompact) ...[
                  classDropdown,
                  const SizedBox(height: 10),
                  searchField,
                ] else
                  Row(
                    children: [
                      Expanded(child: classDropdown),
                      const SizedBox(width: 12),
                      Expanded(child: searchField),
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${students.length} students'),
                    if (section != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            manageRoster(context, workspace, section),
                        icon: const Icon(Icons.playlist_add_check, size: 18),
                        label: const Text('Manage students'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _studentsList(students, section)),
        ],
      );

      if (context.isExpanded) {
        return Scaffold(
          appBar: AppBar(title: const Text('Roster')),
          body: Row(
            children: [
              Expanded(child: roster),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 340,
                child: _tagsList(workspace.tags, showInlineAdd: true),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editStudent(null, section),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add student'),
          ),
        );
      }

      final onTagsTab = _tabController.index == 1;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Roster'),
          actions: [
            if (context.isCompact && widget.onOpenSettings != null)
              IconButton(
                tooltip: 'Settings',
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Students'),
              Tab(text: 'Tags'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [roster, _tagsList(workspace.tags, showInlineAdd: false)],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: onTagsTab ? 'New tag' : 'Add student',
          onPressed: onTagsTab
              ? () => _editTag(null)
              : () => _editStudent(null, section),
          child: Icon(onTagsTab ? Icons.add : Icons.person_add_alt),
        ),
      );
    },
  );

  Widget _studentsList(List<Student> students, ClassSection? section) {
    if (students.isEmpty) {
      return const Center(
        child: Text(
          'No students found. Add a student or choose another roster.',
        ),
      );
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
              Text(
                widget.workspace.classesForStudent(student.id).isEmpty
                    ? 'No period assigned'
                    : widget.workspace
                          .classesForStudent(student.id)
                          .map(widget.workspace.classLabel)
                          .join(' · '),
              ),
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

  Widget _tagsList(List<StudentTag> tags, {required bool showInlineAdd}) {
    return Column(
      children: [
        ListTile(
          title: Text('Tags', style: Theme.of(context).textTheme.titleSmall),
          subtitle: const Text('Used when shuffling, and by AI later'),
          trailing: showInlineAdd
              ? IconButton.filledTonal(
                  tooltip: 'New tag',
                  onPressed: () => _editTag(null),
                  icon: const Icon(Icons.add),
                )
              : null,
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

  Future<void> _editStudent(Student? student, ClassSection? section) async {
    final result = await showDialog<StudentEditorResult>(
      context: context,
      builder: (context) => StudentEditorDialog(
        tags: widget.workspace.tags,
        student: student,
        classLabels: {
          for (final item in widget.workspace.classes)
            item.id: widget.workspace.classLabel(item),
        },
        initialClassIds: student == null
            ? {if (section != null) section.id}
            : widget.workspace
                  .classesForStudent(student.id)
                  .map((item) => item.id)
                  .toSet(),
      ),
    );
    if (result == null) return;

    if (result.delete) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${result.student.fullName}?'),
          content: const Text(
            'This deletes the student from every class. To remove only a period assignment, uncheck that class in the student editor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete student'),
            ),
          ],
        ),
      );
      if (confirmed ?? false) widget.workspace.deleteStudent(result.student.id);
      return;
    }
    widget.workspace.saveStudent(result.student, classIds: result.classIds);
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
