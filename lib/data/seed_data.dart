import 'dart:ui' show Offset;

import '../domain/models/models.dart';
import '../domain/ops/layout_ops.dart';
import 'workspace_document.dart';

/// First-run content so the app opens on a real classroom instead of an empty
/// grid. Math is the focus for now, so the seeded section is a math class.
WorkspaceDocument buildSeedWorkspace() {
  final algebra = Subject.create(
    name: 'Algebra I',
    colorValue: 0xFF3B6EA5,
  );
  final math6 = Subject.create(name: '6th Grade Math', colorValue: 0xFF4C8C7B);

  final tags = <StudentTag>[
    StudentTag.create(
      label: 'Talks a lot',
      category: TagCategory.behavior,
      hint: SeatingHint.separateFromSameTag,
      description: 'Chats with neighbours; do not seat next to another talker.',
      colorValue: 0xFFB4713D,
    ),
    StudentTag.create(
      label: 'Needs extra help',
      category: TagCategory.academic,
      hint: SeatingHint.nearTeacher,
      description: 'Benefits from being within easy reach for check-ins.',
      colorValue: 0xFF8B5FA8,
    ),
    StudentTag.create(
      label: 'Front row (vision)',
      category: TagCategory.accessibility,
      hint: SeatingHint.frontOfRoom,
      description: 'Needs a clear line of sight to the board.',
      colorValue: 0xFF3F7D4C,
    ),
    StudentTag.create(
      label: 'Peer helper',
      category: TagCategory.social,
      hint: SeatingHint.anchorsGroup,
      description: 'Strong with math talk; good anchor for a Kagan team.',
      colorValue: 0xFF3B6EA5,
    ),
    StudentTag.create(
      label: 'ELL support',
      category: TagCategory.language,
      hint: SeatingHint.needsPartner,
      description: 'Pair with a bilingual or patient partner.',
      colorValue: 0xFF5C6BC0,
    ),
    StudentTag.create(
      label: 'Easily distracted',
      category: TagCategory.behavior,
      hint: SeatingHint.lowDistraction,
      description: 'Keep away from the door and the pencil sharpener.',
      colorValue: 0xFFA8495C,
    ),
  ];

  final talksALot = tags[0].id;
  final needsHelp = tags[1].id;
  final frontRow = tags[2].id;
  final peerHelper = tags[3].id;
  final ell = tags[4].id;
  final distracted = tags[5].id;

  const names = <(String, String)>[
    ('Ava', 'Mitchell'),
    ('Noah', 'Barrett'),
    ('Sofia', 'Delgado'),
    ('Liam', 'Okafor'),
    ('Maya', 'Chen'),
    ('Elijah', 'Novak'),
    ('Harper', 'Quinn'),
    ('Mateo', 'Rivas'),
    ('Zoe', 'Abernathy'),
    ('Caleb', 'Thornton'),
    ('Priya', 'Raman'),
    ('Owen', 'Castellano'),
    ('Isla', 'Fitzgerald'),
    ('Jonah', 'Weiss'),
    ('Amara', 'Boateng'),
    ('Lucas', 'Petrov'),
    ('Nora', 'Lindqvist'),
    ('Diego', 'Salazar'),
    ('Ruby', 'Hargrove'),
    ('Kian', 'Farhadi'),
    ('Talia', 'Brennan'),
    ('Marcus', 'Whitfield'),
    ('Yuki', 'Tanaka'),
    ('Simone', 'Adeyemi'),
  ];

  // A single math section can mix grades when students accelerate or repeat,
  // so the seeded roster deliberately spans three grade levels.
  const grades = <GradeLevel>[
    GradeLevel.grade6,
    GradeLevel.grade6,
    GradeLevel.grade7,
    GradeLevel.grade6,
    GradeLevel.grade7,
    GradeLevel.grade6,
    GradeLevel.grade6,
    GradeLevel.grade7,
    GradeLevel.grade8,
    GradeLevel.grade6,
    GradeLevel.grade7,
    GradeLevel.grade6,
    GradeLevel.grade6,
    GradeLevel.grade7,
    GradeLevel.grade6,
    GradeLevel.grade8,
    GradeLevel.grade6,
    GradeLevel.grade7,
    GradeLevel.grade6,
    GradeLevel.grade6,
    GradeLevel.grade7,
    GradeLevel.grade6,
    GradeLevel.grade6,
    GradeLevel.grade7,
  ];

  const tagPlan = <int, List<int>>{
    0: [3],
    1: [0],
    3: [1, 4],
    4: [3],
    6: [0, 5],
    7: [1],
    9: [5],
    10: [3],
    12: [2],
    14: [4],
    15: [0],
    17: [1, 4],
    19: [5],
    20: [3],
    22: [2],
  };
  final tagIdsByIndex = <int, List<String>>{
    for (final entry in tagPlan.entries)
      entry.key: [
        for (final i in entry.value)
          [talksALot, needsHelp, frontRow, peerHelper, ell, distracted][i],
      ],
  };

  final students = <Student>[
    for (var i = 0; i < names.length; i++)
      Student.create(
        firstName: names[i].$1,
        lastName: names[i].$2,
        gradeLevel: grades[i],
        tagIds: tagIdsByIndex[i] ?? const <String>[],
      ),
  ];

  final section = ClassSection.create(
    name: 'Period 2 — Algebra I',
    subjectId: algebra.id,
    studentIds: students.map((s) => s.id).toList(growable: false),
    roomName: 'Room 214',
  );

  final rowsLayout = _buildRowsLayout(section.id);
  final podsLayout = _buildPodsLayout(section.id);

  final periods = <SchedulePeriod>[
    SchedulePeriod.create(
      name: 'Period 1 — 6th Grade Math',
      kind: PeriodKind.classTime,
      start: const TimeOfDayMinutes.at(8, 0),
      end: const TimeOfDayMinutes.at(8, 50),
    ),
    SchedulePeriod.create(
      name: 'Passing',
      kind: PeriodKind.passing,
      start: const TimeOfDayMinutes.at(8, 50),
      end: const TimeOfDayMinutes.at(8, 55),
    ),
    SchedulePeriod.create(
      name: 'Period 2 — Algebra I',
      kind: PeriodKind.classTime,
      start: const TimeOfDayMinutes.at(8, 55),
      end: const TimeOfDayMinutes.at(9, 45),
      classSectionId: section.id,
    ),
    SchedulePeriod.create(
      name: 'Passing',
      kind: PeriodKind.passing,
      start: const TimeOfDayMinutes.at(9, 45),
      end: const TimeOfDayMinutes.at(9, 50),
    ),
    SchedulePeriod.create(
      name: 'Prep',
      kind: PeriodKind.prep,
      start: const TimeOfDayMinutes.at(9, 50),
      end: const TimeOfDayMinutes.at(10, 40),
    ),
    SchedulePeriod.create(
      name: 'Lunch',
      kind: PeriodKind.lunch,
      start: const TimeOfDayMinutes.at(11, 30),
      end: const TimeOfDayMinutes.at(12, 10),
    ),
  ];

  return WorkspaceDocument(
    subjects: [algebra, math6],
    students: students,
    tags: tags,
    classes: [
      section.copyWith(
        layoutIds: [rowsLayout.id, podsLayout.id],
        activeLayoutId: podsLayout.id,
      ),
    ],
    layouts: [rowsLayout, podsLayout],
    periods: periods,
  );
}

/// Classic five-across rows, plus the teacher desk and the board.
RoomLayout _buildRowsLayout(String sectionId) {
  final desks = LayoutOps.buildRows(
    rows: 5,
    columns: 5,
    origin: const Offset(180, 240),
    columnGap: 45,
    rowGap: 65,
  );
  return RoomLayout.create(
    name: 'Rows — test day',
    classSectionId: sectionId,
    desks: [...desks, ..._roomFurniture()],
    notes: 'Straight rows for independent work and assessments.',
  );
}

/// Six Kagan teams of four, each desk facing the middle of its pod.
RoomLayout _buildPodsLayout(String sectionId) {
  final desks = <Desk>[];
  final groups = <DeskGroup>[];

  const podOrigins = <Offset>[
    Offset(230, 260),
    Offset(470, 260),
    Offset(710, 260),
    Offset(230, 480),
    Offset(470, 480),
    Offset(710, 480),
  ];

  for (var i = 0; i < podOrigins.length; i++) {
    final seed = [
      for (var s = 0; s < 4; s++)
        Desk.create(x: podOrigins[i].dx, y: podOrigins[i].dy),
    ];
    final arranged = LayoutOps.arrangeAsPod(seed);
    final group = DeskGroup.create(
      name: 'Group ${i + 1}',
      deskIds: arranged.map((d) => d.id).toList(growable: false),
      colorValue: kGroupColors[i % kGroupColors.length],
      isKaganTeam: true,
    );
    desks.addAll(arranged.map((d) => d.copyWith(groupId: group.id)));
    groups.add(group);
  }

  return RoomLayout.create(
    name: 'Kagan pods',
    classSectionId: sectionId,
    desks: [...desks, ..._roomFurniture()],
    groups: groups,
    notes: 'Teams of four for Numbered Heads Together and Rally Coach.',
  );
}

/// Fixtures shared by both seeded layouts so the room reads as a real room.
List<Desk> _roomFurniture() => [
  Desk.create(
    x: 450,
    y: 60,
    kind: DeskKind.whiteboard,
    shape: DeskShape.rectangle,
    width: 400,
    height: 20,
    label: 'Whiteboard',
  ),
  Desk.create(
    x: 120,
    y: 120,
    kind: DeskKind.teacher,
    width: 140,
    height: 70,
    label: 'Teacher',
  ),
  Desk.create(
    x: 860,
    y: 120,
    kind: DeskKind.door,
    shape: DeskShape.rectangle,
    width: 20,
    height: 90,
    label: 'Door',
  ),
  Desk.create(
    x: 820,
    y: 640,
    kind: DeskKind.storage,
    shape: DeskShape.rectangle,
    width: 150,
    height: 45,
    label: 'Supplies',
  ),
];
