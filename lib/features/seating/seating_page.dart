import 'package:flutter/material.dart';

import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import '../../domain/ops/layout_presets.dart';
import 'room_view_controller.dart';
import 'seating_editor_controller.dart';
import 'seating_editor_state.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/layouts_panel.dart';
import 'widgets/room_canvas.dart';
import 'widgets/roster_panel.dart';
import 'widgets/seat_picker.dart';

/// The seating chart screen.
///
/// The three pieces — roster, room, inspector — are the same everywhere; what
/// changes with window size is how many of them are on screen at once.
class SeatingPage extends StatefulWidget {
  const SeatingPage({
    required this.workspace,
    required this.section,
    this.onPickClass,
    super.key,
  });

  final TeacherWorkspace workspace;
  final ClassSection? section;
  final VoidCallback? onPickClass;

  @override
  State<SeatingPage> createState() => _SeatingPageState();
}

class _SeatingPageState extends State<SeatingPage> {
  final _normalView = RoomViewController();
  final _expandedView = RoomViewController();
  bool _canvasExpanded = false;

  RoomViewController get _view => _canvasExpanded ? _expandedView : _normalView;
  SeatingEditorController? _editor;
  String? _editingLayoutId;
  final _editors = <String, SeatingEditorController>{};

  @override
  void initState() {
    super.initState();
    _syncEditor();
  }

  @override
  void didUpdateWidget(SeatingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section?.id != widget.section?.id) _syncEditor();
  }

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _normalView.dispose();
    _expandedView.dispose();
    super.dispose();
  }

  /// Rebuilds the editor when the class or the active layout changes.
  ///
  /// Each layout keeps its draft and undo history for this app session.
  void _syncEditor({String? layoutId}) {
    final stale = widget.section;
    if (stale == null) {
      _retireEditor();
      return;
    }
    // Re-read the section: `widget.section` was captured at build time and can
    // still point at a layout that was just deleted.
    final section = widget.workspace.classSection(stale.id) ?? stale;

    final layouts = widget.workspace.layoutsFor(section.id);
    final requested = layoutId ?? section.activeLayoutId;
    // Fall back to any surviving layout when the requested one is gone, so
    // deleting the active layout cannot strand the editor on it.
    final layout =
        (requested == null ? null : widget.workspace.layout(requested)) ??
        layouts.firstOrNull;

    if (layout == null) {
      _retireEditor();
      _editingLayoutId = null;
      return;
    }
    if (layout.id == _editingLayoutId && _editor != null) return;

    _editingLayoutId = layout.id;
    _editor = _editors.putIfAbsent(
      layout.id,
      () => SeatingEditorController(
        workspace: widget.workspace,
        layout: layout,
        classSectionId: section.id,
        // Pick up where the class left off, if anything was ever saved.
        seating: Map<String, String>.from(
          widget.workspace.latestAssignment(layout.id)?.seatToStudent ??
              const <String, String>{},
        ),
        pinnedSeats:
            widget.workspace.latestAssignment(layout.id)?.lockedDeskIds ?? {},
      ),
    );
    _normalView.fit(layout.roomSize);
    _expandedView.fit(layout.roomSize);
  }

  void _toggleCanvas() {
    if (!_canvasExpanded) _expandedView.fit(_editor!.layout.roomSize);
    setState(() => _canvasExpanded = !_canvasExpanded);
  }

  /// Cached editors are disposed together when the page closes.
  void _retireEditor() {
    _editor = null;
  }

  @override
  Widget build(BuildContext context) {
    // The layout being edited can be deleted from elsewhere in the app, so
    // confirm it still exists before drawing it.
    final editingId = _editingLayoutId;
    if (editingId != null && widget.workspace.layout(editingId) == null) {
      _syncEditor();
    }

    final section = widget.section;
    final editor = _editor;

    if (section == null) {
      return const _EmptyState(
        icon: Icons.class_outlined,
        title: 'No classes yet',
        message: 'Add a class to start building a seating chart.',
      );
    }
    if (editor == null) {
      return _EmptyState(
        icon: Icons.grid_view_outlined,
        title: 'No layout yet',
        message: 'Create a layout for ${section.name} to get started.',
        action: FilledButton.icon(
          onPressed: () => _createLayout(LayoutPreset.rows),
          icon: const Icon(Icons.add),
          label: const Text('Create a layout'),
        ),
      );
    }

    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          final dockPanel = !_canvasExpanded && constraints.maxWidth >= 980;
          final designing = editor.mode == EditorMode.design;
          final unseated = editor.unseatedStudents.length;
          final seated = editor.roster.length - unseated;
          final shortage = editor.roster.length - editor.layout.seatCount;
          return Scaffold(
            appBar: _canvasExpanded
                ? null
                : AppBar(
                    toolbarHeight: 64,
                    titleSpacing: narrow ? 16 : 24,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seating chart',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        InkWell(
                          onTap: widget.workspace.classes.length > 1
                              ? widget.onPickClass
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.workspace.classLabel(section),
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              if (widget.workspace.classes.length > 1)
                                const Icon(Icons.arrow_drop_down, size: 18),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      if (!narrow)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Text(
                            editor.hasUnsavedSeating
                                ? 'Unsaved seating'
                                : 'Seating up to date',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: () => _saveAssignment(editor),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: Text(narrow ? 'Save' : 'Save chart'),
                      ),
                      _moreMenu(editor),
                      const SizedBox(width: 8),
                    ],
                  ),
            body: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    narrow ? 12 : 24,
                    4,
                    narrow ? 12 : 24,
                    8,
                  ),
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final modePicker = SegmentedButton<EditorMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: EditorMode.seating,
                            icon: Icon(Icons.event_seat_outlined),
                            label: Text('Seat students'),
                          ),
                          ButtonSegment(
                            value: EditorMode.design,
                            icon: Icon(Icons.edit_outlined),
                            label: Text('Design room'),
                          ),
                        ],
                        selected: {editor.mode},
                        onSelectionChanged: (values) =>
                            editor.setMode(values.first),
                      );
                      final layouts = TextButton.icon(
                        onPressed: () => _openPanelSheet(editor, initialTab: 1),
                        icon: const Icon(Icons.layers_outlined, size: 18),
                        label: Text(
                          editor.layout.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                      if (bounds.maxWidth < 600) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            modePicker,
                            Align(
                              alignment: Alignment.centerLeft,
                              child: layouts,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          modePicker,
                          const Spacer(),
                          Flexible(child: layouts),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                EditorToolbar(
                  editor: editor,
                  view: _view,
                  onOpenPanel: dockPanel
                      ? null
                      : () => _openPanelSheet(
                          editor,
                          initialTab: designing ? 3 : 0,
                        ),
                  onAutoSeat: () => _autoSeat(editor),
                  onShuffle: () => _shuffle(editor),
                  onSave: _canvasExpanded
                      ? () => _saveAssignment(editor)
                      : null,
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (dockPanel) ...[
                        SizedBox(
                          width: 288,
                          child: designing
                              ? InspectorPanel(
                                  editor: editor,
                                  workspace: widget.workspace,
                                  onAssignSeat: (desk) =>
                                      _openAssignSheet(editor, desk),
                                )
                              : RosterPanel(
                                  editor: editor,
                                  workspace: widget.workspace,
                                ),
                        ),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        child: ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  12,
                                  0,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      designing
                                          ? Icons.open_with
                                          : Icons.touch_app_outlined,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        editor.pendingStudent != null
                                            ? 'Choose a seat for ${editor.pendingStudent!.fullName}'
                                            : designing
                                            ? 'Drag desks or group outlines to arrange your room. Click to edit.'
                                            : narrow
                                            ? 'Tap a seat to assign. Use + to zoom in.'
                                            : 'Tap a seat to assign or swap a student.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                    if (editor.pendingStudent != null)
                                      IconButton(
                                        tooltip: 'Cancel student placement',
                                        onPressed: () =>
                                            editor.pickStudent(null),
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: _toggleCanvas,
                                      icon: Icon(
                                        _canvasExpanded
                                            ? Icons.fullscreen_exit
                                            : Icons.fullscreen,
                                        size: 20,
                                      ),
                                      label: Text(
                                        _canvasExpanded
                                            ? 'Restore view'
                                            : 'Expand view',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ClipRect(
                                  child: RoomCanvas(
                                    controller: editor,
                                    view: _view,
                                    workspace: widget.workspace,
                                    onSeatTapped: (desk) =>
                                        _openAssignSheet(editor, desk),
                                    onDeskMenu: (desk, position) =>
                                        _openDeskMenu(editor, desk, position),
                                    onGroupTapped: dockPanel
                                        ? null
                                        : (group) => _openPanelSheet(
                                            editor,
                                            initialTab: 3,
                                          ),
                                    onGroupMenu: (group, position) =>
                                        _openGroupMenu(editor, group, position),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Front of room is at the top',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                    CanvasZoomControls(
                                      editor: editor,
                                      view: _view,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_canvasExpanded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          unseated == 0
                              ? Icons.check_circle_outline
                              : Icons.people_outline,
                          size: 17,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            shortage > 0
                                ? '$seated/${editor.roster.length} seated · Add $shortage more seats'
                                : '$seated/${editor.roster.length} seated · ${editor.layout.seatCount - seated} open seats',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (!narrow)
                          Text(
                            'Room edits save automatically',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _moreMenu(SeatingEditorController editor) => MenuAnchor(
    builder: (context, controller, _) => IconButton(
      tooltip: 'More chart options',
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.more_vert),
    ),
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.history),
        onPressed: () => _openPanelSheet(editor, initialTab: 2),
        child: const Text('Saved charts'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.save_as_outlined),
        onPressed: () => _saveAsNewLayout(editor),
        child: const Text('Copy this layout…'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.group_work_outlined),
        onPressed: editor.layout.groups.length < 2
            ? null
            : () {
                editor.rotateGroups();
                _toast('Teams rotated.', onUndo: editor.undo);
              },
        child: const Text('Rotate teams between groups'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.person_off_outlined),
        onPressed: editor.seating.isEmpty
            ? null
            : () {
                editor.clearAllSeats();
                _toast('All seats cleared.', onUndo: editor.undo);
              },
        child: const Text('Clear all seats'),
      ),
    ],
  );

  void _autoSeat(SeatingEditorController editor) {
    final result = editor.seatRemaining();
    final left = result.unseatedStudentIds.length;
    _toast(
      left == 0
          ? 'Everyone has a seat. Your existing placements stayed in place.'
          : '$left students still need a seat. Add desks in Design room.',
      onUndo: editor.undo,
    );
  }

  // --- Sheets and menus ----------------------------------------------------

  /// Roster, layouts, and history in one sheet, for windows too narrow to dock
  /// them.
  Future<void> _openPanelSheet(
    SeatingEditorController editor, {
    int initialTab = 0,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DefaultTabController(
        length: 4,
        initialIndex: initialTab,
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: Column(
            children: [
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Roster'),
                  Tab(text: 'Layouts'),
                  Tab(text: 'History'),
                  Tab(text: 'Properties'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    RosterPanel(
                      editor: editor,
                      workspace: widget.workspace,
                      onStudentPicked: () => Navigator.of(context).pop(),
                    ),
                    _buildLayoutsPanel(editor),
                    _buildHistoryPanel(editor),
                    InspectorPanel(
                      editor: editor,
                      workspace: widget.workspace,
                      onAssignSeat: (desk) {
                        Navigator.of(context).pop();
                        _openAssignSheet(editor, desk);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutsPanel(SeatingEditorController editor) {
    final section = widget.section!;
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) => LayoutsPanel(
        layouts: widget.workspace.layoutsFor(section.id),
        activeLayoutId: editor.layout.id,
        onSelect: (layout) {
          Navigator.of(context).pop();
          _switchLayout(layout);
        },
        onCreate: (preset) {
          Navigator.of(context).pop();
          _createLayout(preset);
        },
        onDuplicate: (layout) {
          final copy = layout.duplicate();
          widget.workspace.addLayoutToClass(copy, section.id);
          Navigator.of(context).pop();
          _switchLayout(copy);
        },
        onRename: (layout) async {
          final name = await _promptForName(
            title: 'Rename layout',
            initial: layout.name,
          );
          if (name != null) {
            final cached = _editors[layout.id];
            if (cached != null) {
              cached.renameLayout(name);
            } else {
              widget.workspace.upsertLayout(layout.copyWith(name: name));
            }
          }
        },
        onDelete: (layout) {
          widget.workspace.deleteLayout(layout.id);
          // _syncEditor falls back to a surviving layout on its own.
          if (layout.id == _editingLayoutId) setState(_syncEditor);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _buildHistoryPanel(SeatingEditorController editor) {
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) => HistoryPanel(
        assignments: widget.workspace.historyForLayout(editor.layout.id),
        onRestore: (assignment) {
          editor.applyAssignment(assignment);
          Navigator.of(context).pop();
          _toast('Restored "${assignment.displayName()}".');
        },
        onDelete: (assignment) =>
            widget.workspace.deleteAssignment(assignment.id),
      ),
    );
  }

  /// Seat picker for one desk: who is unseated, plus swapping with someone who
  /// is already sitting somewhere.
  Future<void> _openAssignSheet(
    SeatingEditorController editor,
    Desk desk,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SeatPicker(editor: editor, desk: desk),
    );
  }

  Future<void> _openDeskMenu(
    SeatingEditorController editor,
    Desk desk,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (desk.isSeat)
          const PopupMenuItem(value: 'assign', child: Text('Seat a student')),
        if (desk.isSeat)
          PopupMenuItem(
            value: 'pin',
            child: Text(
              editor.isPinned(desk.id)
                  ? 'Unpin from shuffles'
                  : 'Pin through shuffles',
            ),
          ),
        if (editor.mode == EditorMode.design) ...[
          const PopupMenuItem(
            value: 'group',
            child: Text('Select whole group'),
          ),
          PopupMenuItem(
            value: 'lock',
            child: Text(desk.locked ? 'Unlock position' : 'Lock position'),
          ),
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ],
    );
    if (!mounted || selected == null) return;

    switch (selected) {
      case 'assign':
        await _openAssignSheet(editor, desk);
      case 'pin':
        editor.togglePinned(desk.id);
      case 'group':
        editor.selectGroupOf(desk.id);
      case 'lock':
        editor.toggleDeskLocked(desk.id);
      case 'duplicate':
        editor.duplicateSelection();
      case 'delete':
        editor.deleteSelection();
    }
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _openGroupMenu(
    SeatingEditorController editor,
    DeskGroup group,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'edit', child: Text('Edit group')),
        PopupMenuItem(
          value: 'rotate',
          enabled: !editor.groupPositionLocked,
          child: const Text('Rotate group 90°'),
        ),
        PopupMenuItem(
          value: 'lock',
          child: Text(
            editor.groupPositionLocked
                ? 'Unlock group position'
                : 'Lock group position',
          ),
        ),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate group')),
        const PopupMenuItem(value: 'ungroup', child: Text('Ungroup desks')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete group and desks'),
        ),
      ],
    );
    if (!mounted ||
        action == null ||
        editor.layout.groupById(group.id) == null) {
      return;
    }
    editor.selectGroup(group.id);
    switch (action) {
      case 'edit':
        await _openPanelSheet(editor, initialTab: 3);
      case 'rotate':
        editor.rotateSelectionBy(90);
      case 'lock':
        editor.setSelectionLocked(!editor.groupPositionLocked);
      case 'duplicate':
        editor.duplicateSelection();
      case 'ungroup':
        editor.ungroupSelection();
      case 'delete':
        editor.deleteSelection();
    }
  }

  void _switchLayout(RoomLayout layout) {
    widget.workspace.setActiveLayout(widget.section!.id, layout.id);
    setState(() => _syncEditor(layoutId: layout.id));
    _view.fit(layout.roomSize);
  }

  Future<void> _createLayout(LayoutPreset preset) async {
    final section = widget.section;
    if (section == null) return;
    final name = await _promptForName(
      title: 'New layout',
      initial: preset.label,
    );
    if (name == null) return;

    final layout = buildPresetLayout(
      preset: preset.name,
      name: name,
      classSectionId: section.id,
    );
    widget.workspace.addLayoutToClass(layout, section.id);
    if (!mounted) return;
    setState(() => _syncEditor(layoutId: layout.id));
    _view.fit(layout.roomSize);
  }

  Future<void> _saveAsNewLayout(SeatingEditorController editor) async {
    final name = await _promptForName(
      title: 'Save as new layout',
      initial: '${editor.layout.name} (copy)',
    );
    if (name == null) return;
    final copy = editor.saveAsNewLayout(name);
    if (!mounted) return;
    setState(() {
      _editors.removeWhere((_, value) => identical(value, editor));
      _editors[copy.id] = editor;
      _editingLayoutId = copy.id;
    });
    _toast('Saved as "$name".');
  }

  void _shuffle(SeatingEditorController editor) {
    final result = editor.shuffleSeating();
    final left = result.unseatedStudentIds.length;
    _toast(
      left == 0
          ? 'Class shuffled.'
          : 'Class shuffled — $left students still need a seat.',
      onUndo: editor.undo,
    );
  }

  Future<void> _saveAssignment(SeatingEditorController editor) async {
    final name = await _promptForName(
      title: 'Save this seating',
      initial: '',
      hint: 'e.g. Week of Sep 22',
      allowEmpty: true,
    );
    if (name == null) return;
    editor.saveAssignment(name: name);
    _toast('Saved to history.');
  }

  Future<String?> _promptForName({
    required String title,
    required String initial,
    String? hint,
    bool allowEmpty = false,
  }) async {
    var value = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          onChanged: (text) => value = text,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Name', hintText: hint),
          onFieldSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(value),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return null;
    final trimmed = result.trim();
    if (trimmed.isEmpty && !allowEmpty) return null;
    return trimmed;
  }

  void _toast(String message, {VoidCallback? onUndo}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: onUndo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: onUndo),
        ),
      );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
