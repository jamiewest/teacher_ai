import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/app/theme.dart';
import 'package:teacher_ai/features/roster/roster_page.dart';
import 'package:teacher_ai/features/schedule/schedule_page.dart';
import 'package:teacher_ai/features/seating/seating_page.dart';

import 'seating_page_widget_test.dart' show loadedWorkspace;

void main() {
  test('AppTheme configures responsive hover tooltip timing', () {
    expect(
      AppTheme.light().tooltipTheme.waitDuration,
      const Duration(milliseconds: 450),
    );
    expect(
      AppTheme.dark().tooltipTheme.waitDuration,
      const Duration(milliseconds: 450),
    );
  });

  testWidgets('SeatingPage exposes hover tooltips and live helper text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final workspace = await loadedWorkspace();
    addTearDown(workspace.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SeatingPage(
          workspace: workspace,
          section: workspace.classes.first,
          onPickClass: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Switch room layout or create one from a preset'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Tap a seat to select a student without scoring'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Tap any occupied seat to add 1 point'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Tap any occupied seat to deduct 1 point'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('View weekly point totals and timestamped entries'),
      findsOneWidget,
    );

    expect(find.text('Tap a seat to inspect or score.'), findsOneWidget);
    await tester.tap(find.text('Tap +1'));
    await tester.pumpAndSettle();
    expect(find.text('Tap any seat to immediately add +1.'), findsOneWidget);

    await tester.tap(find.text('Tap −1'));
    await tester.pumpAndSettle();
    expect(find.text('Tap any seat to immediately deduct −1.'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit seating'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Fill open seats while keeping existing placements'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Randomize seating while keeping pinned seats in place'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Save a snapshot of this seating arrangement to history'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('0 of 24 students seated in this layout'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Design room'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Add student desks, tables, or room fixtures'),
      findsOneWidget,
    );
    expect(find.byTooltip('Snap spacing when dragging desks'), findsOneWidget);
    expect(
      find.text(
        'Drag across desks or Shift-click to select several and align or group them.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('RosterPage exposes hover tooltips and helper copy', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final workspace = await loadedWorkspace();
    addTearDown(workspace.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RosterPage(
          workspace: workspace,
          section: workspace.classes.first,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Check or uncheck students enrolled in this class'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Create a student and assign them to classes'),
      findsOneWidget,
    );
    expect(
      find.text('Apply tags to students to guide shuffles (like front-of-room).'),
      findsOneWidget,
    );
  });

  testWidgets('SchedulePage exposes hover tooltips', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final workspace = await loadedWorkspace();
    addTearDown(workspace.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SchedulePage(workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Set start and end dates to number school weeks'),
      findsOneWidget,
    );
    expect(find.byTooltip('Jump back to today'), findsOneWidget);
    expect(
      find.byTooltip('Show every repeating period, including other weekdays'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Add a class period or break to your weekly schedule'),
      findsOneWidget,
    );
  });
}
