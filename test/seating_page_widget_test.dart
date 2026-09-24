import 'dart:math' as math;

import 'package:extensions/logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/app/home_shell.dart';
import 'package:teacher_ai/app/theme.dart';
import 'package:teacher_ai/data/key_value_store.dart';
import 'package:teacher_ai/data/teacher_repository.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';
import 'package:teacher_ai/domain/models/models.dart';
import 'package:teacher_ai/features/seating/widgets/room_canvas.dart';
import 'package:teacher_ai/features/seating/widgets/roster_panel.dart';

Future<TeacherWorkspace> loadedWorkspace() async {
  final workspace = TeacherWorkspace(
    StoredTeacherRepository(InMemoryStore(), NullLoggerFactory.instance),
    NullLoggerFactory.instance,
  );
  await workspace.load();
  return workspace;
}

Future<void> pumpShell(
  WidgetTester tester,
  TeacherWorkspace workspace,
  Size size,
) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: HomeShell(workspace: workspace),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(1400, 900),
    const Size(900, 700),
    const Size(390, 844),
  ]) {
    testWidgets('expanded canvas fits and restores the view at $size', (
      tester,
    ) async {
      final workspace = await loadedWorkspace();
      await pumpShell(tester, workspace, size);
      final canvas = find.byType(RoomCanvas);
      final normalSize = tester.getSize(canvas);
      final normalView = tester.widget<RoomCanvas>(canvas).view;

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      final previousScale = normalView.scale;
      final previousPan = normalView.pan;

      await tester.tap(find.text('Expand view'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RosterPanel), findsNothing);
      final expandedSize = tester.getSize(canvas);
      expect(expandedSize.height, greaterThan(normalSize.height));
      if (size.width == 1400) {
        expect(expandedSize.width, greaterThan(normalSize.width));
      }
      final expandedCanvas = tester.widget<RoomCanvas>(canvas);
      final view = expandedCanvas.view;
      final room = expandedCanvas.controller.layout.roomSize;
      final roomRect = Rect.fromPoints(
        view.toScreen(Offset.zero),
        view.toScreen(Offset(room.width, room.height)),
      );
      expect(roomRect.left, greaterThanOrEqualTo(19.9));
      expect(roomRect.top, greaterThanOrEqualTo(19.9));
      expect(roomRect.right, lessThanOrEqualTo(expandedSize.width - 19.9));
      expect(roomRect.bottom, lessThanOrEqualTo(expandedSize.height - 19.9));

      // Seating remains editable, with the same draft and undo history.
      await tester.tap(find.text('Seat remaining'));
      await tester.pumpAndSettle();
      final seating = Map.of(expandedCanvas.controller.seating);
      expect(seating, isNotEmpty);
      expect(find.byTooltip('Save chart'), findsOneWidget);

      await tester.tap(find.text('Restore view'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(canvas), normalSize);
      final restored = tester.widget<RoomCanvas>(canvas);
      expect(restored.view.scale, previousScale);
      expect(restored.view.pan, previousPan);
      expect(restored.controller.seating, seating);
      expect(restored.controller.canUndo, isTrue);
    });
  }

  testWidgets('the seating editor renders the seeded classroom', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));

    expect(find.byType(RoomCanvas), findsOneWidget);
    // The seeded class opens on the Kagan pod layout.
    expect(find.text('Kagan pods'), findsOneWidget);
  });

  testWidgets('a wide window docks the roster beside the canvas', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));

    expect(find.byType(RosterPanel), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a narrow window gives the canvas the whole screen', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(500, 900));

    // Panels become sheets, so neither is docked.
    expect(find.byType(RosterPanel), findsNothing);
    expect(find.byType(RoomCanvas), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('switching to the roster tab lists the seeded students', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Roster'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ava Mitchell'), findsWidgets);
    expect(find.text('Talks a lot'), findsWidgets);
  });

  testWidgets('room edits autosave and survive a tab switch', (tester) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));

    await tester.tap(find.text('Design room'));
    await tester.pumpAndSettle();

    final layoutId = workspace.classes.first.activeLayoutId!;
    Desk firstSeat() => workspace.layout(layoutId)!.seats.first;
    final before = firstSeat();

    // Drag the desk across the room, the way a teacher would.
    final canvas = tester.getRect(find.byType(RoomCanvas));
    final view = tester.widget<RoomCanvas>(find.byType(RoomCanvas)).view;
    final start = canvas.topLeft + view.toScreen(before.center);

    await tester.dragFrom(start, const Offset(120, 90));
    await tester.pumpAndSettle();

    // The room autosaves, so the workspace already has the new position.
    final moved = firstSeat();
    expect(
      moved.center,
      isNot(before.center),
      reason:
          'dragging a desk should reach the workspace without an explicit '
          'save',
    );

    // Leave for the roster, then come back.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Roster'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();

    expect(
      firstSeat().center,
      moved.center,
      reason: 'the move must not be discarded when the tab changes',
    );
  });

  testWidgets('deleting the active layout falls back to a surviving one', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));

    final section = workspace.classes.first;
    final active = section.activeLayoutId!;
    final survivor = workspace
        .layoutsFor(section.id)
        .firstWhere((l) => l.id != active);

    workspace.deleteLayout(active);
    await tester.pumpAndSettle();
    // Let the workspace's debounced save fire so no timer outlives the test.
    await tester.pump(TeacherWorkspace.saveDebounce);

    expect(workspace.layout(active), isNull);
    expect(find.byType(RoomCanvas), findsOneWidget);
    expect(
      find.text(survivor.name),
      findsWidgets,
      reason: 'the editor should move to the remaining layout',
    );
  });

  testWidgets('dragging the rotation handle turns the desk in snap steps', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));

    await tester.tap(find.text('Design room'));
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(RoomCanvas));
    final canvasWidget = tester.widget<RoomCanvas>(find.byType(RoomCanvas));
    final view = canvasWidget.view;
    final editor = canvasWidget.controller;

    final desk = editor.layout.seats.first;
    final before = desk.rotation;
    Offset toGlobal(Offset room) => canvas.topLeft + view.toScreen(room);

    // Select the desk so its rotation handle appears.
    await tester.tapAt(toGlobal(desk.center));
    await tester.pumpAndSettle();
    expect(editor.soleSelection?.id, desk.id);

    // The handle sits off the desk's leading edge, travelling with its facing.
    final distance = desk.height / 2 + view.screenToRoomDistance(28);
    final radians = desk.rotation * math.pi / 180.0;
    final handle = Offset(
      desk.center.dx + distance * math.sin(radians),
      desk.center.dy - distance * math.cos(radians),
    );
    // Drag it to the desk's right, which is a quarter turn.
    final target = desk.center + Offset(distance, 0);

    await tester.dragFrom(
      toGlobal(handle),
      toGlobal(target) - toGlobal(handle),
    );
    await tester.pumpAndSettle();

    final after = editor.layout.deskById(desk.id)!.rotation;
    expect(after, isNot(before), reason: 'the handle should rotate the desk');
    expect(
      after % editor.rotationSnap.step,
      closeTo(0, 0.001),
      reason: 'rotation should land on the active snap increment',
    );
    expect(after, closeTo(90, 0.001));
  });
}
