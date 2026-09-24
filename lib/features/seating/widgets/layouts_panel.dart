import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/ops/layout_presets.dart';

/// Starting points offered when creating a layout.
enum LayoutPreset {
  blank('Empty room', Icons.crop_square, 'Add your own desks and furniture'),
  rows('Rows', Icons.view_stream, '25 seats · Independent work'),
  pods('Kagan pods', Icons.group_work, '24 seats · Six teams of four'),
  horseshoe(
    'Horseshoe',
    Icons.rounded_corner,
    '14 seats · Whole-class discussion',
  );

  const LayoutPreset(this.label, this.icon, this.description);
  final String label;
  final IconData icon;
  final String description;
}

/// Saved layouts for a class, with the actions that manage them.
class LayoutsPanel extends StatelessWidget {
  const LayoutsPanel({
    required this.layouts,
    required this.activeLayoutId,
    required this.onSelect,
    required this.onCreate,
    required this.onDuplicate,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final List<RoomLayout> layouts;
  final String? activeLayoutId;
  final ValueChanged<RoomLayout> onSelect;
  final ValueChanged<LayoutPreset> onCreate;
  final ValueChanged<RoomLayout> onDuplicate;
  final ValueChanged<RoomLayout> onRename;
  final ValueChanged<RoomLayout> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Saved layouts', style: theme.textTheme.titleSmall),
        ),
        for (final layout in layouts)
          ListTile(
            selected: layout.id == activeLayoutId,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: _LayoutPreview(layout: layout),
            title: Text(layout.name),
            subtitle: Text(
              '${layout.seatCount} seats'
              '${layout.groups.isEmpty ? '' : ' · ${layout.groups.length} groups'}'
              ' · ${_relative(layout.updatedAt)}',
            ),
            trailing: MenuAnchor(
              builder: (context, controller, _) => IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: () => onRename(layout),
                  child: const Text('Rename'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.copy_all_outlined),
                  onPressed: () => onDuplicate(layout),
                  child: const Text('Duplicate'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.delete_outline),
                  onPressed: layouts.length > 1 ? () => onDelete(layout) : null,
                  child: const Text('Delete'),
                ),
              ],
            ),
            onTap: () => onSelect(layout),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('New layout', style: theme.textTheme.titleSmall),
        ),
        for (final preset in LayoutPreset.values)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: _LayoutPreview(
              layout: buildPresetLayout(
                preset: preset.name,
                name: preset.label,
              ),
            ),
            title: Text(preset.label),
            subtitle: Text(preset.description),
            onTap: () => onCreate(preset),
          ),
      ],
    );
  }
}

/// Past seating arrangements for a layout, newest first.
///
/// History is append-only, so this is a record of what was actually used —
/// which is exactly the signal a future AI needs to learn a teacher's habits.
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({
    required this.assignments,
    required this.onRestore,
    required this.onDelete,
    this.onRename,
    super.key,
  });

  final List<SeatingAssignment> assignments;
  final ValueChanged<SeatingAssignment> onRestore;
  final ValueChanged<SeatingAssignment> onDelete;
  final ValueChanged<SeatingAssignment>? onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (assignments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No saved seating yet.\nArrange the class, then save it to build '
            'up a history.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: assignments.length,
      itemBuilder: (context, index) {
        final assignment = assignments[index];
        return ListTile(
          leading: Icon(_iconFor(assignment.source)),
          title: Text(assignment.displayName()),
          subtitle: Text(
            '${assignment.seatedCount} seated · '
            '${assignment.source.label}'
            '${assignment.seed == null ? '' : ' · seed ${assignment.seed}'}',
          ),
          trailing: MenuAnchor(
            builder: (context, controller, _) => IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.restore),
                onPressed: () => onRestore(assignment),
                child: const Text('Put this back'),
              ),
              if (onRename != null)
                MenuItemButton(
                  leadingIcon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: () => onRename!(assignment),
                  child: const Text('Rename'),
                ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(assignment),
                child: const Text('Delete'),
              ),
            ],
          ),
          onTap: () => onRestore(assignment),
        );
      },
    );
  }

  IconData _iconFor(AssignmentSource source) => switch (source) {
    AssignmentSource.manual => Icons.edit_outlined,
    AssignmentSource.shuffle => Icons.shuffle,
    AssignmentSource.imported => Icons.download_outlined,
    AssignmentSource.ai => Icons.auto_awesome_outlined,
  };
}

/// Coarse "how long ago" text; precise timestamps are not useful here.
String _relative(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${when.month}/${when.day}';
}

/// Small previews make saved rooms and starting points recognizable.
class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview({required this.layout});
  final RoomLayout layout;
  @override
  Widget build(BuildContext context) => Container(
    width: 76,
    height: 56,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(6),
    ),
    child: CustomPaint(
      painter: _LayoutPreviewPainter(
        layout,
        Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _LayoutPreviewPainter extends CustomPainter {
  _LayoutPreviewPainter(this.layout, this.color);
  final RoomLayout layout;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / layout.roomWidth,
      size.height / layout.roomHeight,
    );
    canvas.save();
    canvas.translate(
      (size.width - layout.roomWidth * scale) / 2,
      (size.height - layout.roomHeight * scale) / 2,
    );
    canvas.scale(scale);
    for (final desk in layout.desks) {
      canvas.save();
      canvas.translate(desk.x, desk.y);
      canvas.rotate(desk.rotation * math.pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: desk.width,
            height: desk.height,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = desk.isSeat ? color : color.withValues(alpha: 0.3),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayoutPreviewPainter old) =>
      old.layout != layout || old.color != color;
}
