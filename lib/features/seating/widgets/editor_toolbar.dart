import 'package:flutter/material.dart';

import '../../../domain/ops/layout_ops.dart';
import '../../../domain/models/models.dart';
import '../room_view_controller.dart';
import '../seating_editor_controller.dart';
import '../seating_editor_state.dart';

/// The band of controls above the classroom.
///
/// Which controls stay visible is the main responsive decision in the editor:
/// on a desktop the arrange actions are one click away, while on a phone they
/// collapse into a menu so the canvas keeps the width it needs.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    required this.editor,
    required this.view,
    required this.onAutoSeat,
    required this.onShuffle,
    this.onOpenPanel,
    super.key,
  });
  final SeatingEditorController editor;
  final RoomViewController view;
  final VoidCallback onAutoSeat;
  final VoidCallback onShuffle;
  final VoidCallback? onOpenPanel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) => Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onOpenPanel != null)
                TextButton.icon(
                  onPressed: onOpenPanel,
                  icon: Icon(
                    editor.mode == EditorMode.seating
                        ? Icons.people_outline
                        : Icons.tune,
                    size: 18,
                  ),
                  label: Text(
                    editor.mode == EditorMode.seating
                        ? 'Students'
                        : 'Properties',
                  ),
                ),
              if (editor.mode == EditorMode.seating) ...[
                FilledButton.tonalIcon(
                  onPressed:
                      editor.unseatedStudents.isEmpty ||
                          editor.layout.seatCount == 0
                      ? null
                      : onAutoSeat,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Seat remaining'),
                ),
                TextButton.icon(
                  onPressed: editor.seating.isEmpty ? null : onShuffle,
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: const Text('Shuffle'),
                ),
              ] else ...[
                SegmentedButton<EditorTool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: EditorTool.select,
                      icon: Icon(Icons.near_me_outlined),
                      tooltip: 'Select and move desks',
                    ),
                    ButtonSegment(
                      value: EditorTool.pan,
                      icon: Icon(Icons.pan_tool_outlined),
                      tooltip: 'Pan around the room',
                    ),
                  ],
                  selected: {
                    editor.tool == EditorTool.addDesk
                        ? EditorTool.select
                        : editor.tool,
                  },
                  onSelectionChanged: (s) => editor.setTool(s.first),
                ),
                MenuAnchor(
                  builder: (context, menu, _) => FilledButton.tonalIcon(
                    onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add furniture'),
                  ),
                  menuChildren: [
                    for (final kind in DeskKind.values)
                      MenuItemButton(
                        onPressed: () {
                          editor.addDesk(
                            view.toRoom(
                              Offset(
                                view.viewport.width / 2,
                                view.viewport.height / 2,
                              ),
                            ),
                            kind: kind,
                          );
                          editor.setTool(EditorTool.select);
                        },
                        child: Text(kind.label),
                      ),
                  ],
                ),
                if (editor.selection.length >= 2)
                  _ArrangeMenuButton(
                    editor: editor,
                    count: editor.selection.length,
                  ),
                _ViewMenuButton(editor: editor),
              ],
              const _Sep(),
              IconButton(
                tooltip: 'Undo',
                onPressed: editor.canUndo ? editor.undo : null,
                icon: const Icon(Icons.undo, size: 20),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: editor.canRedo ? editor.redo : null,
                icon: const Icon(Icons.redo, size: 20),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

IconData _alignIcon(AlignEdge edge) => switch (edge) {
  AlignEdge.left => Icons.align_horizontal_left,
  AlignEdge.horizontalCenter => Icons.align_horizontal_center,
  AlignEdge.right => Icons.align_horizontal_right,
  AlignEdge.top => Icons.align_vertical_top,
  AlignEdge.verticalCenter => Icons.align_vertical_center,
  AlignEdge.bottom => Icons.align_vertical_bottom,
};

/// The same arrange actions, folded into a menu for narrow windows.
class _ArrangeMenuButton extends StatelessWidget {
  const _ArrangeMenuButton({required this.editor, required this.count});

  final SeatingEditorController editor;
  final int count;

  @override
  Widget build(BuildContext context) {
    final canAlign = count >= 2;
    final canDistribute = count >= 3;
    return MenuAnchor(
      builder: (context, controller, _) => TextButton.icon(
        onPressed: canAlign
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: const Icon(Icons.dashboard_customize_outlined),
        label: const Text('Arrange'),
      ),
      menuChildren: [
        for (final edge in AlignEdge.values)
          MenuItemButton(
            leadingIcon: Icon(_alignIcon(edge)),
            onPressed: canAlign ? () => editor.alignSelection(edge) : null,
            child: Text('Align ${edge.label.toLowerCase()}'),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.horizontal_distribute),
          onPressed: canDistribute
              ? () => editor.distributeSelection(SpreadAxis.horizontal)
              : null,
          child: const Text('Space evenly across'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.vertical_distribute),
          onPressed: canDistribute
              ? () => editor.distributeSelection(SpreadAxis.vertical)
              : null,
          child: const Text('Space evenly down'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.join_inner),
          onPressed: canAlign ? () => editor.clusterSelection() : null,
          child: const Text('Pull together'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.group_work_outlined),
          onPressed: canAlign ? editor.podSelection : null,
          child: const Text('Arrange as team pod'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.workspaces_outline),
          onPressed: canAlign ? () => editor.groupSelection() : null,
          child: const Text('Group these desks'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.workspaces_outlined),
          onPressed: count > 0 ? editor.ungroupSelection : null,
          child: const Text('Ungroup'),
        ),
      ],
    );
  }
}

/// Grid and rotation settings for narrow windows.
class _ViewMenuButton extends StatelessWidget {
  const _ViewMenuButton({required this.editor});

  final SeatingEditorController editor;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        tooltip: 'Grid and rotation',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.tune),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(editor.snapToGrid ? Icons.grid_on : Icons.grid_off),
          onPressed: () => editor.setSnapToGrid(!editor.snapToGrid),
          child: Text(
            editor.snapToGrid ? 'Snap to grid: on' : 'Snap to grid: off',
          ),
        ),
        MenuItemButton(
          leadingIcon: Icon(editor.showGrid ? Icons.blur_on : Icons.blur_off),
          onPressed: () => editor.setShowGrid(!editor.showGrid),
          child: Text(editor.showGrid ? 'Hide grid' : 'Show grid'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            editor.showTags ? Icons.label : Icons.label_off_outlined,
          ),
          onPressed: () => editor.setShowTags(!editor.showTags),
          child: Text(editor.showTags ? 'Hide tag dots' : 'Show tag dots'),
        ),
        const Divider(height: 8),
        for (final snap in RotationSnap.values)
          MenuItemButton(
            leadingIcon: Icon(
              editor.rotationSnap == snap
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            onPressed: () => editor.setRotationSnap(snap),
            child: Text('Rotate in ${snap.label} steps'),
          ),
      ],
    );
  }
}

class CanvasZoomControls extends StatelessWidget {
  const CanvasZoomControls({
    required this.editor,
    required this.view,
    super.key,
  });

  final SeatingEditorController editor;
  final RoomViewController view;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: view,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Zoom out',
          onPressed: () => view.zoomAtCenter(1 / 1.2),
          icon: const Icon(Icons.zoom_out),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${view.zoomPercent}%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        IconButton(
          tooltip: 'Zoom in',
          onPressed: () => view.zoomAtCenter(1.2),
          icon: const Icon(Icons.zoom_in),
        ),
        IconButton(
          tooltip: 'Fit the room to the window',
          onPressed: () => view.fit(editor.layout.roomSize),
          icon: const Icon(Icons.fit_screen_outlined),
        ),
      ],
    ),
  );
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4),
    child: SizedBox(height: 24, child: VerticalDivider(width: 1)),
  );
}
