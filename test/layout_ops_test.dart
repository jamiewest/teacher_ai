import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/domain/models/desk.dart';
import 'package:teacher_ai/domain/ops/layout_ops.dart';

Desk deskAt(String id, double x, double y, {bool locked = false}) =>
    Desk(id: id, x: x, y: y, width: 60, height: 40, locked: locked);

void main() {
  group('alignDesks', () {
    test('aligns left edges to the selection bounds', () {
      final desks = [deskAt('a', 100, 0), deskAt('b', 300, 50)];
      final result = LayoutOps.alignDesks(desks, AlignEdge.left);
      expect(result[0].bounds.left, closeTo(70, 0.001));
      expect(result[1].bounds.left, closeTo(70, 0.001));
      // Aligning left must not move anything vertically.
      expect(result[1].y, 50);
    });

    test('centers on the shared vertical centerline', () {
      final desks = [deskAt('a', 100, 0), deskAt('b', 300, 0)];
      final result = LayoutOps.alignDesks(desks, AlignEdge.horizontalCenter);
      expect(result[0].x, closeTo(200, 0.001));
      expect(result[1].x, closeTo(200, 0.001));
    });

    test('leaves locked desks where they are', () {
      final desks = [deskAt('a', 100, 0), deskAt('b', 300, 0, locked: true)];
      final result = LayoutOps.alignDesks(desks, AlignEdge.left);
      expect(result[1].x, 300);
    });
  });

  group('distributeEvenly', () {
    test('equalizes the gaps between desks and keeps the ends fixed', () {
      final desks = [
        deskAt('a', 0, 0),
        deskAt('b', 40, 0),
        deskAt('c', 400, 0),
      ];
      final result = LayoutOps.distributeEvenly(desks, SpreadAxis.horizontal);
      final sorted = [...result]..sort((p, q) => p.x.compareTo(q.x));

      expect(sorted.first.x, closeTo(0, 0.001), reason: 'first stays put');
      expect(sorted.last.x, closeTo(400, 0.001), reason: 'last stays put');

      final gap1 = sorted[1].bounds.left - sorted[0].bounds.right;
      final gap2 = sorted[2].bounds.left - sorted[1].bounds.right;
      expect(gap1, closeTo(gap2, 0.001));
    });

    test('is a no-op below three desks', () {
      final desks = [deskAt('a', 0, 0), deskAt('b', 500, 0)];
      expect(LayoutOps.distributeEvenly(desks, SpreadAxis.horizontal), desks);
    });

    test('works down the vertical axis too', () {
      final desks = [
        deskAt('a', 0, 0),
        deskAt('b', 0, 20),
        deskAt('c', 0, 300),
      ];
      final result = LayoutOps.distributeEvenly(desks, SpreadAxis.vertical);
      final sorted = [...result]..sort((p, q) => p.y.compareTo(q.y));
      final gap1 = sorted[1].bounds.top - sorted[0].bounds.bottom;
      final gap2 = sorted[2].bounds.top - sorted[1].bounds.bottom;
      expect(gap1, closeTo(gap2, 0.001));
    });
  });

  test('spaceWithGap sets an exact edge-to-edge distance', () {
    final desks = [deskAt('a', 0, 0), deskAt('b', 500, 0), deskAt('c', 900, 0)];
    final result = LayoutOps.spaceWithGap(desks, SpreadAxis.horizontal, 25);
    final sorted = [...result]..sort((p, q) => p.x.compareTo(q.x));
    expect(sorted[1].bounds.left - sorted[0].bounds.right, closeTo(25, 0.001));
    expect(sorted[2].bounds.left - sorted[1].bounds.right, closeTo(25, 0.001));
  });

  group('arrangeAsPod', () {
    test('faces four desks inward as two facing pairs', () {
      final desks = [
        deskAt('a', 0, 0),
        deskAt('b', 200, 0),
        deskAt('c', 0, 200),
        deskAt('d', 200, 200),
      ];
      final result = LayoutOps.arrangeAsPod(desks);
      final rotations = result.map((d) => d.rotation).toSet();
      expect(rotations, {0.0, 180.0});

      // The pod stays centered on where the desks already were.
      final centroid = LayoutOps.centroidOf(result);
      expect(centroid.dx, closeTo(100, 0.001));
      expect(centroid.dy, closeTo(100, 0.001));
    });

    test('rings larger teams around the center', () {
      final desks = [for (var i = 0; i < 6; i++) deskAt('d$i', 0, 0)];
      final result = LayoutOps.arrangeAsPod(desks);
      final centroid = LayoutOps.centroidOf(result);
      for (final desk in result) {
        expect((desk.center - centroid).distance, greaterThan(0));
      }
    });
  });

  test('rotateSelection turns the pod without pulling it apart', () {
    final desks = [deskAt('a', 0, 0), deskAt('b', 100, 0)];
    final before = (desks[1].center - desks[0].center).distance;
    final result = LayoutOps.rotateSelection(desks, 90);
    final after = (result[1].center - result[0].center).distance;

    expect(after, closeTo(before, 0.001));
    expect(result[0].rotation, 90);
    // A 90 degree turn about the centroid puts b below a.
    expect(result[1].center.dy, greaterThan(result[0].center.dy));
  });

  group('snapping and clamping', () {
    test('snapPoint rounds to the nearest grid intersection', () {
      expect(LayoutOps.snapPoint(const Offset(37, 52), 15), const Offset(30, 45));
      expect(LayoutOps.snapPoint(const Offset(37, 52), 0), const Offset(37, 52));
    });

    test('clampToRoom pulls a desk back inside the walls', () {
      final desk = deskAt('a', -50, 10);
      final clamped = LayoutOps.clampToRoom(desk, 900, 700);
      expect(clamped.bounds.left, closeTo(0, 0.001));
      expect(clamped.bounds.top, greaterThanOrEqualTo(0));
    });
  });

  test('buildRows lays out an evenly spaced block', () {
    final desks = LayoutOps.buildRows(
      rows: 3,
      columns: 4,
      origin: const Offset(100, 100),
      columnGap: 40,
      rowGap: 60,
    );
    expect(desks, hasLength(12));
    expect(desks[1].x - desks[0].x, closeTo(Desk.defaultWidth + 40, 0.001));
    expect(desks[4].y - desks[0].y, closeTo(Desk.defaultHeight + 60, 0.001));
  });
}
