import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../common/ids.dart';

/// What a placed object in the room actually is.
///
/// Only items where [isSeat] is true can hold a student; the rest are context
/// the teacher needs to lay the room out sensibly (where the door is, which
/// wall the board is on).
enum DeskKind {
  student('Student desk', true),
  table('Group table', true),
  teacher('Teacher desk', false),
  whiteboard('Whiteboard', false),
  door('Door', false),
  storage('Storage / cabinet', false),
  rug('Rug / floor area', false);

  const DeskKind(this.label, this.isSeat);
  final String label;

  /// Whether a student can be assigned here.
  final bool isSeat;

  static DeskKind fromJson(String value) => DeskKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => DeskKind.student,
  );

  String toJson() => name;
}

/// Outline used when painting the item.
enum DeskShape {
  rectangle('Rectangle'),
  rounded('Rounded'),
  circle('Circle'),
  trapezoid('Trapezoid');

  const DeskShape(this.label);
  final String label;

  static DeskShape fromJson(String value) => DeskShape.values.firstWhere(
    (s) => s.name == value,
    orElse: () => DeskShape.rounded,
  );

  String toJson() => name;
}

/// A single placed item in the classroom.
///
/// Position is the item's **center**, in room centimeters, not screen pixels.
/// Storing room units means a saved layout survives a window resize, a
/// different screen density, or being opened on a tablet; the view applies a
/// scale at paint time and inverts it for hit-testing.
class Desk {
  const Desk({
    required this.id,
    required this.x,
    required this.y,
    this.kind = DeskKind.student,
    this.shape = DeskShape.rounded,
    this.width = defaultWidth,
    this.height = defaultHeight,
    this.rotation = 0,
    this.groupId,
    this.label = '',
    this.locked = false,
  });

  Desk.create({
    required this.x,
    required this.y,
    this.kind = DeskKind.student,
    this.shape = DeskShape.rounded,
    this.width = defaultWidth,
    this.height = defaultHeight,
    this.rotation = 0,
    this.groupId,
    this.label = '',
    this.locked = false,
  }) : id = newId();

  /// A typical student desk is about 60cm x 45cm.
  static const double defaultWidth = 60;
  static const double defaultHeight = 45;

  final String id;

  /// Center X in room centimeters, measured from the room's top-left corner.
  final double x;

  /// Center Y in room centimeters, measured from the room's top-left corner.
  final double y;

  final DeskKind kind;
  final DeskShape shape;

  /// Size in room centimeters, before rotation.
  final double width;
  final double height;

  /// Clockwise rotation in degrees, normalized to [0, 360).
  final double rotation;

  /// Id of the [DeskGroup] this desk belongs to, if any.
  final String? groupId;

  /// Optional override label, e.g. "Front table". Empty means "use the
  /// assigned student's name".
  final String label;

  /// A locked desk is skipped by move, shuffle, and align operations.
  final bool locked;

  bool get isSeat => kind.isSeat;

  Offset get center => Offset(x, y);

  /// Axis-aligned bounds ignoring rotation, in room centimeters.
  Rect get localBounds =>
      Rect.fromCenter(center: center, width: width, height: height);

  /// The desk's four corners in room coordinates, with [rotation] applied.
  List<Offset> get corners {
    final radians = rotation * math.pi / 180.0;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final hw = width / 2;
    final hh = height / 2;
    const signs = <(double, double)>[(-1, -1), (1, -1), (1, 1), (-1, 1)];
    return [
      for (final (sx, sy) in signs)
        Offset(
          x + (sx * hw) * cos - (sy * hh) * sin,
          y + (sx * hw) * sin + (sy * hh) * cos,
        ),
    ];
  }

  /// Axis-aligned bounding box of the rotated desk, in room centimeters.
  ///
  /// Used for marquee selection, distribute/align math, and fitting the room
  /// view to its contents.
  Rect get bounds {
    if (rotation == 0) return localBounds;
    final pts = corners;
    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Hit-test a point given in room coordinates, honoring rotation.
  ///
  /// The point is rotated back into the desk's local frame rather than
  /// rotating the rectangle, which keeps this exact for any angle.
  bool containsPoint(Offset point, {double padding = 0}) {
    final radians = -rotation * math.pi / 180.0;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final dx = point.dx - x;
    final dy = point.dy - y;
    final localX = dx * cos - dy * sin;
    final localY = dx * sin + dy * cos;
    final hw = width / 2 + padding;
    final hh = height / 2 + padding;
    if (shape == DeskShape.circle) {
      if (hw <= 0 || hh <= 0) return false;
      final nx = localX / hw;
      final ny = localY / hh;
      return nx * nx + ny * ny <= 1.0;
    }
    return localX.abs() <= hw && localY.abs() <= hh;
  }

  Desk copyWith({
    double? x,
    double? y,
    DeskKind? kind,
    DeskShape? shape,
    double? width,
    double? height,
    double? rotation,
    String? groupId,
    bool clearGroup = false,
    String? label,
    bool? locked,
  }) => Desk(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    kind: kind ?? this.kind,
    shape: shape ?? this.shape,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: normalizeRotation(rotation ?? this.rotation),
    groupId: clearGroup ? null : (groupId ?? this.groupId),
    label: label ?? this.label,
    locked: locked ?? this.locked,
  );

  Desk movedTo(Offset position) => copyWith(x: position.dx, y: position.dy);

  Desk movedBy(Offset delta) => copyWith(x: x + delta.dx, y: y + delta.dy);

  /// Wraps any angle into [0, 360).
  static double normalizeRotation(double degrees) {
    final value = degrees % 360.0;
    return value < 0 ? value + 360.0 : value;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'kind': kind.toJson(),
    'shape': shape.toJson(),
    'width': width,
    'height': height,
    'rotation': rotation,
    'groupId': groupId,
    'label': label,
    'locked': locked,
  };

  factory Desk.fromJson(Map<String, Object?> json) => Desk(
    id: json['id']! as String,
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    kind: DeskKind.fromJson(json['kind'] as String? ?? 'student'),
    shape: DeskShape.fromJson(json['shape'] as String? ?? 'rounded'),
    width: (json['width'] as num?)?.toDouble() ?? defaultWidth,
    height: (json['height'] as num?)?.toDouble() ?? defaultHeight,
    rotation: normalizeRotation((json['rotation'] as num?)?.toDouble() ?? 0),
    groupId: json['groupId'] as String?,
    label: json['label'] as String? ?? '',
    locked: json['locked'] as bool? ?? false,
  );
}
