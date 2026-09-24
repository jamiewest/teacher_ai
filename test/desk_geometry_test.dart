import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/domain/models/desk.dart';

void main() {
  group('Desk rotation geometry', () {
    test('normalizes any angle into [0, 360)', () {
      expect(Desk.normalizeRotation(-90), 270);
      expect(Desk.normalizeRotation(450), 90);
      expect(Desk.normalizeRotation(360), 0);
    });

    test('bounds of an unrotated desk match its size', () {
      final desk = Desk(id: 'a', x: 100, y: 100, width: 60, height: 40);
      expect(desk.bounds, const Rect.fromLTRB(70, 80, 130, 120));
    });

    test('a 90-degree rotation swaps the bounding box extents', () {
      final desk = Desk(
        id: 'a',
        x: 100,
        y: 100,
        width: 60,
        height: 40,
        rotation: 90,
      );
      final bounds = desk.bounds;
      expect(bounds.width, closeTo(40, 0.001));
      expect(bounds.height, closeTo(60, 0.001));
      expect(bounds.center.dx, closeTo(100, 0.001));
    });

    test('hit-testing follows the rotation', () {
      final desk = Desk(
        id: 'a',
        x: 0,
        y: 0,
        width: 100,
        height: 20,
        rotation: 90,
      );
      // Rotated upright: tall and narrow, so a point 40 above is inside and a
      // point 40 to the side is not.
      expect(desk.containsPoint(const Offset(0, -40)), isTrue);
      expect(desk.containsPoint(const Offset(40, 0)), isFalse);
    });

    test('a circular desk uses an elliptical hit region', () {
      final desk = Desk(
        id: 'a',
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        shape: DeskShape.circle,
      );
      expect(desk.containsPoint(const Offset(40, 0)), isTrue);
      // The corner of the bounding box falls outside the circle.
      expect(desk.containsPoint(const Offset(45, 45)), isFalse);
    });

    test('corners stay the right distance from the center when rotated', () {
      final desk = Desk(
        id: 'a',
        x: 10,
        y: 10,
        width: 60,
        height: 40,
        rotation: 37,
      );
      final expected = math.sqrt(30 * 30 + 20 * 20);
      for (final corner in desk.corners) {
        expect((corner - desk.center).distance, closeTo(expected, 0.001));
      }
    });

    test('round-trips through JSON', () {
      final desk = Desk(
        id: 'a',
        x: 12.5,
        y: 34.5,
        kind: DeskKind.table,
        shape: DeskShape.circle,
        width: 120,
        height: 120,
        rotation: 45,
        groupId: 'g1',
        label: 'Front table',
        locked: true,
      );
      final restored = Desk.fromJson(desk.toJson());
      expect(restored.x, desk.x);
      expect(restored.rotation, desk.rotation);
      expect(restored.kind, DeskKind.table);
      expect(restored.shape, DeskShape.circle);
      expect(restored.groupId, 'g1');
      expect(restored.locked, isTrue);
    });
  });
}
