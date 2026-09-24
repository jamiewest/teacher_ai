import 'package:collection/collection.dart';

import '../../domain/models/models.dart';

/// One undoable moment in the seating editor.
///
/// The layout, the seating map, and the pinned seats travel together because
/// a single action can touch all three — deleting a desk removes its student
/// and its pin as well. Snapshots are immutable, so undo is a stack of these
/// rather than a pile of inverse operations.
class EditorSnapshot {
  const EditorSnapshot({
    required this.layout,
    this.seatToStudent = const <String, String>{},
    this.pinnedSeats = const <String>{},
  });

  final RoomLayout layout;

  /// Desk id -> student id for the arrangement being edited.
  final Map<String, String> seatToStudent;

  /// Seats the teacher pinned so a shuffle leaves them alone.
  final Set<String> pinnedSeats;

  EditorSnapshot copyWith({
    RoomLayout? layout,
    Map<String, String>? seatToStudent,
    Set<String>? pinnedSeats,
  }) => EditorSnapshot(
    layout: layout ?? this.layout,
    seatToStudent: seatToStudent ?? this.seatToStudent,
    pinnedSeats: pinnedSeats ?? this.pinnedSeats,
  );

  /// Drops references to desks that no longer exist.
  EditorSnapshot pruned() {
    final ids = layout.desks.map((d) => d.id).toSet();
    return copyWith(
      seatToStudent: {
        for (final e in seatToStudent.entries)
          if (ids.contains(e.key)) e.key: e.value,
      },
      pinnedSeats: pinnedSeats.where(ids.contains).toSet(),
    );
  }

  String? studentAt(String deskId) => seatToStudent[deskId];

  String? deskForStudent(String studentId) =>
      seatToStudent.entries.firstWhereOrNull((e) => e.value == studentId)?.key;
}

/// Seating protects the room geometry; design exposes furniture tools.
enum EditorMode { seating, design }

/// What a press on the canvas does.
///
/// A pointer-only device can lean on modifier keys, but a touch device cannot,
/// so the tool is an explicit, visible mode rather than an invisible one.
enum EditorTool {
  select('Select', 'Drag desks, drag empty space to marquee-select'),
  addDesk('Add', 'Tap the room to place a desk'),
  pan('Pan', 'Drag to move around the room');

  const EditorTool(this.label, this.hint);
  final String label;
  final String hint;
}
