import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/models.dart';
import 'layout_ops.dart';

/// Room fixtures every preset starts with, so a new layout still reads as a
/// classroom: a board to face, a teacher desk, and a door.
List<Desk> defaultFixtures({
  double roomWidth = RoomLayout.defaultRoomWidth,
  double roomHeight = RoomLayout.defaultRoomHeight,
}) => [
  Desk.create(
    x: roomWidth / 2,
    y: 60,
    kind: DeskKind.whiteboard,
    shape: DeskShape.rectangle,
    width: roomWidth * 0.45,
    height: 20,
    label: 'Whiteboard',
  ),
  Desk.create(
    x: 120,
    y: 130,
    kind: DeskKind.teacher,
    width: 140,
    height: 70,
    label: 'Teacher',
  ),
  Desk.create(
    x: roomWidth - 45,
    y: 130,
    kind: DeskKind.door,
    shape: DeskShape.rectangle,
    width: 20,
    height: 90,
    label: 'Door',
  ),
];

/// Builds a starting arrangement.
///
/// Presets exist because an empty grid is a hard place to start; every one of
/// these is a shape teachers actually use, and all of them stay fully
/// editable afterwards.
RoomLayout buildPresetLayout({
  required String preset,
  required String name,
  String? classSectionId,
  double roomWidth = RoomLayout.defaultRoomWidth,
  double roomHeight = RoomLayout.defaultRoomHeight,
}) {
  final fixtures = defaultFixtures(
    roomWidth: roomWidth,
    roomHeight: roomHeight,
  );

  return switch (preset) {
    'rows' => RoomLayout.create(
      name: name,
      classSectionId: classSectionId,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
      desks: [
        ...LayoutOps.buildRows(
          rows: 5,
          columns: 5,
          origin: Offset(roomWidth / 2 - 2 * 105, 240),
          columnGap: 45,
          rowGap: 65,
        ),
        ...fixtures,
      ],
      notes: 'Straight rows for independent work and assessments.',
    ),
    'pods' => _pods(name, classSectionId, roomWidth, roomHeight, fixtures),
    'horseshoe' => _horseshoe(
      name,
      classSectionId,
      roomWidth,
      roomHeight,
      fixtures,
    ),
    _ => RoomLayout.create(
      name: name,
      classSectionId: classSectionId,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
      desks: fixtures,
    ),
  };
}

/// Six teams of four, each desk turned to face its pod's center.
RoomLayout _pods(
  String name,
  String? sectionId,
  double roomWidth,
  double roomHeight,
  List<Desk> fixtures,
) {
  final desks = <Desk>[];
  final groups = <DeskGroup>[];

  const columns = 3;
  const rows = 2;
  final spacingX = (roomWidth - 200) / columns;
  final spacingY = (roomHeight - 340) / rows;

  var index = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < columns; c++) {
      final center = Offset(
        150 + spacingX * c + spacingX / 2,
        260 + spacingY * r,
      );
      final seed = [
        for (var s = 0; s < 4; s++) Desk.create(x: center.dx, y: center.dy),
      ];
      final arranged = LayoutOps.arrangeAsPod(seed);
      final group = DeskGroup.create(
        name: 'Group ${index + 1}',
        deskIds: arranged.map((d) => d.id).toList(growable: false),
        colorValue: kGroupColors[index % kGroupColors.length],
        isKaganTeam: true,
      );
      desks.addAll(arranged.map((d) => d.copyWith(groupId: group.id)));
      groups.add(group);
      index++;
    }
  }

  return RoomLayout.create(
    name: name,
    classSectionId: sectionId,
    roomWidth: roomWidth,
    roomHeight: roomHeight,
    desks: [...desks, ...fixtures],
    groups: groups,
    notes: 'Teams of four for Kagan structures.',
  );
}

/// One open U, every desk angled toward the middle of the room.
RoomLayout _horseshoe(
  String name,
  String? sectionId,
  double roomWidth,
  double roomHeight,
  List<Desk> fixtures,
) {
  final focus = Offset(roomWidth / 2, 200);
  final desks = <Desk>[];

  void place(Offset position) {
    final toFocus = focus - position;
    // Desks face "up" at 0 degrees, so the angle is measured off the +Y axis.
    final degrees =
        math.atan2(toFocus.dx, -toFocus.dy) * 180 / math.pi;
    desks.add(
      Desk.create(
        x: position.dx,
        y: position.dy,
        rotation: Desk.normalizeRotation(degrees),
      ),
    );
  }

  const perSide = 5;
  const perBottom = 6;
  final left = roomWidth * 0.18;
  final right = roomWidth * 0.82;
  final top = roomHeight * 0.36;
  final bottom = roomHeight * 0.84;

  for (var i = 0; i < perSide; i++) {
    final t = i / (perSide - 1);
    place(Offset(left, top + (bottom - top) * t));
    place(Offset(right, top + (bottom - top) * t));
  }
  for (var i = 1; i < perBottom - 1; i++) {
    final t = i / (perBottom - 1);
    place(Offset(left + (right - left) * t, bottom));
  }

  return RoomLayout.create(
    name: name,
    classSectionId: sectionId,
    roomWidth: roomWidth,
    roomHeight: roomHeight,
    desks: [...desks, ...fixtures],
    notes: 'Open U for whole-class discussion and number talks.',
  );
}
