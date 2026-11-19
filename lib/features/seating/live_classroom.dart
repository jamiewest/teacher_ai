import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import 'room_view_controller.dart';
import 'seating_editor_controller.dart';
import 'widgets/canvas_overlay_controls.dart';
import 'widgets/room_canvas.dart';

/// Live teaching keeps the room fixed and puts scoring within reach without
/// crowding the classroom canvas.
///
/// On expanded desktops it docks controls into a sleek side panel; on phones
/// and compact windows it floats controls over the bottom edge so the room
/// owns almost the entire viewport.
class LiveClassroom extends StatefulWidget {
  const LiveClassroom({
    required this.workspace,
    required this.section,
    required this.editor,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEdit,
    super.key,
  });

  final TeacherWorkspace workspace;
  final ClassSection section;
  final SeatingEditorController editor;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEdit;

  @override
  State<LiveClassroom> createState() => LiveClassroomState();
}

class LiveClassroomState extends State<LiveClassroom> {
  final _view = RoomViewController();
  String? _studentId;
  int _tapDelta = 0;
  ParticipationEntry? _lastEntry;

  @override
  void didUpdateWidget(LiveClassroom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor) {
      _studentId = null;
      _lastEntry = null;
      _view.fit(widget.editor.layout.roomSize);
    }
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  void openWeeklySheet() => _showWeek(context);

  int _total(String id, DateTime start, DateTime end) =>
      widget.workspace.participationTotal(id, widget.section.id, start, end);

  void _score(Student student, int delta) {
    final entry = widget.workspace.addParticipation(
      studentId: student.id,
      classSectionId: widget.section.id,
      delta: delta,
    );
    HapticFeedback.selectionClick();
    setState(() {
      _studentId = student.id;
      _lastEntry = entry;
    });
  }

  void _onSeatTapped(Desk desk, {required bool isCompactOverlay}) {
    final student = widget.editor.studentAt(desk.id);
    setState(() => _studentId = student?.id);

    // On touch devices only, zoom into tiny desks first so fingers do not
    // mis-tap neighbors. Desktop/pointer clicks score immediately.
    if (student != null &&
        context.isTouch &&
        desk.width * _view.scale < 44) {
      final targetScale = 48.0 / desk.width;
      if (targetScale > _view.scale) {
        _view.zoomAtCenter(targetScale / _view.scale);
      }
      _view.centerOn(desk.center);
      return;
    }

    if (student != null && _tapDelta != 0) {
      _score(student, _tapDelta);
      return;
    }

    // If a bottom-row seat was selected behind the floating mobile dock, nudge
    // the room upward just enough to reveal it.
    if (student != null &&
        isCompactOverlay &&
        _view.viewport.height > 200 &&
        _view.toScreen(desk.center).dy > _view.viewport.height - 150) {
      _view.panBy(const Offset(0, -110));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.workspace, widget.editor]),
    builder: (context, _) {
      final now = DateTime.now();
      final today = schoolDate(now);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final week = weekStart(now);
      final weekEnd = DateTime(week.year, week.month, week.day + 7);
      final selected = widget.editor.roster
          .where((s) => s.id == _studentId)
          .firstOrNull;
      final palette = RoomPalette.of(context);
      final dockSide = context.isExpanded && !widget.expanded;
      final isCompact = context.isCompact;

      final canvas = ColoredBox(
        color: palette.canvasBackdrop,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: RoomCanvas(
                  controller: widget.editor,
                  view: _view,
                  workspace: widget.workspace,
                  readOnly: true,
                  scores: {
                    for (final s in widget.editor.roster)
                      s.id: _total(s.id, today, tomorrow),
                  },
                  onSeatTapped: (desk) =>
                      _onSeatTapped(desk, isCompactOverlay: !dockSide),
                ),
              ),
            ),
            if (dockSide)
              Positioned(
                bottom: 12,
                right: 12,
                child: CanvasZoomPill(
                  view: _view,
                  roomSize: widget.editor.layout.roomSize,
                  expanded: widget.expanded,
                  onToggleExpanded: widget.onToggleExpanded,
                ),
              )
            else ...[
              Positioned(
                top: 8,
                right: 8,
                child: CanvasZoomPill(
                  view: _view,
                  roomSize: widget.editor.layout.roomSize,
                  expanded: widget.expanded,
                  onToggleExpanded: widget.onToggleExpanded,
                  compact: isCompact,
                ),
              ),
              if (_lastEntry != null)
                Positioned(
                  top: isCompact ? 50 : 12,
                  left: 12,
                  right: isCompact ? 12 : 210,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _FloatingUndoPill(
                      entry: _lastEntry!,
                      studentName:
                          widget.workspace
                              .student(_lastEntry!.studentId)
                              ?.fullName ??
                          'Student',
                      onUndo: () {
                        widget.workspace.undoParticipation(_lastEntry!.id);
                        setState(() => _lastEntry = null);
                      },
                      onDismiss: () => setState(() => _lastEntry = null),
                    ),
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _MobileLiveDock(
                      editor: widget.editor,
                      selected: selected,
                      tapDelta: _tapDelta,
                      todayTotal: selected == null
                          ? 0
                          : _total(selected.id, today, tomorrow),
                      weekTotal: selected == null
                          ? 0
                          : _total(selected.id, week, weekEnd),
                      compact: isCompact,
                      onTapModeChanged: (mode) =>
                          setState(() => _tapDelta = mode),
                      onPickStudent: _pickStudent,
                      onClearStudent: () => setState(() => _studentId = null),
                      onScore: (delta) => _score(selected!, delta),
                      onEdit: widget.onEdit,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

      if (!dockSide) return canvas;

      return Row(
        children: [
          Expanded(child: canvas),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 288,
            child: _DesktopLivePanel(
              workspace: widget.workspace,
              editor: widget.editor,
              selected: selected,
              lastEntry: _lastEntry,
              tapDelta: _tapDelta,
              todayTotal: selected == null
                  ? 0
                  : _total(selected.id, today, tomorrow),
              weekTotal: selected == null
                  ? 0
                  : _total(selected.id, week, weekEnd),
              onTapModeChanged: (mode) => setState(() => _tapDelta = mode),
              onPickStudent: _pickStudent,
              onScore: (delta) => _score(selected!, delta),
              onUndo: () {
                widget.workspace.undoParticipation(_lastEntry!.id);
                setState(() => _lastEntry = null);
              },
              onEdit: widget.onEdit,
              onShowWeek: () => _showWeek(context),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _pickStudent() async {
    final picked = await showModalBottomSheet<Student>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose a student',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Includes unseated students so you can still score them.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final student in widget.editor.roster)
                      ListTile(
                        title: Text(student.fullName),
                        subtitle: Text(
                          widget.editor.seating.containsValue(student.id)
                              ? 'Seated'
                              : 'Not yet seated',
                        ),
                        onTap: () => Navigator.pop(context, student),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _studentId = picked.id);
    for (final desk in widget.editor.layout.seats) {
      if (widget.editor.studentAt(desk.id)?.id == picked.id) {
        widget.editor.selectOnly(desk.id);
        if (_view.scale < 1) _view.zoomAtCenter(1 / _view.scale);
        _view.centerOn(desk.center);
        break;
      }
    }
  }

  void _showWeek(BuildContext context) {
    var week = weekStart(DateTime.now());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final end = DateTime(week.year, week.month, week.day + 7);
          final entries = widget.workspace.participation
              .where(
                (e) =>
                    e.classSectionId == widget.section.id &&
                    !e.occurredAt.isBefore(week) &&
                    e.occurredAt.isBefore(end),
              )
              .toList();
          final ids = {
            ...widget.section.studentIds,
            ...entries.map((e) => e.studentId),
          };
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: Column(
                children: [
                  Text(
                    'Weekly participation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(widget.section.name),
                  const SizedBox(height: 2),
                  Text(
                    'Tap a student to view dated entries',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous week',
                        onPressed: () => setSheetState(
                          () => week = DateTime(
                            week.year,
                            week.month,
                            week.day - 7,
                          ),
                        ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          '${week.month}/${week.day}/${week.year} – ${DateTime(end.year, end.month, end.day - 1).month}/${DateTime(end.year, end.month, end.day - 1).day}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next week',
                        onPressed: () => setSheetState(() => week = end),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      Tooltip(
                        message: 'Jump back to the current week',
                        excludeFromSemantics: true,
                        child: TextButton(
                          onPressed: () => setSheetState(
                            () => week = weekStart(DateTime.now()),
                          ),
                          child: const Text('This week'),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final id in ids)
                          ExpansionTile(
                            title: Text(
                              widget.workspace.student(id)?.fullName ??
                                  'Former student',
                            ),
                            trailing: Text(
                              '${_total(id, week, end)} pts',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            children: [
                              if (!entries.any((e) => e.studentId == id))
                                const ListTile(
                                  title: Text('No points recorded this week'),
                                ),
                              for (final entry
                                  in entries
                                      .where((e) => e.studentId == id)
                                      .toList()
                                      .reversed)
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    '${entry.delta > 0 ? '+1' : '−1'} participation',
                                  ),
                                  subtitle: Text(
                                    '${entry.occurredAt.month}/${entry.occurredAt.day} · ${TimeOfDay.fromDateTime(entry.occurredAt).format(context)}',
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FloatingUndoPill extends StatelessWidget {
  const _FloatingUndoPill({
    required this.entry,
    required this.studentName,
    required this.onUndo,
    required this.onDismiss,
  });

  final ParticipationEntry entry;
  final String studentName;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FloatingPillSurface(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.only(left: 12, right: 4, top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '${entry.delta > 0 ? '+1' : '−1'} · $studentName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Undo the last participation point',
            excludeFromSemantics: true,
            child: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.onSecondaryContainer,
              ),
              onPressed: onUndo,
              child: const Text('Undo'),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            iconSize: 16,
            color: scheme.onSecondaryContainer,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _MobileLiveDock extends StatelessWidget {
  const _MobileLiveDock({
    required this.editor,
    required this.selected,
    required this.tapDelta,
    required this.todayTotal,
    required this.weekTotal,
    required this.compact,
    required this.onTapModeChanged,
    required this.onPickStudent,
    required this.onClearStudent,
    required this.onScore,
    required this.onEdit,
  });

  final SeatingEditorController editor;
  final Student? selected;
  final int tapDelta;
  final int todayTotal;
  final int weekTotal;
  final bool compact;
  final ValueChanged<int> onTapModeChanged;
  final VoidCallback onPickStudent;
  final VoidCallback onClearStudent;
  final ValueChanged<int> onScore;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FloatingPillSurface(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected!.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        'Today: $todayTotal · This week: $weekTotal',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Clear student selection',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onPressed: onClearStudent,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'Deduct 1 participation point',
                    excludeFromSemantics: true,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () => onScore(-1),
                      icon: const Icon(Icons.remove, size: 18),
                      label: const Text('Deduct 1'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: 'Add 1 participation point',
                    excludeFromSemantics: true,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () => onScore(1),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add 1'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: 0,
                      tooltip: 'Tap a seat to select a student without scoring',
                      label: const Text('Select', maxLines: 1),
                      icon: compact
                          ? null
                          : const Icon(Icons.touch_app_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: 1,
                      tooltip: 'Tap any occupied seat to add 1 point',
                      label: const Text('Tap +1', maxLines: 1),
                      icon: compact ? null : const Icon(Icons.add, size: 16),
                    ),
                    ButtonSegment(
                      value: -1,
                      tooltip: 'Tap any occupied seat to deduct 1 point',
                      label: const Text('Tap −1', maxLines: 1),
                      icon: compact ? null : const Icon(Icons.remove, size: 16),
                    ),
                  ],
                  selected: {tapDelta},
                  onSelectionChanged: (v) => onTapModeChanged(v.first),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Choose student',
                visualDensity: VisualDensity.compact,
                onPressed: onPickStudent,
                icon: const Icon(Icons.people_outline),
              ),
            ],
          ),
          if (editor.seating.isEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.center,
              child: Tooltip(
                message: 'Switch to Seat students to assign desks',
                excludeFromSemantics: true,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.event_seat_outlined, size: 16),
                  label: const Text('Set up seating'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopLivePanel extends StatelessWidget {
  const _DesktopLivePanel({
    required this.workspace,
    required this.editor,
    required this.selected,
    required this.lastEntry,
    required this.tapDelta,
    required this.todayTotal,
    required this.weekTotal,
    required this.onTapModeChanged,
    required this.onPickStudent,
    required this.onScore,
    required this.onUndo,
    required this.onEdit,
    required this.onShowWeek,
  });

  final TeacherWorkspace workspace;
  final SeatingEditorController editor;
  final Student? selected;
  final ParticipationEntry? lastEntry;
  final int tapDelta;
  final int todayTotal;
  final int weekTotal;
  final ValueChanged<int> onTapModeChanged;
  final VoidCallback onPickStudent;
  final ValueChanged<int> onScore;
  final VoidCallback onUndo;
  final VoidCallback onEdit;
  final VoidCallback onShowWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TAP MODE',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.9,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                tooltip: 'Tap a seat to select a student without scoring',
                label: Text('Select'),
              ),
              ButtonSegment(
                value: 1,
                tooltip: 'Tap any occupied seat to add 1 point',
                label: Text('Tap +1'),
              ),
              ButtonSegment(
                value: -1,
                tooltip: 'Tap any occupied seat to deduct 1 point',
                label: Text('Tap −1'),
              ),
            ],
            selected: {tapDelta},
            onSelectionChanged: (v) => onTapModeChanged(v.first),
          ),
          const SizedBox(height: 6),
          Text(
            switch (tapDelta) {
              1 => 'Tap any seat to immediately add +1.',
              -1 => 'Tap any seat to immediately deduct −1.',
              _ => 'Tap a seat to inspect or score.',
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected?.fullName ?? 'Select a student',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selected == null
                                  ? 'Tap a seat or use the class list'
                                  : 'Today: $todayTotal · This week: $weekTotal',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Choose student',
                        onPressed: onPickStudent,
                        icon: const Icon(Icons.people_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'Deduct 1 participation point',
                          excludeFromSemantics: true,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: selected == null
                                ? null
                                : () => onScore(-1),
                            icon: const Icon(Icons.remove, size: 18),
                            label: const Text('Deduct 1'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: 'Add 1 participation point',
                          excludeFromSemantics: true,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: selected == null
                                ? null
                                : () => onScore(1),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add 1'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: lastEntry == null
                ? scheme.surfaceContainerLow
                : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lastEntry == null
                            ? 'Today’s participation'
                            : '${lastEntry!.delta > 0 ? '+1' : '−1'} · ${workspace.student(lastEntry!.studentId)?.fullName ?? 'Student'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: lastEntry == null
                              ? scheme.onSurfaceVariant
                              : scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Undo the last participation point',
                      excludeFromSemantics: true,
                      child: TextButton(
                        onPressed: lastEntry == null ? null : onUndo,
                        child: const Text('Undo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (editor.seating.isEmpty)
            Tooltip(
              message: 'Switch to Seat students to assign desks',
              excludeFromSemantics: true,
              child: FilledButton.tonalIcon(
                onPressed: onEdit,
                icon: const Icon(Icons.event_seat_outlined),
                label: const Text('Set up seating'),
              ),
            )
          else if (editor.unseatedStudents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${editor.unseatedStudents.length} unseated · Use the class list',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Tooltip(
            message: 'View weekly point totals and timestamped entries',
            excludeFromSemantics: true,
            child: OutlinedButton.icon(
              onPressed: onShowWeek,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: const Text('Weekly breakdown'),
            ),
          ),
        ],
      ),
    );
  }
}
