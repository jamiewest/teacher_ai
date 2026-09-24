import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:collection/collection.dart';

import '../../common/ids.dart';
import 'desk.dart';
import 'desk_group.dart';

/// A saved arrangement of a classroom: the room's dimensions plus every desk
/// and group in it.
///
/// A teacher keeps several of these per class — rows for a test, pods for
/// group work — and switches between them, so layouts are named, listable
/// records rather than a single mutable "current room".
class RoomLayout {
  const RoomLayout({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.classSectionId,
    this.roomWidth = defaultRoomWidth,
    this.roomHeight = defaultRoomHeight,
    this.gridSize = defaultGridSize,
    this.desks = const <Desk>[],
    this.groups = const <DeskGroup>[],
    this.notes = '',
  });

  factory RoomLayout.create({
    required String name,
    String? classSectionId,
    double roomWidth = defaultRoomWidth,
    double roomHeight = defaultRoomHeight,
    double gridSize = defaultGridSize,
    List<Desk> desks = const <Desk>[],
    List<DeskGroup> groups = const <DeskGroup>[],
    String notes = '',
  }) {
    final now = DateTime.now();
    return RoomLayout(
      id: newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
      classSectionId: classSectionId,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
      gridSize: gridSize,
      desks: desks,
      groups: groups,
      notes: notes,
    );
  }

  /// All measurements are in centimeters. A 9m x 7m room is a common
  /// classroom footprint.
  static const double defaultRoomWidth = 900;
  static const double defaultRoomHeight = 700;

  /// 15cm grid gives fine control without making snapping feel loose.
  static const double defaultGridSize = 15;

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Layouts are usually owned by a class, but can be drafted standalone.
  final String? classSectionId;

  /// Room dimensions in centimeters.
  final double roomWidth;
  final double roomHeight;

  /// Snap-to-grid spacing in centimeters.
  final double gridSize;

  final List<Desk> desks;
  final List<DeskGroup> groups;
  final String notes;

  Size get roomSize => Size(roomWidth, roomHeight);

  Rect get roomBounds => Rect.fromLTWH(0, 0, roomWidth, roomHeight);

  /// Desks a student can actually be assigned to.
  List<Desk> get seats => desks.where((d) => d.isSeat).toList(growable: false);

  int get seatCount => seats.length;

  Desk? deskById(String id) => desks.firstWhereOrNull((d) => d.id == id);

  DeskGroup? groupById(String id) => groups.firstWhereOrNull((g) => g.id == id);

  DeskGroup? groupForDesk(String deskId) {
    final desk = deskById(deskId);
    final groupId = desk?.groupId;
    return groupId == null ? null : groupById(groupId);
  }

  /// Desks belonging to [groupId], in the group's stored seat order.
  List<Desk> desksInGroup(String groupId) {
    final group = groupById(groupId);
    if (group == null) return const <Desk>[];
    return group.deskIds
        .map(deskById)
        .whereType<Desk>()
        .toList(growable: false);
  }

  /// Bounding box of everything placed, or the room itself when empty.
  Rect get contentBounds {
    if (desks.isEmpty) return roomBounds;
    return desks.map((d) => d.bounds).reduce((a, b) => a.expandToInclude(b));
  }

  /// Next default group name, avoiding collisions with existing "Group N"
  /// names so deleting group 2 does not produce a duplicate later.
  String nextGroupName() {
    var n = groups.length + 1;
    final taken = groups.map((g) => g.name).toSet();
    while (taken.contains('Group $n')) {
      n++;
    }
    return 'Group $n';
  }

  /// Next color in the palette, offset so new groups do not repeat the last.
  int nextGroupColor() => kGroupColors[groups.length % kGroupColors.length];

  /// Snaps a room-space value to the layout's grid.
  double snapToGrid(double value) =>
      gridSize <= 0 ? value : (value / gridSize).roundToDouble() * gridSize;

  RoomLayout copyWith({
    String? name,
    DateTime? updatedAt,
    String? classSectionId,
    bool clearSection = false,
    double? roomWidth,
    double? roomHeight,
    double? gridSize,
    List<Desk>? desks,
    List<DeskGroup>? groups,
    String? notes,
  }) => RoomLayout(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    classSectionId: clearSection
        ? null
        : (classSectionId ?? this.classSectionId),
    roomWidth: roomWidth ?? this.roomWidth,
    roomHeight: roomHeight ?? this.roomHeight,
    gridSize: gridSize ?? this.gridSize,
    desks: desks ?? this.desks,
    groups: groups ?? this.groups,
    notes: notes ?? this.notes,
  );

  /// Duplicates the layout under a new id and name, keeping desk ids stable
  /// within the copy so groups still resolve.
  RoomLayout duplicate({String? name}) {
    final idMap = <String, String>{for (final d in desks) d.id: newId()};
    final now = DateTime.now();
    return RoomLayout(
      id: newId(),
      name: name ?? '${this.name} (copy)',
      createdAt: now,
      updatedAt: now,
      classSectionId: classSectionId,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
      gridSize: gridSize,
      desks: [
        for (final d in desks)
          Desk(
            id: idMap[d.id]!,
            x: d.x,
            y: d.y,
            kind: d.kind,
            shape: d.shape,
            width: d.width,
            height: d.height,
            rotation: d.rotation,
            groupId: d.groupId,
            label: d.label,
            locked: d.locked,
          ),
      ],
      groups: [
        for (final g in groups)
          g.copyWith(
            deskIds: g.deskIds
                .map((id) => idMap[id])
                .whereType<String>()
                .toList(growable: false),
          ),
      ],
      notes: notes,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'classSectionId': classSectionId,
    'roomWidth': roomWidth,
    'roomHeight': roomHeight,
    'gridSize': gridSize,
    'desks': desks.map((d) => d.toJson()).toList(growable: false),
    'groups': groups.map((g) => g.toJson()).toList(growable: false),
    'notes': notes,
  };

  factory RoomLayout.fromJson(Map<String, Object?> json) => RoomLayout(
    id: json['id']! as String,
    name: json['name']! as String,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    classSectionId: json['classSectionId'] as String?,
    roomWidth: (json['roomWidth'] as num?)?.toDouble() ?? defaultRoomWidth,
    roomHeight: (json['roomHeight'] as num?)?.toDouble() ?? defaultRoomHeight,
    gridSize: math.max(
      0,
      (json['gridSize'] as num?)?.toDouble() ?? defaultGridSize,
    ),
    desks: (json['desks'] as List<Object?>? ?? const [])
        .map((e) => Desk.fromJson(e! as Map<String, Object?>))
        .toList(growable: false),
    groups: (json['groups'] as List<Object?>? ?? const [])
        .map((e) => DeskGroup.fromJson(e! as Map<String, Object?>))
        .toList(growable: false),
    notes: json['notes'] as String? ?? '',
  );
}
