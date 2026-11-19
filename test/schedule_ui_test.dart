import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/app/home_shell.dart';
import 'package:teacher_ai/app/theme.dart';
import 'package:teacher_ai/domain/models/models.dart';
import 'package:teacher_ai/domain/ops/layout_presets.dart';
import 'package:teacher_ai/features/schedule/schedule_page.dart';
import 'package:teacher_ai/features/seating/widgets/room_canvas.dart';
import 'seating_page_widget_test.dart' show loadedWorkspace;

void main() {
  testWidgets(
    'current class follows Wednesday times, preserves manual choice and holds edits',
    (tester) async {
      final workspace = await loadedWorkspace();
      addTearDown(workspace.dispose);
      for (final p in workspace.periods.toList()) {
        workspace.deletePeriod(p.id);
      }
      final first = workspace.classes.first;
      final second = ClassSection.create(
        name: 'Period 4 students',
        subjectId: first.subjectId,
      );
      workspace.upsertClass(second);
      final room = buildPresetLayout(
        preset: 'pairs',
        name: 'Partners',
        classSectionId: second.id,
      );
      workspace.addLayoutToClass(room, second.id);
      workspace.savePeriod(
        SchedulePeriod(
          id: 'p4',
          name: 'Period 4',
          kind: PeriodKind.classTime,
          start: const TimeOfDayMinutes(720),
          end: const TimeOfDayMinutes(780),
          classSectionId: second.id,
          dayTimes: const {
            3: PeriodTimes(TimeOfDayMinutes(660), TimeOfDayMinutes(700)),
          },
        ),
      );
      var now = DateTime(2026, 10, 7, 11, 30);
      tester.view
        ..physicalSize = const Size(1400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeShell(workspace: workspace, now: () => now),
        ),
      );
      await tester.pumpAndSettle();
      RoomCanvas canvas() => tester.widget<RoomCanvas>(find.byType(RoomCanvas));
      expect(canvas().controller.layout.id, room.id);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').startsWith('Following schedule'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('class-selector-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(workspace.classLabel(first)));
      await tester.pumpAndSettle();
      expect(canvas().controller.layout.classSectionId, first.id);
      await tester.pump(const Duration(seconds: 16));
      expect(canvas().controller.layout.classSectionId, first.id);
      expect(find.byTooltip('Manual class selection'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('class-selector-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow current period'));
      await tester.pumpAndSettle();
      expect(canvas().controller.layout.id, room.id);
      await tester.tap(find.byTooltip('Edit seating'));
      await tester.pumpAndSettle();
      now = DateTime(2026, 10, 7, 11, 40);
      await tester.pump(const Duration(seconds: 16));
      expect(canvas().controller.layout.id, room.id);
      expect(find.byTooltip('Class held while editing'), findsOneWidget);
      await tester.tap(find.byTooltip('Live classroom'));
      await tester.pumpAndSettle();
      expect(canvas().controller.layout.classSectionId, first.id);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1400.0]) {
    testWidgets('schedule day controls and period editor fit $width', (
      tester,
    ) async {
      final workspace = await loadedWorkspace();
      addTearDown(workspace.dispose);
      tester.view
        ..physicalSize = Size(width, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SchedulePage(workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('day-off')));
      await tester.pumpAndSettle();
      expect(workspace.daysOff.single.weekday, 3);
      expect(find.textContaining('No periods on this day'), findsOneWidget);
      await tester.tap(find.text('Edit all periods'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No periods on this day'), findsNothing);
      await tester.tap(find.text('Add period'));
      await tester.pumpAndSettle();
      expect(find.text('Repeats on'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
