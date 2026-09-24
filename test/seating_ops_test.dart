import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/domain/models/models.dart';
import 'package:teacher_ai/domain/ops/seating_ops.dart';

RoomLayout layoutWithSeats(int count) => RoomLayout.create(
  name: 'Test',
  desks: [
    for (var i = 0; i < count; i++)
      Desk(id: 'seat$i', x: 100.0 + i * 80, y: 300),
    // A fixture must never be treated as a seat.
    Desk(id: 'board', x: 400, y: 50, kind: DeskKind.whiteboard),
  ],
);

List<Student> makeStudents(int count) => [
  for (var i = 0; i < count; i++)
    Student(
      id: 'student$i',
      firstName: 'Kid$i',
      lastName: 'L',
      gradeLevel: GradeLevel.grade6,
    ),
];

void main() {
  group('shuffle', () {
    test('seats everyone when there are enough seats', () {
      final result = SeatingOps.shuffle(
        layout: layoutWithSeats(6),
        students: makeStudents(6),
        seed: 42,
      );
      expect(result.seatToStudent, hasLength(6));
      expect(result.unseatedStudentIds, isEmpty);
      expect(result.seatToStudent.values.toSet(), hasLength(6));
    });

    test('never assigns a student to a fixture', () {
      final result = SeatingOps.shuffle(
        layout: layoutWithSeats(4),
        students: makeStudents(4),
        seed: 7,
      );
      expect(result.seatToStudent.keys, isNot(contains('board')));
    });

    test('is reproducible for a given seed', () {
      final layout = layoutWithSeats(8);
      final students = makeStudents(8);
      final a = SeatingOps.shuffle(layout: layout, students: students, seed: 99);
      final b = SeatingOps.shuffle(layout: layout, students: students, seed: 99);
      expect(a.seatToStudent, equals(b.seatToStudent));
    });

    test('reports students who could not be seated', () {
      final result = SeatingOps.shuffle(
        layout: layoutWithSeats(3),
        students: makeStudents(5),
        seed: 1,
      );
      expect(result.seatToStudent, hasLength(3));
      expect(result.unseatedStudentIds, hasLength(2));
    });

    test('pinned seats keep their student', () {
      final layout = layoutWithSeats(6);
      final students = makeStudents(6);
      const current = {'seat0': 'student3', 'seat1': 'student4'};

      final result = SeatingOps.shuffle(
        layout: layout,
        students: students,
        current: current,
        lockedDeskIds: {'seat0'},
        seed: 5,
      );

      expect(result.seatToStudent['seat0'], 'student3');
      // The pinned student must not also turn up somewhere else.
      expect(
        result.seatToStudent.values.where((id) => id == 'student3'),
        hasLength(1),
      );
      expect(result.seatToStudent.values.toSet(), hasLength(6));
    });

    test('a front-of-room tag pulls that student toward the board', () {
      final layout = RoomLayout.create(
        name: 'Rows',
        desks: [
          Desk(id: 'front', x: 450, y: 120),
          Desk(id: 'middle', x: 450, y: 350),
          Desk(id: 'back', x: 450, y: 600),
        ],
      );
      final tag = StudentTag(
        id: 'tag-front',
        label: 'Front row',
        hint: SeatingHint.frontOfRoom,
      );
      final students = [
        Student(
          id: 'needs-front',
          firstName: 'Ada',
          lastName: 'L',
          gradeLevel: GradeLevel.grade6,
          tagIds: const ['tag-front'],
        ),
        ...makeStudents(2),
      ];

      final result = SeatingOps.shuffle(
        layout: layout,
        students: students,
        tagsById: {tag.id: tag},
        seed: 3,
      );
      expect(result.seatToStudent['front'], 'needs-front');
    });
  });

  group('swapSeats', () {
    test('exchanges two seated students', () {
      const seating = {'a': 's1', 'b': 's2'};
      final result = SeatingOps.swapSeats(seating, 'a', 'b');
      expect(result['a'], 's2');
      expect(result['b'], 's1');
    });

    test('moving into an empty seat leaves the origin empty', () {
      const seating = {'a': 's1'};
      final result = SeatingOps.swapSeats(seating, 'a', 'b');
      expect(result.containsKey('a'), isFalse);
      expect(result['b'], 's1');
    });
  });

  test('rotateGroups moves whole teams and keeps every student', () {
    final layout = RoomLayout.create(
      name: 'Pods',
      desks: [
        Desk(id: 'a1', x: 0, y: 0),
        Desk(id: 'a2', x: 60, y: 0),
        Desk(id: 'b1', x: 300, y: 0),
        Desk(id: 'b2', x: 360, y: 0),
      ],
      groups: [
        DeskGroup(id: 'g1', name: 'Group 1', deskIds: const ['a1', 'a2']),
        DeskGroup(id: 'g2', name: 'Group 2', deskIds: const ['b1', 'b2']),
      ],
    );
    const seating = {'a1': 's1', 'a2': 's2', 'b1': 's3', 'b2': 's4'};

    final result = SeatingOps.rotateGroups(
      layout: layout,
      current: seating,
      seed: 11,
    );
    expect(result.values.toSet(), {'s1', 's2', 's3', 's4'});
    expect(result, hasLength(4));
  });
}
