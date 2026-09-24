import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../models/desk.dart';

/// Axis used by the spacing and alignment helpers.
enum SpreadAxis {
  horizontal('Horizontally'),
  vertical('Vertically');

  const SpreadAxis(this.label);
  final String label;
}

/// Edge or centerline that [alignDesks] snaps a selection to.
enum AlignEdge {
  left('Left edges'),
  horizontalCenter('Vertical centerline'),
  right('Right edges'),
  top('Top edges'),
  verticalCenter('Horizontal centerline'),
  bottom('Bottom edges');

  const AlignEdge(this.label);
  final String label;

  bool get isHorizontal =>
      this == left || this == horizontalCenter || this == right;
}

/// How far a rotation handle snaps as it is dragged.
enum RotationSnap {
  free('Free', 0),
  deg15('15°', 15),
  deg45('45°', 45),
  deg90('90°', 90);

  const RotationSnap(this.label, this.step);
  final String label;

  /// Snap increment in degrees; 0 means full 360° freedom.
  final double step;

  double apply(double degrees) {
    if (step <= 0) return Desk.normalizeRotation(degrees);
    return Desk.normalizeRotation((degrees / step).roundToDouble() * step);
  }
}

/// Pure geometry operations over a selection of desks.
///
/// Every function takes desks and returns *new* desks, leaving the caller to
/// fold the result back into a layout. Keeping these pure is what lets the
/// editor treat each operation as one undoable snapshot.
class LayoutOps {
  const LayoutOps._();

  /// Bounding box that encloses every desk, honoring rotation.
  static Rect boundsOf(Iterable<Desk> desks) {
    if (desks.isEmpty) return Rect.zero;
    return desks.map((d) => d.bounds).reduce((a, b) => a.expandToInclude(b));
  }

  /// Average of the desk centers.
  static Offset centroidOf(Iterable<Desk> desks) {
    if (desks.isEmpty) return Offset.zero;
    var sx = 0.0;
    var sy = 0.0;
    for (final d in desks) {
      sx += d.x;
      sy += d.y;
    }
    return Offset(sx / desks.length, sy / desks.length);
  }

  /// Snaps a room-space point to a [gridSize] grid. A [gridSize] of 0 or less
  /// disables snapping.
  static Offset snapPoint(Offset point, double gridSize) {
    if (gridSize <= 0) return point;
    return Offset(
      (point.dx / gridSize).roundToDouble() * gridSize,
      (point.dy / gridSize).roundToDouble() * gridSize,
    );
  }

  /// Keeps a desk fully inside the room.
  static Desk clampToRoom(Desk desk, double roomWidth, double roomHeight) {
    final b = desk.bounds;
    var dx = 0.0;
    var dy = 0.0;
    if (b.left < 0) dx = -b.left;
    if (b.right > roomWidth) dx = roomWidth - b.right;
    if (b.top < 0) dy = -b.top;
    if (b.bottom > roomHeight) dy = roomHeight - b.bottom;
    if (dx == 0 && dy == 0) return desk;
    return desk.movedBy(Offset(dx, dy));
  }

  /// Aligns every desk in the selection to the same edge or centerline.
  ///
  /// The reference is taken from the selection's overall bounds, which is what
  /// a teacher expects when they say "line these up".
  static List<Desk> alignDesks(List<Desk> desks, AlignEdge edge) {
    if (desks.length < 2) return desks;
    final movable = desks.where((d) => !d.locked).toList();
    if (movable.isEmpty) return desks;
    final bounds = boundsOf(desks);

    return [
      for (final d in desks)
        if (d.locked)
          d
        else
          switch (edge) {
            AlignEdge.left => d.movedBy(Offset(bounds.left - d.bounds.left, 0)),
            AlignEdge.right => d.movedBy(
              Offset(bounds.right - d.bounds.right, 0),
            ),
            AlignEdge.horizontalCenter => d.copyWith(x: bounds.center.dx),
            AlignEdge.top => d.movedBy(Offset(0, bounds.top - d.bounds.top)),
            AlignEdge.bottom => d.movedBy(
              Offset(0, bounds.bottom - d.bounds.bottom),
            ),
            AlignEdge.verticalCenter => d.copyWith(y: bounds.center.dy),
          },
    ];
  }

  /// Spaces desks so the gaps *between* them are equal along [axis].
  ///
  /// The outermost two desks stay put and everything between them slides,
  /// which matches the behavior of every design tool's "distribute" command.
  /// Equalizing gaps rather than centers is what looks right when desks are
  /// different sizes.
  static List<Desk> distributeEvenly(List<Desk> desks, SpreadAxis axis) {
    if (desks.length < 3) return desks;
    final horizontal = axis == SpreadAxis.horizontal;

    final sorted = [...desks]
      ..sort((a, b) {
        final av = horizontal ? a.bounds.left : a.bounds.top;
        final bv = horizontal ? b.bounds.left : b.bounds.top;
        return av.compareTo(bv);
      });

    final first = sorted.first.bounds;
    final last = sorted.last.bounds;
    final span = horizontal
        ? last.right - first.left
        : last.bottom - first.top;
    final totalExtent = sorted.fold<double>(
      0,
      (sum, d) => sum + (horizontal ? d.bounds.width : d.bounds.height),
    );
    final gap = (span - totalExtent) / (sorted.length - 1);

    final moved = <String, Desk>{};
    var cursor = horizontal ? first.left : first.top;
    for (final d in sorted) {
      final extent = horizontal ? d.bounds.width : d.bounds.height;
      if (d.locked) {
        cursor = (horizontal ? d.bounds.left : d.bounds.top) + extent + gap;
        continue;
      }
      final current = horizontal ? d.bounds.left : d.bounds.top;
      final delta = cursor - current;
      moved[d.id] = d.movedBy(
        horizontal ? Offset(delta, 0) : Offset(0, delta),
      );
      cursor += extent + gap;
    }

    return [for (final d in desks) moved[d.id] ?? d];
  }

  /// Sets a fixed gap between neighbouring desks along [axis], anchored on the
  /// first desk. Use this when "evenly" is not enough and the teacher wants a
  /// specific aisle width.
  static List<Desk> spaceWithGap(
    List<Desk> desks,
    SpreadAxis axis,
    double gap,
  ) {
    if (desks.length < 2) return desks;
    final horizontal = axis == SpreadAxis.horizontal;
    final sorted = [...desks]
      ..sort((a, b) {
        final av = horizontal ? a.bounds.left : a.bounds.top;
        final bv = horizontal ? b.bounds.left : b.bounds.top;
        return av.compareTo(bv);
      });

    final moved = <String, Desk>{};
    var cursor = horizontal ? sorted.first.bounds.left : sorted.first.bounds.top;
    for (final d in sorted) {
      final extent = horizontal ? d.bounds.width : d.bounds.height;
      if (!d.locked) {
        final current = horizontal ? d.bounds.left : d.bounds.top;
        final delta = cursor - current;
        moved[d.id] = d.movedBy(horizontal ? Offset(delta, 0) : Offset(0, delta));
      }
      cursor += extent + gap;
    }
    return [for (final d in desks) moved[d.id] ?? d];
  }

  /// Pulls a selection into a compact block centered on where it already sits.
  ///
  /// This is the "group these together" helper: desks keep their reading
  /// order but collapse into tidy rows with a uniform [gap].
  static List<Desk> clusterTogether(
    List<Desk> desks, {
    double gap = 10,
    int? columns,
  }) {
    if (desks.length < 2) return desks;
    final center = centroidOf(desks);

    // Reading order: top-to-bottom in bands, then left-to-right, so the
    // result feels like a rearrangement rather than a reshuffle.
    final sorted = [...desks]
      ..sort((a, b) {
        final rowCompare = a.y.compareTo(b.y);
        if (rowCompare.abs() > 0 && (a.y - b.y).abs() > a.height / 2) {
          return rowCompare;
        }
        return a.x.compareTo(b.x);
      });

    final cols = columns ?? math.max(1, math.sqrt(sorted.length).ceil());
    final rows = (sorted.length / cols).ceil();
    final cellWidth =
        sorted.map((d) => d.bounds.width).reduce(math.max) + gap;
    final cellHeight =
        sorted.map((d) => d.bounds.height).reduce(math.max) + gap;

    final blockWidth = cols * cellWidth - gap;
    final blockHeight = rows * cellHeight - gap;
    final originX = center.dx - blockWidth / 2;
    final originY = center.dy - blockHeight / 2;

    final moved = <String, Desk>{};
    for (var i = 0; i < sorted.length; i++) {
      final d = sorted[i];
      if (d.locked) continue;
      final col = i % cols;
      final row = i ~/ cols;
      moved[d.id] = d.movedTo(
        Offset(
          originX + col * cellWidth + cellWidth / 2 - gap / 2,
          originY + row * cellHeight + cellHeight / 2 - gap / 2,
        ),
      );
    }
    return [for (final d in desks) moved[d.id] ?? d];
  }

  /// Arranges up to four desks into a Kagan-style team pod, each desk facing
  /// the middle.
  ///
  /// Kagan structures lean on every student having both a shoulder partner
  /// (beside them) and a face partner (across from them), which only works if
  /// the desks actually point inward.
  static List<Desk> arrangeAsPod(List<Desk> desks, {double gap = 4}) {
    if (desks.length < 2) return desks;
    final center = centroidOf(desks);
    final movable = desks.where((d) => !d.locked).toList();
    if (movable.isEmpty) return desks;

    final w = movable.map((d) => d.width).reduce(math.max);
    final h = movable.map((d) => d.height).reduce(math.max);
    final moved = <String, Desk>{};

    if (movable.length <= 4) {
      // Two facing pairs: top row faces down (180), bottom row faces up (0).
      const rotations = <double>[180, 180, 0, 0];
      final offsets = <Offset>[
        Offset(-(w + gap) / 2, -(h + gap) / 2),
        Offset((w + gap) / 2, -(h + gap) / 2),
        Offset(-(w + gap) / 2, (h + gap) / 2),
        Offset((w + gap) / 2, (h + gap) / 2),
      ];
      for (var i = 0; i < movable.length; i++) {
        moved[movable[i].id] = movable[i].copyWith(
          x: center.dx + offsets[i].dx,
          y: center.dy + offsets[i].dy,
          rotation: rotations[i],
        );
      }
    } else {
      // Larger teams ring the center, each desk rotated to face inward.
      final radius = math.max(w, h) * movable.length / (2 * math.pi) + gap;
      for (var i = 0; i < movable.length; i++) {
        final angle = (2 * math.pi * i) / movable.length - math.pi / 2;
        moved[movable[i].id] = movable[i].copyWith(
          x: center.dx + radius * math.cos(angle),
          y: center.dy + radius * math.sin(angle),
          rotation: Desk.normalizeRotation(angle * 180 / math.pi + 90 + 180),
        );
      }
    }
    return [for (final d in desks) moved[d.id] ?? d];
  }

  /// Rotates a whole selection around its shared centroid, so a pod can be
  /// turned to face a different part of the room without falling apart.
  static List<Desk> rotateSelection(List<Desk> desks, double degrees) {
    if (desks.isEmpty || degrees == 0) return desks;
    final center = centroidOf(desks);
    final radians = degrees * math.pi / 180.0;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return [
      for (final d in desks)
        if (d.locked)
          d
        else
          d.copyWith(
            x: center.dx + (d.x - center.dx) * cos - (d.y - center.dy) * sin,
            y: center.dy + (d.x - center.dx) * sin + (d.y - center.dy) * cos,
            rotation: d.rotation + degrees,
          ),
    ];
  }

  /// Builds a fresh block of desks in classic rows, used to seed a new layout.
  static List<Desk> buildRows({
    required int rows,
    required int columns,
    required Offset origin,
    double columnGap = 40,
    double rowGap = 70,
    double deskWidth = Desk.defaultWidth,
    double deskHeight = Desk.defaultHeight,
  }) => [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < columns; c++)
        Desk.create(
          x: origin.dx + c * (deskWidth + columnGap),
          y: origin.dy + r * (deskHeight + rowGap),
          width: deskWidth,
          height: deskHeight,
        ),
  ];
}
