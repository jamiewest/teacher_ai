import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../seating_editor_controller.dart';

/// A searchable picker with an explicit description of what each choice does.
class SeatPicker extends StatefulWidget {
  const SeatPicker({required this.editor, required this.desk, super.key});
  final SeatingEditorController editor;
  final Desk desk;

  @override
  State<SeatPicker> createState() => _SeatPickerState();
}

class _SeatPickerState extends State<SeatPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.editor,
    builder: (context, _) {
      final editor = widget.editor;
      final current = editor.studentAt(widget.desk.id);
      final students =
          editor.roster
              .where(
                (s) =>
                    s.id != current?.id &&
                    s.fullName.toLowerCase().contains(
                      _query.trim().toLowerCase(),
                    ),
              )
              .toList()
            ..sort((a, b) {
              final seatedA = editor.snapshot.deskForStudent(a.id) != null;
              final seatedB = editor.snapshot.deskForStudent(b.id) != null;
              return seatedA == seatedB
                  ? a.fullName.compareTo(b.fullName)
                  : seatedA
                  ? 1
                  : -1;
            });
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: Text(current?.fullName ?? 'Choose a student'),
                subtitle: Text(
                  editor.layout.groupForDesk(widget.desk.id)?.name ??
                      'Student seat',
                ),
                trailing: IconButton(
                  tooltip: 'Close seat picker',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (current != null) ...[
                SwitchListTile(
                  title: const Text('Keep this seat during shuffles'),
                  secondary: const Icon(Icons.push_pin_outlined),
                  value: editor.isPinned(widget.desk.id),
                  onChanged: (_) => editor.togglePinned(widget.desk.id),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    onPressed: () {
                      editor.clearSeat(widget.desk.id);
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.person_remove_outlined),
                    label: const Text('Remove from seat'),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search students',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: students.isEmpty
                    ? const Center(child: Text('No students found.'))
                    : ListView.builder(
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final hasSeat =
                              editor.snapshot.deskForStudent(student.id) !=
                              null;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(student.initials),
                            ),
                            title: Text(student.fullName),
                            subtitle: Text(
                              hasSeat
                                  ? current == null
                                        ? 'Move to this seat'
                                        : 'Swap with ${current.firstName}'
                                  : current == null
                                  ? 'Needs a seat'
                                  : '${current.firstName} will become unseated',
                            ),
                            trailing: Icon(
                              hasSeat ? Icons.swap_horiz : Icons.add,
                              size: 20,
                            ),
                            onTap: () {
                              editor.placeStudent(widget.desk.id, student.id);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
