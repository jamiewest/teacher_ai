import 'package:flutter/material.dart';

import '../../../data/teacher_workspace.dart';
import '../../../domain/models/models.dart';
import '../../../domain/ops/layout_ops.dart';
import '../seating_editor_controller.dart';

/// Properties of whatever is selected: one desk, several desks, or the room
/// itself when nothing is selected.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({
    required this.editor,
    required this.workspace,
    this.onAssignSeat,
    super.key,
  });

  final SeatingEditorController editor;
  final TeacherWorkspace workspace;
  final void Function(Desk desk)? onAssignSeat;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final sole = editor.soleSelection;
        final count = editor.selection.length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (count == 0)
              _RoomSection(editor: editor)
            else if (sole != null)
              _DeskSection(
                editor: editor,
                workspace: workspace,
                desk: sole,
                onAssignSeat: onAssignSeat,
              )
            else
              _MultiSection(editor: editor, count: count),
            const SizedBox(height: 20),
            _GroupsSection(editor: editor),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.9,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Room dimensions and grid, shown when nothing is selected.
class _RoomSection extends StatelessWidget {
  const _RoomSection({required this.editor});

  final SeatingEditorController editor;

  @override
  Widget build(BuildContext context) {
    final layout = editor.layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Room'),
        Text(
          '${layout.seatCount} seats · ${layout.groups.length} groups',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _MeasureSlider(
          label: 'Room width',
          value: layout.roomWidth,
          min: 400,
          max: 1600,
          onChanged: (v) => editor.setRoomSize(width: v),
          onStart: editor.beginInteraction,
          onEnd: editor.endInteraction,
        ),
        _MeasureSlider(
          label: 'Room depth',
          value: layout.roomHeight,
          min: 400,
          max: 1600,
          onChanged: (v) => editor.setRoomSize(height: v),
          onStart: editor.beginInteraction,
          onEnd: editor.endInteraction,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Grid'),
            const Spacer(),
            DropdownButton<double>(
              value: _gridOptions.contains(layout.gridSize)
                  ? layout.gridSize
                  : _gridOptions.first,
              isDense: true,
              items: [
                for (final size in _gridOptions)
                  DropdownMenuItem(
                    value: size,
                    child: Text(size == 0 ? 'Off' : '${size.round()} cm'),
                  ),
              ],
              onChanged: (v) => v == null ? null : editor.setGridSize(v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: select several desks to line them up or space them evenly.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  static const _gridOptions = <double>[15, 5, 10, 25, 30, 50, 0];
}

/// Everything about one desk.
class _DeskSection extends StatelessWidget {
  const _DeskSection({
    required this.editor,
    required this.workspace,
    required this.desk,
    this.onAssignSeat,
  });

  final SeatingEditorController editor;
  final TeacherWorkspace workspace;
  final Desk desk;
  final void Function(Desk desk)? onAssignSeat;

  @override
  Widget build(BuildContext context) {
    final student = editor.studentAt(desk.id);
    final group = editor.layout.groupForDesk(desk.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          desk.kind.label,
          trailing: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: desk.locked ? 'Unlock position' : 'Lock position',
            icon: Icon(desk.locked ? Icons.lock : Icons.lock_open, size: 18),
            onPressed: () => editor.toggleDeskLocked(desk.id),
          ),
        ),
        if (desk.isSeat) ...[
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(child: Text(student?.initials ?? '–')),
              title: Text(student?.fullName ?? 'Empty seat'),
              subtitle: Text(
                student == null
                    ? 'Tap to seat a student'
                    : student.gradeLevel.label,
              ),
              trailing: student == null
                  ? const Icon(Icons.person_add_alt)
                  : IconButton(
                      tooltip: 'Clear this seat',
                      icon: const Icon(Icons.person_remove_alt_1_outlined),
                      onPressed: () => editor.clearSeat(desk.id),
                    ),
              onTap: () => onAssignSeat?.call(desk),
            ),
          ),
          if (student != null && student.tagIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in student.tagIds)
                    if (workspace.tag(id) case final tag?)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(
                          backgroundColor: Color(tag.colorValue),
                          radius: 6,
                        ),
                        label: Text(tag.label),
                      ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Keep through shuffles'),
            subtitle: const Text('Pinned seats are left alone'),
            value: editor.isPinned(desk.id),
            onChanged: (_) => editor.togglePinned(desk.id),
          ),
          const Divider(height: 24),
        ],
        const _SectionTitle('Direction'),
        _RotationControl(editor: editor, desk: desk),
        const SizedBox(height: 16),
        const _SectionTitle('Size and shape'),
        _MeasureSlider(
          label: 'Width',
          value: desk.width,
          min: 30,
          max: 200,
          onChanged: (v) => editor.resizeDesk(desk.id, width: v),
          onStart: editor.beginInteraction,
          onEnd: editor.endInteraction,
        ),
        _MeasureSlider(
          label: 'Depth',
          value: desk.height,
          min: 30,
          max: 200,
          onChanged: (v) => editor.resizeDesk(desk.id, height: v),
          onStart: editor.beginInteraction,
          onEnd: editor.endInteraction,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Shape'),
            const Spacer(),
            DropdownButton<DeskShape>(
              value: desk.shape,
              isDense: true,
              items: [
                for (final shape in DeskShape.values)
                  DropdownMenuItem(value: shape, child: Text(shape.label)),
              ],
              onChanged: (s) =>
                  s == null ? null : editor.setDeskShape(desk.id, s),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('label-${desk.id}'),
          initialValue: desk.label,
          decoration: const InputDecoration(
            labelText: 'Label',
            helperText: 'Shown when no student is seated here',
            isDense: true,
          ),
          onFieldSubmitted: (value) => editor.setDeskLabel(desk.id, value),
        ),
        const Divider(height: 24),
        if (group != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Color(group.colorValue),
              radius: 10,
            ),
            title: Text(group.name),
            subtitle: Text('${group.seatCount} seats'),
            trailing: IconButton(
              tooltip: 'Select the whole group',
              icon: const Icon(Icons.select_all),
              onPressed: () => editor.selectGroupOf(desk.id),
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: editor.duplicateSelection,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Duplicate'),
            ),
            OutlinedButton.icon(
              onPressed: editor.deleteSelection,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rotation slider plus the fixed-angle shortcuts.
class _RotationControl extends StatelessWidget {
  const _RotationControl({required this.editor, required this.desk});

  final SeatingEditorController editor;
  final Desk desk;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('${desk.rotation.round()}°'),
            Expanded(
              child: Slider(
                value: desk.rotation.clamp(0, 360),
                max: 360,
                // Free while dragging; the snap setting applies to the handle
                // on the canvas and to the preset buttons below.
                onChangeStart: (_) => editor.beginInteraction(),
                onChanged: (v) =>
                    editor.setDeskRotation(desk.id, v, snap: false),
                onChangeEnd: (_) => editor.endInteraction(),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final angle in const <double>[0, 90, 180, 270])
              ChoiceChip(
                label: Text('${angle.round()}°'),
                selected: desk.rotation.round() == angle.round(),
                onSelected: (_) =>
                    editor.setDeskRotation(desk.id, angle, snap: false),
              ),
            ActionChip(
              avatar: const Icon(Icons.rotate_left, size: 16),
              label: const Text('-15'),
              onPressed: () => editor.setDeskRotation(
                desk.id,
                desk.rotation - 15,
                snap: false,
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.rotate_right, size: 16),
              label: const Text('+15'),
              onPressed: () => editor.setDeskRotation(
                desk.id,
                desk.rotation + 15,
                snap: false,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Actions that only make sense on a multi-desk selection.
class _MultiSection extends StatelessWidget {
  const _MultiSection({required this.editor, required this.count});

  final SeatingEditorController editor;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('$count desks selected'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => editor.groupSelection(),
              icon: const Icon(Icons.workspaces_outline, size: 18),
              label: const Text('Make a group'),
            ),
            OutlinedButton.icon(
              onPressed: editor.ungroupSelection,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Ungroup'),
            ),
            OutlinedButton.icon(
              onPressed: editor.podSelection,
              icon: const Icon(Icons.group_work_outlined, size: 18),
              label: const Text('Team pod'),
            ),
            OutlinedButton.icon(
              onPressed: () => editor.clusterSelection(),
              icon: const Icon(Icons.join_inner, size: 18),
              label: const Text('Pull together'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SectionTitle('Line up'),
        Wrap(
          spacing: 4,
          children: [
            for (final edge in AlignEdge.values)
              IconButton.outlined(
                tooltip: edge.label,
                onPressed: () => editor.alignSelection(edge),
                icon: Icon(_alignIconFor(edge)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const _SectionTitle('Space evenly'),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: count >= 3
                  ? () => editor.distributeSelection(SpreadAxis.horizontal)
                  : null,
              icon: const Icon(Icons.horizontal_distribute, size: 18),
              label: const Text('Across'),
            ),
            OutlinedButton.icon(
              onPressed: count >= 3
                  ? () => editor.distributeSelection(SpreadAxis.vertical)
                  : null,
              icon: const Icon(Icons.vertical_distribute, size: 18),
              label: const Text('Down'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SectionTitle('Turn all of them'),
        Wrap(
          spacing: 6,
          children: [
            for (final angle in const <double>[0, 90, 180, 270])
              ActionChip(
                label: Text('${angle.round()}°'),
                onPressed: () => editor.setSelectionRotation(angle),
              ),
            ActionChip(
              avatar: const Icon(Icons.rotate_90_degrees_ccw, size: 16),
              label: const Text('Rotate group'),
              onPressed: () => editor.rotateSelectionBy(15),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: editor.duplicateSelection,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Duplicate'),
            ),
            OutlinedButton.icon(
              onPressed: editor.deleteSelection,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}

IconData _alignIconFor(AlignEdge edge) => switch (edge) {
  AlignEdge.left => Icons.align_horizontal_left,
  AlignEdge.horizontalCenter => Icons.align_horizontal_center,
  AlignEdge.right => Icons.align_horizontal_right,
  AlignEdge.top => Icons.align_vertical_top,
  AlignEdge.verticalCenter => Icons.align_vertical_center,
  AlignEdge.bottom => Icons.align_vertical_bottom,
};

/// Every group in the layout, with rename and recolor.
class _GroupsSection extends StatelessWidget {
  const _GroupsSection({required this.editor});

  final SeatingEditorController editor;

  @override
  Widget build(BuildContext context) {
    final groups = editor.layout.groups;
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        _SectionTitle('Groups (${groups.length})'),
        for (final group in groups)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: PopupMenuButton<int>(
              tooltip: 'Group colour',
              icon: CircleAvatar(
                backgroundColor: Color(group.colorValue),
                radius: 10,
              ),
              itemBuilder: (context) => [
                for (final color in kGroupColors)
                  PopupMenuItem(
                    value: color,
                    child: Row(
                      children: [
                        CircleAvatar(backgroundColor: Color(color), radius: 9),
                        const SizedBox(width: 10),
                        Text(
                          color == group.colorValue ? 'Current' : 'Use this',
                        ),
                      ],
                    ),
                  ),
              ],
              onSelected: (color) => editor.setGroupColor(group.id, color),
            ),
            title: Text(group.name),
            subtitle: Text(
              '${group.seatCount} seats'
              '${group.isKaganTeam ? ' · Kagan team' : ''}',
            ),
            trailing: IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _rename(context, group),
            ),
            onTap: () => editor.addToSelection(group.deskIds),
          ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, DeskGroup group) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      editor.renameGroup(group.id, name.trim());
    }
  }
}

/// A labelled slider that reads out centimeters.
class _MeasureSlider extends StatelessWidget {
  const _MeasureSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onStart,
    this.onEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 74, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChangeStart: onStart == null ? null : (_) => onStart!(),
            onChanged: onChanged,
            onChangeEnd: onEnd == null ? null : (_) => onEnd!(),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${value.round()}cm',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
