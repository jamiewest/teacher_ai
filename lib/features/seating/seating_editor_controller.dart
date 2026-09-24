import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../common/ids.dart';
import '../../data/teacher_workspace.dart';
import '../../domain/models/models.dart';
import '../../domain/ops/layout_ops.dart';
import '../../domain/ops/seating_ops.dart';
import 'seating_editor_state.dart';

/// Drives the seating chart editor for one layout.
///
/// Every mutation produces a new [EditorSnapshot]; the controller keeps a
/// bounded stack of them so undo/redo works for the whole editor, including
/// shuffles. Continuous gestures (dragging, rotating) are wrapped in
/// [beginInteraction]/[endInteraction] so a drag lands as a single undo step
/// instead of one per frame.
class SeatingEditorController extends ChangeNotifier {
  SeatingEditorController({
    required TeacherWorkspace workspace,
    required RoomLayout layout,
    required String classSectionId,
    Map<String, String>? seating,
    Set<String> pinnedSeats = const {},
  }) : _workspace = workspace,
       _classSectionId = classSectionId,
       _syncedLayout = layout,
       _snapshot = EditorSnapshot(
         layout: layout,
         seatToStudent: seating ?? const <String, String>{},
         pinnedSeats: pinnedSeats,
       );

  /// Deep enough for a work session, bounded so a long editing run cannot
  /// grow memory without limit.
  static const int maxHistory = 100;

  final TeacherWorkspace _workspace;
  final String _classSectionId;

  EditorSnapshot _snapshot;
  final List<EditorSnapshot> _undo = <EditorSnapshot>[];
  final List<EditorSnapshot> _redo = <EditorSnapshot>[];
  EditorSnapshot? _interactionBaseline;

  /// The last layout handed to the workspace, so autosave can skip writes for
  /// changes that only touched seating.
  RoomLayout _syncedLayout;

  Set<String> _selection = <String>{};
  EditorTool _tool = EditorTool.select;
  EditorMode _mode = EditorMode.seating;
  String? _pendingStudentId;

  EditorMode get mode => _mode;
  String? get pendingStudentId => _pendingStudentId;
  Student? get pendingStudent =>
      _pendingStudentId == null ? null : _workspace.student(_pendingStudentId!);

  bool get hasUnsavedSeating {
    final saved = _workspace.latestAssignment(layout.id);
    return !mapEquals(
          seating,
          saved?.seatToStudent ?? const <String, String>{},
        ) ||
        !setEquals(pinnedSeats, saved?.lockedDeskIds ?? const <String>{});
  }

  void setMode(EditorMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _tool = EditorTool.select;
    _selection = {};
    _pendingStudentId = null;
    notifyListeners();
  }

  void pickStudent(String? studentId) {
    _pendingStudentId = studentId;
    notifyListeners();
  }

  /// Move an existing student by swapping, so nobody silently loses a seat.
  void placeStudent(String deskId, String studentId) {
    final desk = layout.deskById(deskId);
    if (desk == null || !desk.isSeat) return;
    final previous = snapshot.deskForStudent(studentId);
    _pendingStudentId = null;
    if (previous == deskId) {
      notifyListeners();
    } else if (previous != null) {
      swapSeats(previous, deskId);
    } else {
      assignStudent(deskId, studentId);
    }
  }

  /// Fill empty seats without disturbing the teacher's manual placements.
  ShuffleResult seatRemaining({int? seed}) {
    final result = SeatingOps.shuffle(
      layout: layout,
      students: roster,
      current: seating,
      lockedDeskIds: {...pinnedSeats, ...seating.keys},
      tagsById: _workspace.tagsById,
      seed: seed,
    );
    _apply(_snapshot.copyWith(seatToStudent: result.seatToStudent));
    _lastSeed = result.seed;
    return result;
  }

  RotationSnap _rotationSnap = RotationSnap.deg15;
  bool _snapToGrid = true;
  bool _showGrid = true;
  bool _showTags = true;
  bool _dirty = false;

  // --- Reads ---------------------------------------------------------------

  EditorSnapshot get snapshot => _snapshot;
  RoomLayout get layout => _snapshot.layout;
  Map<String, String> get seating => _snapshot.seatToStudent;
  Set<String> get pinnedSeats => _snapshot.pinnedSeats;
  String get classSectionId => _classSectionId;

  Set<String> get selection => _selection;
  EditorTool get tool => _tool;
  RotationSnap get rotationSnap => _rotationSnap;
  bool get snapToGrid => _snapToGrid;
  bool get showGrid => _showGrid;
  bool get showTags => _showTags;

  /// True when the layout has changes that are not yet saved.
  bool get isDirty => _dirty;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<Desk> get selectedDesks => layout.desks
      .where((d) => _selection.contains(d.id))
      .toList(growable: false);

  /// The single selected desk, or null when zero or many are selected.
  Desk? get soleSelection =>
      _selection.length == 1 ? layout.deskById(_selection.first) : null;

  List<Student> get roster => _workspace.rosterFor(_classSectionId);

  /// Roster students who do not currently have a seat.
  List<Student> get unseatedStudents {
    final seated = seating.values.toSet();
    return roster.where((s) => !seated.contains(s.id)).toList(growable: false);
  }

  Student? studentAt(String deskId) {
    final id = seating[deskId];
    return id == null ? null : _workspace.student(id);
  }

  bool isPinned(String deskId) => _snapshot.pinnedSeats.contains(deskId);

  // --- View options --------------------------------------------------------

  void setTool(EditorTool tool) {
    if (_tool == tool) return;
    _tool = tool;
    notifyListeners();
  }

  void setRotationSnap(RotationSnap snap) {
    if (_rotationSnap == snap) return;
    _rotationSnap = snap;
    notifyListeners();
  }

  void setSnapToGrid(bool value) {
    if (_snapToGrid == value) return;
    _snapToGrid = value;
    notifyListeners();
  }

  void setShowGrid(bool value) {
    if (_showGrid == value) return;
    _showGrid = value;
    notifyListeners();
  }

  void setShowTags(bool value) {
    if (_showTags == value) return;
    _showTags = value;
    notifyListeners();
  }

  // --- Selection -----------------------------------------------------------
  //
  // Selection is deliberately outside the undo stack: undoing a move should
  // restore desk positions, not a past selection.

  void selectOnly(String deskId) => _setSelection({deskId});

  void toggleSelection(String deskId) => _setSelection(
    _selection.contains(deskId)
        ? (_selection.toSet()..remove(deskId))
        : (_selection.toSet()..add(deskId)),
  );

  void addToSelection(Iterable<String> deskIds) =>
      _setSelection(_selection.toSet()..addAll(deskIds));

  void clearSelection() => _setSelection(const <String>{});

  void selectAllSeats() => _setSelection(layout.seats.map((d) => d.id).toSet());

  /// Selects every desk in the same group as [deskId], which is how a teacher
  /// grabs a whole pod to move or rotate it.
  void selectGroupOf(String deskId) {
    final group = layout.groupForDesk(deskId);
    if (group == null) {
      selectOnly(deskId);
      return;
    }
    _setSelection(group.deskIds.toSet());
  }

  /// Marquee selection. [rect] is in room coordinates and desks are tested by
  /// their rotated bounds, so a tilted desk still gets caught.
  void selectInRect(Rect rect, {bool additive = false}) {
    final hits = layout.desks
        .where((d) => d.bounds.overlaps(rect))
        .map((d) => d.id);
    _setSelection(additive ? (_selection.toSet()..addAll(hits)) : hits.toSet());
  }

  /// Topmost desk under a room-space point, preferring later desks so
  /// recently added items win overlaps.
  Desk? deskAt(Offset roomPoint, {double padding = 0}) => layout.desks.reversed
      .firstWhereOrNull((d) => d.containsPoint(roomPoint, padding: padding));

  void _setSelection(Set<String> next) {
    if (setEquals(_selection, next)) return;
    _selection = next;
    notifyListeners();
  }

  // --- History -------------------------------------------------------------

  /// Marks the start of a continuous gesture so it collapses to one undo step.
  void beginInteraction() => _interactionBaseline ??= _snapshot;

  /// Ends a gesture, pushing one history entry if anything actually changed.
  void endInteraction() {
    final baseline = _interactionBaseline;
    _interactionBaseline = null;
    if (baseline == null || identical(baseline, _snapshot)) return;
    _pushHistory(baseline);
    _publishLayout();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot);
    _snapshot = _undo.removeLast();
    _pruneSelection();
    _dirty = true;
    _publishLayout();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot);
    _snapshot = _redo.removeLast();
    _pruneSelection();
    _dirty = true;
    _publishLayout();
    notifyListeners();
  }

  /// Applies a change. During an interaction the change is folded into the
  /// gesture instead of becoming its own history entry.
  void _apply(EditorSnapshot next) {
    if (_interactionBaseline == null) {
      _pushHistory(_snapshot);
    }
    _snapshot = next.pruned();
    _dirty = true;
    _pruneSelection();
    _publishLayout();
    notifyListeners();
  }

  /// Pushes room changes to the workspace, which persists them on a debounce.
  ///
  /// Moving a desk is not a thing a teacher should have to remember to save,
  /// so the room autosaves. Seating arrangements stay explicit, because those
  /// are named snapshots in the history rather than ambient state.
  ///
  /// Writes are held back until a gesture finishes, so a drag notifies the
  /// workspace once instead of once per frame.
  void _publishLayout() {
    if (_interactionBaseline != null) return;
    if (identical(layout, _syncedLayout)) return;
    _syncedLayout = layout;
    _workspace.upsertLayout(layout);
  }

  void _pushHistory(EditorSnapshot entry) {
    _undo.add(entry);
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void _pruneSelection() {
    final ids = layout.desks.map((d) => d.id).toSet();
    final next = _selection.where(ids.contains).toSet();
    if (next.length != _selection.length) _selection = next;
  }

  /// Replaces the desk list, keeping everything else intact.
  void _withDesks(List<Desk> desks) =>
      _apply(_snapshot.copyWith(layout: layout.copyWith(desks: desks)));

  /// Folds a transformed selection back into the full desk list.
  List<Desk> _merge(List<Desk> transformed) {
    final byId = {for (final d in transformed) d.id: d};
    return [for (final d in layout.desks) byId[d.id] ?? d];
  }

  // --- Desk editing --------------------------------------------------------

  /// Adds a desk at a room-space point, snapping and clamping to the room.
  Desk addDesk(Offset position, {DeskKind kind = DeskKind.student}) {
    final snapped = _snapToGrid
        ? LayoutOps.snapPoint(position, layout.gridSize)
        : position;
    final (width, height, shape) = switch (kind) {
      DeskKind.student => (60.0, 45.0, DeskShape.rounded),
      DeskKind.table => (120.0, 120.0, DeskShape.circle),
      DeskKind.teacher => (140.0, 70.0, DeskShape.rounded),
      DeskKind.whiteboard => (300.0, 20.0, DeskShape.rectangle),
      DeskKind.door => (20.0, 90.0, DeskShape.rectangle),
      DeskKind.storage => (150.0, 45.0, DeskShape.rectangle),
      DeskKind.rug => (180.0, 140.0, DeskShape.rounded),
    };
    final desk = LayoutOps.clampToRoom(
      Desk.create(
        x: snapped.dx,
        y: snapped.dy,
        kind: kind,
        shape: shape,
        width: width,
        height: height,
        label: kind.isSeat ? '' : kind.label,
      ),
      layout.roomWidth,
      layout.roomHeight,
    );
    _withDesks([...layout.desks, desk]);
    selectOnly(desk.id);
    return desk;
  }

  /// Moves the selection by a room-space delta.
  ///
  /// Snapping is applied to the *anchor* desk and the same correction is
  /// applied to the rest, so a multi-desk drag keeps its internal spacing.
  void moveSelectionBy(Offset delta, {String? anchorDeskId}) {
    if (_selection.isEmpty || delta == Offset.zero) return;
    var applied = delta;

    if (_snapToGrid && layout.gridSize > 0) {
      final anchor = layout.deskById(anchorDeskId ?? _selection.first);
      if (anchor != null) {
        final target = anchor.center + delta;
        applied = LayoutOps.snapPoint(target, layout.gridSize) - anchor.center;
      }
    }

    final moved = [
      for (final d in selectedDesks)
        if (d.locked)
          d
        else
          LayoutOps.clampToRoom(
            d.movedBy(applied),
            layout.roomWidth,
            layout.roomHeight,
          ),
    ];
    _withDesks(_merge(moved));
  }

  /// Moves the selection so the anchor desk's center lands on [target].
  ///
  /// Positions are measured from the snapshot captured by [beginInteraction],
  /// not from the previous frame, so snapping cannot accumulate drift over a
  /// long drag.
  void dragSelectionTo(String anchorDeskId, Offset target) {
    final baseline = _interactionBaseline ?? _snapshot;
    final anchorStart = baseline.layout.deskById(anchorDeskId);
    if (anchorStart == null) return;

    final resolved = _snapToGrid && layout.gridSize > 0
        ? LayoutOps.snapPoint(target, layout.gridSize)
        : target;
    final delta = resolved - anchorStart.center;
    if (delta == Offset.zero) return;

    final moved = <Desk>[];
    for (final id in _selection) {
      final start = baseline.layout.deskById(id);
      final live = layout.deskById(id);
      if (start == null || live == null || live.locked) continue;
      moved.add(
        LayoutOps.clampToRoom(
          live.copyWith(x: start.x + delta.dx, y: start.y + delta.dy),
          layout.roomWidth,
          layout.roomHeight,
        ),
      );
    }
    if (moved.isEmpty) return;
    _withDesks(_merge(moved));
  }

  /// Nudges the selection, for arrow-key adjustment after a shuffle.
  void nudgeSelection(Offset direction) {
    final step = _snapToGrid && layout.gridSize > 0 ? layout.gridSize : 5.0;
    beginInteraction();
    moveSelectionBy(direction * step);
    endInteraction();
  }

  void setDeskRotation(String deskId, double degrees, {bool snap = true}) {
    final desk = layout.deskById(deskId);
    if (desk == null || desk.locked) return;
    final value = snap
        ? _rotationSnap.apply(degrees)
        : Desk.normalizeRotation(degrees);
    _withDesks(_merge([desk.copyWith(rotation: value)]));
  }

  /// Sets the same rotation on every selected desk — "face all of these the
  /// same way".
  void setSelectionRotation(double degrees) {
    if (_selection.isEmpty) return;
    final value = _rotationSnap.apply(degrees);
    _withDesks(
      _merge([for (final d in selectedDesks) d.copyWith(rotation: value)]),
    );
  }

  /// Rotates the selection around its shared centroid, keeping a pod intact.
  void rotateSelectionBy(double degrees) {
    if (_selection.isEmpty) return;
    _withDesks(_merge(LayoutOps.rotateSelection(selectedDesks, degrees)));
  }

  void resizeDesk(String deskId, {double? width, double? height}) {
    final desk = layout.deskById(deskId);
    if (desk == null) return;
    _withDesks(
      _merge([
        desk.copyWith(
          width: width == null ? null : math.max(20, width),
          height: height == null ? null : math.max(20, height),
        ),
      ]),
    );
  }

  void setDeskShape(String deskId, DeskShape shape) {
    final desk = layout.deskById(deskId);
    if (desk == null) return;
    _withDesks(_merge([desk.copyWith(shape: shape)]));
  }

  void setDeskLabel(String deskId, String label) {
    final desk = layout.deskById(deskId);
    if (desk == null) return;
    _withDesks(_merge([desk.copyWith(label: label)]));
  }

  void toggleDeskLocked(String deskId) {
    final desk = layout.deskById(deskId);
    if (desk == null) return;
    _withDesks(_merge([desk.copyWith(locked: !desk.locked)]));
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    final removed = _selection;
    _apply(
      _snapshot.copyWith(
        layout: layout.copyWith(
          desks: layout.desks
              .where((d) => !removed.contains(d.id))
              .toList(growable: false),
          groups: [
            for (final g in layout.groups)
              g.copyWith(
                deskIds: g.deskIds
                    .where((id) => !removed.contains(id))
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
    clearSelection();
  }

  /// Duplicates the selection, offset slightly so the copies are visible.
  void duplicateSelection({Offset offset = const Offset(40, 40)}) {
    if (_selection.isEmpty) return;
    final copies = [
      for (final d in selectedDesks)
        Desk(
          id: newId(),
          x: d.x + offset.dx,
          y: d.y + offset.dy,
          kind: d.kind,
          shape: d.shape,
          width: d.width,
          height: d.height,
          rotation: d.rotation,
          label: d.label,
        ),
    ];
    _withDesks([...layout.desks, ...copies]);
    _setSelection(copies.map((d) => d.id).toSet());
  }

  // --- Arrangement helpers -------------------------------------------------

  void alignSelection(AlignEdge edge) {
    if (_selection.length < 2) return;
    _withDesks(_merge(LayoutOps.alignDesks(selectedDesks, edge)));
  }

  void distributeSelection(SpreadAxis axis) {
    if (_selection.length < 3) return;
    _withDesks(_merge(LayoutOps.distributeEvenly(selectedDesks, axis)));
  }

  void spaceSelection(SpreadAxis axis, double gap) {
    if (_selection.length < 2) return;
    _withDesks(_merge(LayoutOps.spaceWithGap(selectedDesks, axis, gap)));
  }

  void clusterSelection({double gap = 10}) {
    if (_selection.length < 2) return;
    _withDesks(_merge(LayoutOps.clusterTogether(selectedDesks, gap: gap)));
  }

  /// Arranges the selection into a Kagan-style pod facing inward.
  void podSelection() {
    if (_selection.length < 2) return;
    _withDesks(_merge(LayoutOps.arrangeAsPod(selectedDesks)));
  }

  /// Resizes the room. Desks outside the new walls are pulled back inside so
  /// shrinking a room can never lose a desk off the edge.
  void setRoomSize({double? width, double? height}) {
    final w = math.max(200.0, width ?? layout.roomWidth);
    final h = math.max(200.0, height ?? layout.roomHeight);
    if (w == layout.roomWidth && h == layout.roomHeight) return;
    _apply(
      _snapshot.copyWith(
        layout: layout.copyWith(
          roomWidth: w,
          roomHeight: h,
          desks: [for (final d in layout.desks) LayoutOps.clampToRoom(d, w, h)],
        ),
      ),
    );
  }

  void setGridSize(double value) {
    if (value == layout.gridSize) return;
    _apply(_snapshot.copyWith(layout: layout.copyWith(gridSize: value)));
  }

  void renameLayout(String name) {
    if (name.isEmpty || name == layout.name) return;
    _apply(_snapshot.copyWith(layout: layout.copyWith(name: name)));
  }

  // --- Groups --------------------------------------------------------------

  /// Names the current selection as a group, e.g. "Group 3".
  DeskGroup? groupSelection({String? name, bool asKaganTeam = true}) {
    if (_selection.length < 2) return null;
    final ids = layout.desks
        .where((d) => _selection.contains(d.id) && d.isSeat)
        .map((d) => d.id)
        .toList(growable: false);
    if (ids.length < 2) return null;

    final group = DeskGroup.create(
      name: name ?? layout.nextGroupName(),
      deskIds: ids,
      colorValue: layout.nextGroupColor(),
      isKaganTeam: asKaganTeam,
    );

    _apply(
      _snapshot.copyWith(
        layout: layout.copyWith(
          groups: [
            // A desk belongs to one group; drop it from any previous group.
            for (final g in layout.groups)
              g.copyWith(
                deskIds: g.deskIds
                    .where((id) => !ids.contains(id))
                    .toList(growable: false),
              ),
            group,
          ].where((g) => g.deskIds.isNotEmpty).toList(growable: false),
          desks: _merge([
            for (final d in layout.desks.where((d) => ids.contains(d.id)))
              d.copyWith(groupId: group.id),
          ]),
        ),
      ),
    );
    return group;
  }

  void ungroupSelection() {
    if (_selection.isEmpty) return;
    final ids = _selection;
    _apply(
      _snapshot.copyWith(
        layout: layout.copyWith(
          groups: [
            for (final g in layout.groups)
              g.copyWith(
                deskIds: g.deskIds
                    .where((id) => !ids.contains(id))
                    .toList(growable: false),
              ),
          ].where((g) => g.deskIds.isNotEmpty).toList(growable: false),
          desks: _merge([
            for (final d in selectedDesks) d.copyWith(clearGroup: true),
          ]),
        ),
      ),
    );
  }

  void renameGroup(String groupId, String name) {
    final group = layout.groupById(groupId);
    if (group == null) return;
    _apply(
      _snapshot.copyWith(
        layout: layout.copyWith(
          groups: [
            for (final g in layout.groups)
              if (g.id == groupId) g.copyWith(name: name) else g,
          ],
        ),
      ),
    );
  }

  void setGroupColor(String groupId, int colorValue) {
    final group = layout.groupById(groupId);
    if (group == null) return;
    _apply(
      _snapshot.copyWith(
        layout: layout.copyWith(
          groups: [
            for (final g in layout.groups)
              if (g.id == groupId) g.copyWith(colorValue: colorValue) else g,
          ],
        ),
      ),
    );
  }

  // --- Seating -------------------------------------------------------------

  /// Seats a student, vacating whatever seat they held before so a student
  /// can never appear twice in the room.
  void assignStudent(String deskId, String studentId) {
    final desk = layout.deskById(deskId);
    if (desk == null || !desk.isSeat) return;
    final next = Map<String, String>.from(seating)
      ..removeWhere((_, value) => value == studentId)
      ..[deskId] = studentId;
    _apply(_snapshot.copyWith(seatToStudent: next));
  }

  void clearSeat(String deskId) {
    if (!seating.containsKey(deskId)) return;
    _apply(
      _snapshot.copyWith(
        seatToStudent: Map<String, String>.from(seating)..remove(deskId),
      ),
    );
  }

  void clearAllSeats() {
    if (seating.isEmpty) return;
    _apply(_snapshot.copyWith(seatToStudent: const <String, String>{}));
  }

  /// Swaps two students, which is the common manual fix after a shuffle.
  void swapSeats(String deskA, String deskB) {
    _apply(
      _snapshot.copyWith(
        seatToStudent: SeatingOps.swapSeats(seating, deskA, deskB),
      ),
    );
  }

  /// Pins a seat so shuffles leave its student in place.
  void togglePinned(String deskId) {
    final next = _snapshot.pinnedSeats.toSet();
    if (!next.remove(deskId)) next.add(deskId);
    _apply(_snapshot.copyWith(pinnedSeats: next));
  }

  /// Randomly reseats the class, honoring pinned seats. Returns the seed so
  /// the caller can record it with the saved assignment.
  ShuffleResult shuffleSeating({int? seed}) {
    final result = SeatingOps.shuffle(
      layout: layout,
      students: roster,
      current: seating,
      lockedDeskIds: _snapshot.pinnedSeats,
      tagsById: _workspace.tagsById,
      seed: seed,
    );
    _apply(_snapshot.copyWith(seatToStudent: result.seatToStudent));
    _lastSeed = result.seed;
    return result;
  }

  /// Rotates whole teams between pods, the usual way Kagan teams are changed.
  void rotateGroups({int? seed}) {
    if (layout.groups.length < 2) return;
    _apply(
      _snapshot.copyWith(
        seatToStudent: SeatingOps.rotateGroups(
          layout: layout,
          current: seating,
          seed: seed,
        ),
      ),
    );
  }

  int? _lastSeed;

  /// Loads a past arrangement from the history back onto the current layout.
  void applyAssignment(SeatingAssignment assignment) {
    _apply(
      _snapshot.copyWith(
        seatToStudent: Map<String, String>.from(assignment.seatToStudent),
        pinnedSeats: assignment.lockedDeskIds.toSet(),
      ),
    );
    _lastSeed = assignment.seed;
  }

  // --- Persistence ---------------------------------------------------------

  /// Saves the room arrangement (desks and groups) to the workspace.
  void saveLayout({String? name}) {
    final updated = layout.copyWith(name: name, updatedAt: DateTime.now());
    _snapshot = _snapshot.copyWith(layout: updated);
    _syncedLayout = updated;
    _workspace.upsertLayout(updated);
    _dirty = false;
    notifyListeners();
  }

  /// Appends the current seating to the history as a new immutable record.
  SeatingAssignment saveAssignment({
    String name = '',
    AssignmentSource source = AssignmentSource.manual,
  }) {
    saveLayout();
    final assignment = SeatingAssignment.create(
      layoutId: layout.id,
      classSectionId: _classSectionId,
      seatToStudent: Map<String, String>.from(seating),
      name: name,
      source: source,
      seed: source == AssignmentSource.shuffle ? _lastSeed : null,
      lockedDeskIds: _snapshot.pinnedSeats.toSet(),
    );
    _workspace.saveAssignment(assignment);
    return assignment;
  }

  /// Saves the current room as a brand new layout, leaving the original as it
  /// was — "save as" for seating charts.
  RoomLayout saveAsNewLayout(String name) {
    final copy = layout.duplicate(name: name);
    // Remap seating onto the duplicated desk ids by position in the desk list.
    final oldIds = layout.desks.map((d) => d.id).toList(growable: false);
    final newIds = copy.desks.map((d) => d.id).toList(growable: false);
    final remap = <String, String>{
      for (var i = 0; i < oldIds.length && i < newIds.length; i++)
        oldIds[i]: newIds[i],
    };
    _workspace.addLayoutToClass(copy, _classSectionId);
    _snapshot = EditorSnapshot(
      layout: copy,
      seatToStudent: {
        for (final e in seating.entries)
          if (remap[e.key] != null) remap[e.key]!: e.value,
      },
      pinnedSeats: _snapshot.pinnedSeats
          .map((id) => remap[id])
          .whereType<String>()
          .toSet(),
    );
    _syncedLayout = copy;
    _undo.clear();
    _redo.clear();
    _dirty = false;
    clearSelection();
    notifyListeners();
    return copy;
  }
}
