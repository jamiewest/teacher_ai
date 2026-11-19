import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/features/seating/widgets/room_canvas.dart';
import 'seating_page_widget_test.dart' show loadedWorkspace, pumpShell;

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1400, 900),
    const Size(320, 640),
  ]) {
    testWidgets(
      'live scoring, undo, weekly history and room protection at $size',
      (tester) async {
        final workspace = await loadedWorkspace();
        addTearDown(workspace.dispose);
        await pumpShell(tester, workspace, size, edit: false);
        final canvas = tester.widget<RoomCanvas>(find.byType(RoomCanvas));
        final editor = canvas.controller;
        editor.seatRemaining();
        await tester.pumpAndSettle();
        final seated = editor.layout.seats.firstWhere(
          (d) => editor.studentAt(d.id) != null,
        );
        final student = editor.studentAt(seated.id)!;
        Offset seatPoint() =>
            tester.getTopLeft(find.byType(RoomCanvas)) +
            canvas.view.toScreen(seated.center);
        await tester.tapAt(seatPoint());
        await tester.pumpAndSettle();
        expect(find.text(student.fullName), findsOneWidget);
        final beforeScoring = seatPoint();
        await tester.tap(find.text('Add 1'));
        await tester.pumpAndSettle();
        expect(
          seatPoint(),
          beforeScoring,
          reason: 'Scoring must not move the seat targets',
        );
        expect(workspace.participation.single.delta, 1);
        expect(workspace.participation.single.studentId, student.id);
        await tester.tap(find.text('Deduct 1'));
        await tester.pumpAndSettle();
        expect(workspace.participation.length, 2);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(workspace.participation.length, 1);
        await tester.tap(find.text('Tap −1'));
        await tester.pumpAndSettle();
        await tester.tapAt(seatPoint());
        await tester.pumpAndSettle();
        expect(workspace.participation.length, 2);
        expect(workspace.participation.last.delta, -1);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.dragFrom(seatPoint(), const Offset(50, 30));
        await tester.pumpAndSettle();
        expect(editor.studentAt(seated.id)?.id, student.id);
        expect(editor.layout.deskById(seated.id)!.center, seated.center);
        await tester.tap(find.byTooltip('Weekly points'));
        await tester.pumpAndSettle();
        expect(find.text('Weekly participation'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Previous week'));
        await tester.pumpAndSettle();
        expect(find.text('0 pts'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
