import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/features/seating/seating_editor_state.dart';
import 'package:teacher_ai/features/seating/widgets/room_canvas.dart';
import 'package:teacher_ai/features/seating/widgets/seat_picker.dart';
import 'seating_page_widget_test.dart' show loadedWorkspace, pumpShell;

RoomCanvas canvasWidget(WidgetTester tester) =>
    tester.widget<RoomCanvas>(find.byType(RoomCanvas));
Offset seatPoint(WidgetTester tester, String id) {
  final canvas = canvasWidget(tester);
  return tester.getTopLeft(find.byType(RoomCanvas)) +
      canvas.view.toScreen(canvas.controller.layout.deskById(id)!.center);
}

void main() {
  testWidgets('pick a student, place, swap, and undo without moving desks', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    final editor = canvasWidget(tester).controller;
    final seats = editor.layout.seats;
    final first = editor.roster.first;
    final second = editor.roster[1];
    await tester.tap(find.text(first.fullName));
    await tester.pumpAndSettle();
    await tester.tapAt(seatPoint(tester, seats[0].id));
    await tester.pumpAndSettle();
    expect(editor.studentAt(seats[0].id)?.id, first.id);
    expect(editor.pendingStudentId, isNull);
    editor.placeStudent(seats[1].id, second.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text(first.fullName));
    await tester.pumpAndSettle();
    await tester.tapAt(seatPoint(tester, seats[1].id));
    await tester.pumpAndSettle();
    expect(editor.studentAt(seats[1].id)?.id, first.id);
    expect(editor.studentAt(seats[0].id)?.id, second.id);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(editor.studentAt(seats[0].id)?.id, first.id);
    expect(
      editor.layout.seats.map((s) => s.center),
      seats.map((s) => s.center),
    );
  });

  testWidgets('seat remaining preserves placements and can be undone', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    final editor = canvasWidget(tester).controller;
    final seat = editor.layout.seats.first;
    final student = editor.roster.first;
    editor.placeStudent(seat.id, student.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seat remaining'));
    await tester.pumpAndSettle();
    expect(editor.unseatedStudents, isEmpty);
    expect(editor.studentAt(seat.id)?.id, student.id);
    expect(editor.hasUnsavedSeating, isTrue);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(editor.seating, {seat.id: student.id});
  });

  testWidgets('one tap opens a searchable picker and pin survives saving', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    final editor = canvasWidget(tester).controller;
    final seat = editor.layout.seats.first;
    final student = editor.roster.first;
    await tester.tapAt(seatPoint(tester, seat.id));
    await tester.pumpAndSettle();
    expect(find.byType(SeatPicker), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(SeatPicker),
        matching: find.byType(TextField),
      ),
      student.fullName,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SeatPicker),
        matching: find.text(student.fullName, findRichText: false).last,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(seatPoint(tester, seat.id));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close seat picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save chart'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Monday',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(editor.hasUnsavedSeating, isFalse);
    expect(
      workspace.latestAssignment(editor.layout.id)!.lockedDeskIds,
      contains(seat.id),
    );
    editor.shuffleSeating(seed: 1);
    expect(editor.studentAt(seat.id)?.id, student.id);
  });

  testWidgets('seating mode protects furniture from drag and delete', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    final editor = canvasWidget(tester).controller;
    final desk = editor.layout.seats.first;
    editor.placeStudent(desk.id, editor.roster.first.id);
    await tester.pumpAndSettle();
    await tester.dragFrom(seatPoint(tester, desk.id), const Offset(90, 60));
    await tester.pumpAndSettle();
    expect(editor.layout.deskById(desk.id)!.center, desk.center);
    editor.selectOnly(desk.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(editor.layout.deskById(desk.id), isNotNull);
    expect(editor.studentAt(desk.id), isNull);
  });

  testWidgets('switching layouts and resizing preserve the seating draft', (
    tester,
  ) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    final editor = canvasWidget(tester).controller;
    editor.placeStudent(editor.layout.seats.first.id, editor.roster.first.id);
    final savedMap = Map<String, String>.from(editor.seating);
    await tester.pumpAndSettle();
    final other = workspace
        .layoutsFor(workspace.classes.first.id)
        .firstWhere((l) => l.id != editor.layout.id);
    await tester.tap(find.text(editor.layout.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(other.name));
    await tester.pumpAndSettle();
    expect(canvasWidget(tester).controller.layout.id, other.id);
    await tester.tap(find.text(other.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(editor.layout.name).first);
    await tester.pumpAndSettle();
    expect(canvasWidget(tester).controller.seating, savedMap);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(canvasWidget(tester).controller, same(editor));
    expect(editor.seating, savedMap);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add a named fixture in design mode and undo it', (tester) async {
    final workspace = await loadedWorkspace();
    await pumpShell(tester, workspace, const Size(1400, 900));
    final editor = canvasWidget(tester).controller;
    final before = editor.layout.desks.length;
    await tester.tap(find.text('Design room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add furniture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whiteboard'));
    await tester.pumpAndSettle();
    expect(editor.layout.desks.length, before + 1);
    expect(editor.soleSelection!.label, 'Whiteboard');
    expect(
      editor.soleSelection!.width,
      greaterThan(editor.soleSelection!.height),
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(editor.layout.desks.length, before);
  });

  for (final width in [360.0, 768.0, 1024.0, 1400.0]) {
    testWidgets('seating and design fit a $width pixel window', (tester) async {
      final workspace = await loadedWorkspace();
      await pumpShell(tester, workspace, Size(width, 844));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Design room'));
      await tester.pumpAndSettle();
      expect(canvasWidget(tester).controller.mode, EditorMode.design);
      expect(tester.takeException(), isNull);
    });
  }
}
