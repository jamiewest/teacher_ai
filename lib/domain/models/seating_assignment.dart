import '../../common/ids.dart';

/// How a seating arrangement came to exist.
enum AssignmentSource {
  manual('Manual'),
  shuffle('Shuffled'),
  imported('Imported'),
  ai('AI suggested');

  const AssignmentSource(this.label);
  final String label;

  static AssignmentSource fromJson(String value) =>
      AssignmentSource.values.firstWhere(
        (s) => s.name == value,
        orElse: () => AssignmentSource.manual,
      );

  String toJson() => name;
}

/// Who sits where, for one layout and one class, at one point in time.
///
/// Assignments are immutable snapshots. Saving a new arrangement appends to
/// the history rather than overwriting, so a teacher can look back at "the
/// week Jordan sat by the window" — and so a future AI has real examples of
/// what the teacher accepted or changed.
class SeatingAssignment {
  const SeatingAssignment({
    required this.id,
    required this.layoutId,
    required this.classSectionId,
    required this.createdAt,
    required this.seatToStudent,
    this.name = '',
    this.source = AssignmentSource.manual,
    this.seed,
    this.lockedDeskIds = const <String>{},
    this.notes = '',
  });

  factory SeatingAssignment.create({
    required String layoutId,
    required String classSectionId,
    required Map<String, String> seatToStudent,
    String name = '',
    AssignmentSource source = AssignmentSource.manual,
    int? seed,
    Set<String> lockedDeskIds = const <String>{},
    String notes = '',
  }) => SeatingAssignment(
    id: newId(),
    layoutId: layoutId,
    classSectionId: classSectionId,
    createdAt: DateTime.now(),
    seatToStudent: Map.unmodifiable(seatToStudent),
    name: name,
    source: source,
    seed: seed,
    lockedDeskIds: lockedDeskIds,
    notes: notes,
  );

  final String id;
  final String layoutId;
  final String classSectionId;
  final DateTime createdAt;

  /// Desk id -> student id. A desk absent from the map is empty.
  final Map<String, String> seatToStudent;

  /// Optional label, e.g. "Unit 3 test" or "Week of Sep 22".
  final String name;
  final AssignmentSource source;

  /// The RNG seed used when [source] is [AssignmentSource.shuffle], so the
  /// exact arrangement can be reproduced or explained later.
  final int? seed;

  /// Desks the teacher pinned before shuffling; these kept their student.
  final Set<String> lockedDeskIds;
  final String notes;

  int get seatedCount => seatToStudent.length;

  /// Desk the student is sitting at, or null if unseated.
  String? deskForStudent(String studentId) {
    for (final entry in seatToStudent.entries) {
      if (entry.value == studentId) return entry.key;
    }
    return null;
  }

  String? studentAt(String deskId) => seatToStudent[deskId];

  /// Students on the roster who did not get a seat in this arrangement.
  List<String> unseatedStudents(Iterable<String> rosterIds) {
    final seated = seatToStudent.values.toSet();
    return rosterIds.where((id) => !seated.contains(id)).toList(growable: false);
  }

  /// A display name for history lists, falling back to the timestamp.
  String displayName() {
    if (name.isNotEmpty) return name;
    final d = createdAt;
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final suffix = d.hour < 12 ? 'AM' : 'PM';
    return '${d.month}/${d.day} '
        '$hour:${d.minute.toString().padLeft(2, '0')} $suffix';
  }

  SeatingAssignment copyWith({
    Map<String, String>? seatToStudent,
    String? name,
    AssignmentSource? source,
    int? seed,
    Set<String>? lockedDeskIds,
    String? notes,
  }) => SeatingAssignment(
    id: id,
    layoutId: layoutId,
    classSectionId: classSectionId,
    createdAt: createdAt,
    seatToStudent: seatToStudent ?? this.seatToStudent,
    name: name ?? this.name,
    source: source ?? this.source,
    seed: seed ?? this.seed,
    lockedDeskIds: lockedDeskIds ?? this.lockedDeskIds,
    notes: notes ?? this.notes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'layoutId': layoutId,
    'classSectionId': classSectionId,
    'createdAt': createdAt.toIso8601String(),
    'seatToStudent': seatToStudent,
    'name': name,
    'source': source.toJson(),
    'seed': seed,
    'lockedDeskIds': lockedDeskIds.toList(growable: false),
    'notes': notes,
  };

  factory SeatingAssignment.fromJson(Map<String, Object?> json) =>
      SeatingAssignment(
        id: json['id']! as String,
        layoutId: json['layoutId'] as String? ?? '',
        classSectionId: json['classSectionId'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        seatToStudent: <String, String>{
          for (final e
              in (json['seatToStudent'] as Map<Object?, Object?>? ??
                      const <Object?, Object?>{})
                  .entries)
            e.key! as String: e.value! as String,
        },
        name: json['name'] as String? ?? '',
        source: AssignmentSource.fromJson(json['source'] as String? ?? 'manual'),
        seed: (json['seed'] as num?)?.toInt(),
        lockedDeskIds: (json['lockedDeskIds'] as List<Object?>? ?? const [])
            .map((e) => e! as String)
            .toSet(),
        notes: json['notes'] as String? ?? '',
      );
}
