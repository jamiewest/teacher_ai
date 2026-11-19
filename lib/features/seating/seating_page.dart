import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import '../../domain/ops/layout_presets.dart';
import 'live_classroom.dart';
import 'room_view_controller.dart';
import 'seating_editor_controller.dart';
import 'seating_editor_state.dart';
import 'widgets/canvas_overlay_controls.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/layouts_panel.dart';
import 'widgets/room_canvas.dart';
import 'widgets/roster_panel.dart';
import 'widgets/seat_picker.dart';

enum _WorkspaceMode { live, seating, design }

/// The seating workspace: Live teaching, Seat students, and Design room.
///
/// Chrome collapses into a single unified header and floating canvas pills so
/// the classroom layout remains the focus on both phones and desktops.
class SeatingPage extends StatefulWidget {
  const SeatingPage({
    required this.workspace,
    required this.section,
    this.settings,
    this.isFollowingSchedule = true,
    this.isHeldWhileEditing = false,
    this.currentPeriod,
    this.isFullscreen = false,
    this.onFullscreenChanged,
    this.onPickClass,
    this.onOpenSettings,
    this.onEditingChanged,
    super.key,
  });

  final TeacherWorkspace workspace;
  final ClassSection? section;
  final AppSettingsController? settings;
  final bool isFollowingSchedule;
  final bool isHeldWhileEditing;
  final SchedulePeriod? currentPeriod;
  final bool isFullscreen;
  final ValueChanged<bool>? onFullscreenChanged;
  final VoidCallback? onPickClass;
  final VoidCallback? onOpenSettings;
  final ValueChanged<bool>? onEditingChanged;

  @override
  State<SeatingPage> createState() => _SeatingPageState();
}

class _SeatingPageState extends State<SeatingPage> {
  final _normalView = RoomViewController();
  final _expandedView = RoomViewController();
  final _liveKey = GlobalKey<LiveClassroomState>();
  bool _canvasExpanded = false;
  bool _live = true;
  AppSettings? _lastSettings;

  RoomViewController get _view => _canvasExpanded ? _expandedView : _normalView;
  SeatingEditorController? _editor;
  String? _editingLayoutId;
  final _editors = <String, SeatingEditorController>{};

  @override
  void initState() {
    super.initState();
    _lastSettings = widget.settings?.settings;
    widget.settings?.addListener(_onSettingsChanged);
    _syncEditor();
  }

  @override
  void didUpdateWidget(SeatingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings?.removeListener(_onSettingsChanged);
      _lastSettings = widget.settings?.settings;
      widget.settings?.addListener(_onSettingsChanged);
    }
    if (oldWidget.isFullscreen != widget.isFullscreen &&
        widget.isFullscreen != _canvasExpanded) {
      _canvasExpanded = widget.isFullscreen;
    }
    if (oldWidget.section?.id != widget.section?.id) _syncEditor();
  }

  @override
  void dispose() {
    widget.settings?.removeListener(_onSettingsChanged);
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _normalView.dispose();
    _expandedView.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    final current = widget.settings?.settings;
    final previous = _lastSettings;
    _lastSettings = current;
    if (current == null || previous == null) return;
    final editor = _editor;
    if (editor == null) return;
    if (current.showGridByDefault != previous.showGridByDefault) {
      editor.setShowGrid(current.showGridByDefault);
    }
    if (current.showTagDotsByDefault != previous.showTagDotsByDefault) {
      editor.setShowTags(current.showTagDotsByDefault);
    }
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
    _editor = _editors.putIfAbsent(layout.id, () {
      final controller = SeatingEditorController(
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
      );
      final defaults = widget.settings?.settings;
      if (defaults != null) {
        controller.setShowGrid(defaults.showGridByDefault);
        controller.setShowTags(defaults.showTagDotsByDefault);
      }
      return controller;
    });
    _normalView.fit(layout.roomSize);
    _expandedView.fit(layout.roomSize);
  }

  void _toggleCanvas() {
    if (!_canvasExpanded && _editor != null) {
      _expandedView.fit(_editor!.layout.roomSize);
    }
    final next = !_canvasExpanded;
    setState(() => _canvasExpanded = next);
    widget.onFullscreenChanged?.call(next);
  }

  /// Cached editors are disposed together when the page closes.
  void _retireEditor() {
    _editor = null;
  }

  _WorkspaceMode _activeMode(SeatingEditorController editor) {
    if (_live) return _WorkspaceMode.live;
    return editor.mode == EditorMode.design
        ? _WorkspaceMode.design
        : _WorkspaceMode.seating;
  }

  void _setMode(_WorkspaceMode mode, SeatingEditorController editor) {
    if (mode == _WorkspaceMode.live) {
      if (!_live) {
        if (editor.hasUnsavedSeating) editor.saveAssignment();
        editor.setMode(EditorMode.seating);
        widget.onEditingChanged?.call(false);
        setState(() => _live = true);
      }
      return;
    }

    final editorMode = mode == _WorkspaceMode.design
        ? EditorMode.design
        : EditorMode.seating;
    if (_live) {
      widget.onEditingChanged?.call(true);
    }
    editor.setMode(editorMode);
    setState(() => _live = false);
  }

  String get _scheduleTooltip {
    if (widget.isHeldWhileEditing) return 'Class held while editing';
    if (widget.isFollowingSchedule) {
      final period = widget.currentPeriod;
      return period == null
          ? 'Following schedule'
          : 'Following schedule · ${period.name} (${period.start.format()}–${period.end.format()})';
    }
    return 'Manual class selection';
  }

  IconData get _scheduleIcon {
    if (widget.isHeldWhileEditing) return Icons.lock_clock_outlined;
    if (widget.isFollowingSchedule) return Icons.schedule;
    return Icons.pan_tool_alt_outlined;
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
      return Scaffold(
        appBar: AppBar(
          title: const Text('Seating'),
          actions: [
            if (widget.onOpenSettings != null)
              IconButton(
                tooltip: 'Settings',
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        body: const _EmptyState(
          icon: Icons.class_outlined,
          title: 'No classes yet',
          message: 'Add a class to start building a seating chart.',
        ),
      );
    }
    if (editor == null) {
      return Scaffold(
        appBar: AppBar(
          title: InkWell(
            key: const ValueKey('class-selector-pill'),
            onTap: widget.onPickClass,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.workspace.classLabel(section),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.onPickClass != null)
                  const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          actions: [
            if (widget.onOpenSettings != null)
              IconButton(
                tooltip: 'Settings',
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        body: _EmptyState(
          icon: Icons.grid_view_outlined,
          title: 'No layout yet',
          message: 'Create a layout for ${section.name} to get started.',
          action: FilledButton.icon(
            onPressed: () => _createLayout(LayoutPreset.rows),
            icon: const Icon(Icons.add),
            label: const Text('Create a layout'),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final isCompact = context.isCompact;
        final dockPanel = !_canvasExpanded && context.isExpanded;
        final designing = editor.mode == EditorMode.design;
        final unseated = editor.unseatedStudents.length;
        final seated = editor.roster.length - unseated;
        final shortage = editor.roster.length - editor.layout.seatCount;
        final palette = RoomPalette.of(context);
        final scheme = Theme.of(context).colorScheme;

        return Scaffold(
          body: Column(
            children: [
              if (!_canvasExpanded) ...[
                _buildHeader(context, section, editor),
                const Divider(height: 1),
              ],
              Expanded(
                child: _live
                    ? LiveClassroom(
                        key: _liveKey,
                        workspace: widget.workspace,
                        section: section,
                        editor: editor,
                        expanded: _canvasExpanded,
                        onToggleExpanded: _toggleCanvas,
                        onEdit: () => _setMode(_WorkspaceMode.seating, editor),
                      )
                    : Row(
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
                              color: palette.canvasBackdrop,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRect(
                                      child: RoomCanvas(
                                        controller: editor,
                                        view: _view,
                                        workspace: widget.workspace,
                                        onSeatTapped: (desk) =>
                                            _openAssignSheet(editor, desk),
                                        onDeskMenu: (desk, position) =>
                                            _openDeskMenu(
                                              editor,
                                              desk,
                                              position,
                                            ),
                                        onGroupTapped: dockPanel
                                            ? null
                                            : (group) => _openPanelSheet(
                                                editor,
                                                initialTab: 3,
                                              ),
                                        onGroupMenu: (group, position) =>
                                            _openGroupMenu(
                                              editor,
                                              group,
                                              position,
                                            ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: _SeatCountPill(
                                      seated: seated,
                                      rosterCount: editor.roster.length,
                                      shortage: shortage,
                                      compact: isCompact,
                                    ),
                                  ),
                                  if (isCompact)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: CanvasZoomPill(
                                        view: _view,
                                        roomSize: editor.layout.roomSize,
                                        expanded: _canvasExpanded,
                                        onToggleExpanded: _toggleCanvas,
                                        compact: true,
                                      ),
                                    )
                                  else
                                    Positioned(
                                      bottom: 12,
                                      right: 12,
                                      child: CanvasZoomPill(
                                        view: _view,
                                        roomSize: editor.layout.roomSize,
                                        expanded: _canvasExpanded,
                                        onToggleExpanded: _toggleCanvas,
                                      ),
                                    ),
                                  if (editor.pendingStudent != null)
                                    Positioned(
                                      top: isCompact ? 50 : 10,
                                      left: 12,
                                      right: 12,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: FloatingPillSurface(
                                          color: scheme.primaryContainer,
                                          padding: const EdgeInsets.only(
                                            left: 14,
                                            right: 4,
                                            top: 2,
                                            bottom: 2,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'Tap a seat for ${editor.pendingStudent!.fullName}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onPrimaryContainer,
                                                      ),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Cancel student placement',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                color:
                                                    scheme.onPrimaryContainer,
                                                onPressed: () =>
                                                    editor.pickStudent(null),
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 10,
                                    left: 10,
                                    right: isCompact ? 10 : 210,
                                    child: Align(
                                      alignment: isCompact
                                          ? Alignment.bottomCenter
                                          : Alignment.bottomLeft,
                                      child: EditorToolbar(
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
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ClassSection section,
    SeatingEditorController editor,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final classLabel = widget.workspace.classLabel(section);

    return Material(
      color: scheme.surface,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final twoRow = bounds.maxWidth < 680;
          if (twoRow) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: _scheduleTooltip,
                              child: InkWell(
                                key: const ValueKey('class-selector-pill'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: widget.onPickClass,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _scheduleIcon,
                                        size: 14,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          classLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ),
                                      if (widget.onPickClass != null)
                                        const Icon(
                                          Icons.arrow_drop_down,
                                          size: 18,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () =>
                                  _openPanelSheet(editor, initialTab: 1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 1,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.layers_outlined,
                                      size: 13,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        editor.layout.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      size: 15,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_live) ...[
                        IconButton(
                          tooltip: 'Weekly points',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _liveKey.currentState?.openWeeklySheet(),
                          icon: const Icon(Icons.date_range_outlined),
                        ),
                        if (widget.onOpenSettings != null)
                          IconButton(
                            tooltip: 'Settings',
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.onOpenSettings,
                            icon: const Icon(Icons.settings_outlined),
                          ),
                      ] else ...[
                        _SaveButton(
                          compact: true,
                          hasUnsaved: editor.hasUnsavedSeating,
                          onPressed: () => _saveAssignment(editor),
                        ),
                        _moreMenu(editor, includeSettings: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  _modeSegmentedButton(
                    editor,
                    compact: true,
                    hideIcons: bounds.maxWidth < 400,
                  ),
                ],
              ),
            );
          }

          return SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Tooltip(
                            message: _scheduleTooltip,
                            child: ActionChip(
                              key: const ValueKey('class-selector-pill'),
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(
                                _scheduleIcon,
                                size: 16,
                                color: scheme.primary,
                              ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      classLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (widget.onPickClass != null)
                                    const Icon(Icons.arrow_drop_down, size: 18),
                                ],
                              ),
                              onPressed: widget.onPickClass,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.layers_outlined, size: 16),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    editor.layout.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, size: 18),
                              ],
                            ),
                            onPressed: () =>
                                _openPanelSheet(editor, initialTab: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _modeSegmentedButton(
                    editor,
                    compact: bounds.maxWidth < 960,
                    hideIcons: false,
                  ),
                  const SizedBox(width: 12),
                  if (_live)
                    Tooltip(
                      message: 'Weekly points',
                      child: TextButton.icon(
                        onPressed: () =>
                            _liveKey.currentState?.openWeeklySheet(),
                        icon: const Icon(Icons.date_range_outlined, size: 18),
                        label: const Text('Weekly points'),
                      ),
                    )
                  else ...[
                    _SaveButton(
                      compact: bounds.maxWidth < 820,
                      hasUnsaved: editor.hasUnsavedSeating,
                      onPressed: () => _saveAssignment(editor),
                    ),
                    _moreMenu(editor, includeSettings: false),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _modeSegmentedButton(
    SeatingEditorController editor, {
    required bool compact,
    required bool hideIcons,
  }) {
    return SegmentedButton<_WorkspaceMode>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        ),
      ),
      segments: [
        ButtonSegment(
          value: _WorkspaceMode.live,
          tooltip: 'Live classroom',
          icon: hideIcons
              ? null
              : const Icon(Icons.play_circle_outline, size: 17),
          label: const Text(
            'Live',
            key: ValueKey('mode-live'),
            maxLines: 1,
            softWrap: false,
          ),
        ),
        ButtonSegment(
          value: _WorkspaceMode.seating,
          tooltip: 'Edit seating',
          icon: hideIcons
              ? null
              : const Icon(Icons.event_seat_outlined, size: 17),
          label: Text(
            compact ? 'Seat' : 'Seat students',
            key: const ValueKey('mode-seating'),
            maxLines: 1,
            softWrap: false,
          ),
        ),
        ButtonSegment(
          value: _WorkspaceMode.design,
          tooltip: 'Design room',
          icon: hideIcons ? null : const Icon(Icons.edit_outlined, size: 17),
          label: Text(
            compact ? 'Design' : 'Design room',
            key: const ValueKey('mode-design'),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ],
      selected: {_activeMode(editor)},
      onSelectionChanged: (values) => _setMode(values.first, editor),
    );
  }

  Widget _moreMenu(
    SeatingEditorController editor, {
    required bool includeSettings,
  }) => MenuAnchor(
    builder: (context, controller, _) => IconButton(
      tooltip: 'More chart options',
      visualDensity: VisualDensity.compact,
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
      if (includeSettings && widget.onOpenSettings != null) ...[
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: widget.onOpenSettings,
          child: const Text('Settings'),
        ),
      ],
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

  /// Roster, layouts, history, and properties in one sheet, for windows too
  /// narrow to dock them.
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
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 68),
          content: Text(message),
          action: onUndo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: onUndo),
        ),
      );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.compact,
    required this.hasUnsaved,
    required this.onPressed,
  });

  final bool compact;
  final bool hasUnsaved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 8,
        ),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(compact ? 'Save' : 'Save chart'),
          if (hasUnsaved) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: scheme.onPrimary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeatCountPill extends StatelessWidget {
  const _SeatCountPill({
    required this.seated,
    required this.rosterCount,
    required this.shortage,
    required this.compact,
  });

  final int seated;
  final int rosterCount;
  final int shortage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warn = shortage > 0;
    final text = warn
        ? (compact ? '+$shortage seats' : 'Add $shortage more seats')
        : '$seated/$rosterCount seated';

    return FloatingPillSurface(
      color: warn ? scheme.errorContainer : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            warn
                ? Icons.warning_amber_rounded
                : seated == rosterCount
                ? Icons.check_circle_outline
                : Icons.people_outline,
            size: 15,
            color: warn ? scheme.onErrorContainer : scheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: warn ? scheme.onErrorContainer : scheme.onSurface,
            ),
          ),
        ],
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
