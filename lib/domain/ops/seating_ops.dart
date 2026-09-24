import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/desk.dart';
import '../models/room_layout.dart';
import '../models/student.dart';
import '../models/student_tag.dart';

/// Result of a shuffle: the new seating map plus anyone who did not fit.
class ShuffleResult {
  const ShuffleResult({
    required this.seatToStudent,
    required this.seed,
    this.unseatedStudentIds = const <String>[],
  });

  final Map<String, String> seatToStudent;

  /// The seed that produced this arrangement. Stored on the saved assignment
  /// so the same shuffle can be reproduced or explained.
  final int seed;

  /// Students with no seat, because the layout has fewer seats than students.
  final List<String> unseatedStudentIds;
}

/// Deterministic seating placement.
///
/// These are plain rules, not AI: a seeded shuffle, locked seats, and a few
/// hints the teacher set explicitly on their own tags. The AI layer will
/// eventually propose arrangements through this same shape.
class SeatingOps {
  const SeatingOps._();

  /// Randomly assigns students to seats.
  ///
  /// Desks in [lockedDeskIds] — and desks whose [Desk.locked] flag is set —
  /// keep whoever is already sitting there, and those students are removed
  /// from the pool. Passing the same [seed] reproduces the same arrangement.
  static ShuffleResult shuffle({
    required RoomLayout layout,
    required List<Student> students,
    Map<String, String> current = const <String, String>{},
    Set<String> lockedDeskIds = const <String>{},
    Map<String, StudentTag> tagsById = const <String, StudentTag>{},
    bool respectTagHints = true,
    int? seed,
    Offset? frontOfRoom,
  }) {
    final actualSeed = seed ?? DateTime.now().microsecondsSinceEpoch;
    final random = math.Random(actualSeed);

    final seats = layout.seats;
    final locked = <String>{
      ...lockedDeskIds,
      ...seats.where((s) => s.locked).map((s) => s.id),
    };

    final result = <String, String>{};
    final placedStudents = <String>{};
    for (final deskId in locked) {
      final studentId = current[deskId];
      if (studentId != null) {
        result[deskId] = studentId;
        placedStudents.add(studentId);
      }
    }

    final openSeats = seats
        .where((s) => !result.containsKey(s.id))
        .toList(growable: true);
    final pool = students
        .where((s) => !placedStudents.contains(s.id))
        .toList(growable: true);

    // Fisher-Yates on both lists so seat order cannot bias the outcome.
    _shuffleInPlace(openSeats, random);
    _shuffleInPlace(pool, random);

    if (respectTagHints && tagsById.isNotEmpty) {
      _seatPriorityStudentsFirst(
        openSeats: openSeats,
        pool: pool,
        result: result,
        tagsById: tagsById,
        frontOfRoom: frontOfRoom ?? Offset(layout.roomWidth / 2, 0),
      );
    }

    final unseated = <String>[];
    for (final student in pool) {
      if (openSeats.isEmpty) {
        unseated.add(student.id);
        continue;
      }
      result[openSeats.removeLast().id] = student.id;
    }

    return ShuffleResult(
      seatToStudent: result,
      seed: actualSeed,
      unseatedStudentIds: unseated,
    );
  }

  /// Places students whose tags ask for a front seat before everyone else.
  ///
  /// Mutates [openSeats], [pool], and [result]; both lists arrive pre-shuffled
  /// so students with the same hint are still ordered randomly.
  static void _seatPriorityStudentsFirst({
    required List<Desk> openSeats,
    required List<Student> pool,
    required Map<String, String> result,
    required Map<String, StudentTag> tagsById,
    required Offset frontOfRoom,
  }) {
    bool wantsFront(Student s) => s.tagIds.any((id) {
      final hint = tagsById[id]?.hint;
      return hint == SeatingHint.frontOfRoom || hint == SeatingHint.nearTeacher;
    });

    final priority = pool.where(wantsFront).toList(growable: false);
    if (priority.isEmpty) return;

    // Nearest-to-front seats, so "seat near the front" means the same thing
    // whether the room is in rows or pods.
    openSeats.sort(
      (a, b) => (a.center - frontOfRoom).distanceSquared.compareTo(
        (b.center - frontOfRoom).distanceSquared,
      ),
    );

    for (final student in priority) {
      if (openSeats.isEmpty) break;
      result[openSeats.removeAt(0).id] = student.id;
      pool.remove(student);
    }
  }

  /// Rotates students between groups so nobody stays on the same team.
  ///
  /// Kagan teams are meant to change every few weeks; this keeps the layout
  /// intact and moves whole teams' worth of students at once.
  static Map<String, String> rotateGroups({
    required RoomLayout layout,
    required Map<String, String> current,
    int? seed,
  }) {
    final groups = layout.groups.where((g) => g.deskIds.isNotEmpty).toList();
    if (groups.length < 2) return current;

    final random = math.Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    final order = List<int>.generate(groups.length, (i) => i);
    _shuffleInPlace(order, random);

    final result = Map<String, String>.from(current);
    for (var i = 0; i < groups.length; i++) {
      final from = groups[i];
      final to = groups[order[i]];
      for (var seat = 0; seat < from.deskIds.length; seat++) {
        if (seat >= to.deskIds.length) break;
        final studentId = current[from.deskIds[seat]];
        if (studentId == null) {
          result.remove(to.deskIds[seat]);
        } else {
          result[to.deskIds[seat]] = studentId;
        }
      }
    }
    return result;
  }

  /// Swaps the students at two desks, handling the case where one is empty.
  static Map<String, String> swapSeats(
    Map<String, String> current,
    String deskA,
    String deskB,
  ) {
    if (deskA == deskB) return current;
    final result = Map<String, String>.from(current);
    final a = current[deskA];
    final b = current[deskB];
    if (b == null) {
      result.remove(deskA);
    } else {
      result[deskA] = b;
    }
    if (a == null) {
      result.remove(deskB);
    } else {
      result[deskB] = a;
    }
    return result;
  }

  static void _shuffleInPlace<T>(List<T> items, math.Random random) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }
}
