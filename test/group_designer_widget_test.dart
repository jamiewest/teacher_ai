import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/domain/ops/layout_ops.dart';
import 'package:teacher_ai/features/seating/widgets/inspector_panel.dart';
import 'package:teacher_ai/features/seating/widgets/room_canvas.dart';
import 'package:teacher_ai/features/seating/widgets/room_painter.dart';

import 'seating_page_widget_test.dart' show loadedWorkspace, pumpShell;

RoomCanvas canvasWidget(WidgetTester tester) =>
    tester.widget<RoomCanvas>(find.byType(RoomCanvas));

Offset screenPoint(WidgetTester tester, Offset roomPoint) =>
    tester.getTopLeft(find.byType(RoomCanvas)) +
    canvasWidget(tester).view.toScreen(roomPoint);

GroupVisual firstGroup(WidgetTester tester) {
  final canvas = canvasWidget(tester);
  return GroupVisual.forLayout(
    canvas.controller.layout,
    TextLayoutCache(),
    canvas.view.scale,
  ).first;
}

RoomPainter roomPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(RoomCanvas),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as RoomPainter;

void main() {
  testWidgets(
    'click a group label to edit it, then click a desk independently',
    (tester) async {
      final workspace = await loadedWorkspace();
      await pumpShell(tester, workspace, const Size(1400, 900));
      await tester.tap(find.text('Design room'));
      await tester.pumpAndSettle();
      final visual = firstGroup(tester);
      final editor = canvasWidget(tester).controller;
      await tester.tapAt(screenPoint(tester, visual.labelBounds!.center));
      await tester.pumpAndSettle();
      expect(editor.selectedGroup?.id, visual.group.id);
      expect(find.text('GROUP PROPERTIES'), findsOneWidget);
      expect(find.text('Lock group position'), findsOneWidget);
      expect(roomPainter(tester).selectedGroupId, visual.group.id);
      expect(roomPainter(tester).rotationHandle, isNotNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, visual.group.name),
        'Window team',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.selectedGroup!.name, 'Window team');
      final widthSlider = find
          .descendant(
            of: find.byType(InspectorPanel),
            matching: find.byType(Slider),
          )
          .first;
      await tester.drag(widthSlider, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(
        editor.selectedDesks.map((desk) => desk.width).toSet(),
        hasLength(1),
      );
      expect(editor.selectedDesks.first.width, isNot(60));

      // Restore the compact pod before clicking a desk: larger widths can
      // overlap neighbours, which correctly take precedence in hit testing.
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();

      final desk = editor.layout.desksInGroup(visual.group.id).first;
      await tester.tapAt(screenPoint(tester, desk.center));
      await tester.pumpAndSettle();
      expect(editor.soleSelection?.id, desk.id);
      expect(editor.selectedGroup, isNull);
      expect(find.text('GROUP PROPERTIES'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets('drag a group outline and rotate its handle with undo', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    await tester.tap(find.text('Design room'));
    await tester.pumpAndSettle();
    final visual = firstGroup(tester);
    final editor = canvasWidget(tester).controller;
    final before = editor.layout;
    final desks = before.desksInGroup(visual.group.id);
    await tester.dragFrom(
      screenPoint(tester, visual.bounds.centerLeft + const Offset(5, 0)),
      const Offset(80, 60),
    );
    await tester.pumpAndSettle();
    expect(editor.selectedGroup?.id, visual.group.id);
    final moved = editor.layout.desksInGroup(visual.group.id);
    final delta = moved.first.center - desks.first.center;
    expect(delta.distance, greaterThan(0));
    for (var i = 0; i < desks.length; i++) {
      expect(
        (moved[i].center - desks[i].center - delta).distance,
        lessThan(0.001),
      );
    }
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(editor.layout, before);

    final handle = roomPainter(tester).rotationHandle!;
    final center = LayoutOps.centroidOf(desks);
    final vector = handle - center;
    final target = center + Offset(-vector.dy, vector.dx);
    await tester.dragFrom(
      screenPoint(tester, handle),
      screenPoint(tester, target) - screenPoint(tester, handle),
    );
    await tester.pumpAndSettle();
    final rotated = editor.layout.desksInGroup(visual.group.id);
    for (var i = 0; i < desks.length; i++) {
      expect(
        rotated[i].rotation,
        closeTo((desks[i].rotation + 90) % 360, 0.001),
      );
      expect(
        (rotated[i].center - center).distance,
        closeTo((desks[i].center - center).distance, 0.001),
      );
    }
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(editor.layout, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group context menu duplicates a selectable group', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    await tester.tap(find.text('Design room'));
    await tester.pumpAndSettle();
    final visual = firstGroup(tester);
    await tester.tapAt(
      screenPoint(tester, visual.labelBounds!.center),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate group'));
    await tester.pumpAndSettle();
    final editor = canvasWidget(tester).controller;
    expect(editor.selectedGroup!.name, '${visual.group.name} (copy)');
    expect(find.text('GROUP PROPERTIES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets('groups can be edited from the expanded canvas at $size', (
      tester,
    ) async {
      final workspace = await loadedWorkspace();
      await pumpShell(tester, workspace, size);
      await tester.tap(find.text('Design room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expand view'));
      await tester.pumpAndSettle();
      final visual = firstGroup(tester);
      await tester.tapAt(
        screenPoint(tester, visual.bounds.centerLeft + const Offset(5, 0)),
      );
      await tester.pumpAndSettle();
      final editor = canvasWidget(tester).controller;
      expect(editor.selectedGroup?.id, visual.group.id);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('GROUP PROPERTIES'), findsOneWidget);
      await tester.tap(find.text('Lock group position'));
      await tester.pumpAndSettle();
      expect(editor.selectedDesks.every((desk) => desk.locked), isTrue);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(InspectorPanel))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore view'));
      await tester.pumpAndSettle();
      expect(editor.selectedGroup?.id, visual.group.id);
      expect(editor.groupPositionLocked, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
