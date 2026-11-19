import 'dart:convert';

import 'package:extensions/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/data/key_value_store.dart';
import 'package:teacher_ai/data/teacher_repository.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';
import 'package:teacher_ai/data/workspace_document.dart';
import 'package:teacher_ai/domain/models/models.dart';
import 'package:teacher_ai/domain/ops/layout_presets.dart';

void main() {
  late TeacherWorkspace workspace;
  late StoredTeacherRepository repository;
  late ClassSection section;
  setUp(() async {
    repository = StoredTeacherRepository(
      InMemoryStore(),
      NullLoggerFactory.instance,
    );
    workspace = TeacherWorkspace(repository, NullLoggerFactory.instance);
    await workspace.load();
    section = workspace.classes.first;
    for (final p in workspace.periods.toList()) {
      workspace.deletePeriod(p.id);
    }
  });
  tearDown(() => workspace.dispose());

  SchedulePeriod period({String id = 'p4', int start = 720, int end = 780}) =>
      SchedulePeriod(
        id: id,
        name: 'Period 4',
        kind: PeriodKind.classTime,
        start: TimeOfDayMinutes(start),
        end: TimeOfDayMinutes(end),
        classSectionId: section.id,
        dayTimes: const {
          3: PeriodTimes(TimeOfDayMinutes(660), TimeOfDayMinutes(700)),
        },
      );

  test('Wednesday early release uses override with exclusive end boundary', () {
    workspace.savePeriod(period());
    expect(
      workspace.currentClass(DateTime(2026, 10, 7, 11, 30))?.id,
      section.id,
    );
    expect(workspace.currentPeriod(DateTime(2026, 10, 7, 11, 40)), isNull);
    expect(workspace.currentPeriod(DateTime(2026, 10, 6, 11, 30)), isNull);
    expect(
      workspace.currentClass(DateTime(2026, 10, 6, 12, 0))?.id,
      section.id,
    );
    expect(workspace.currentPeriod(DateTime(2026, 10, 10, 12, 30)), isNull);
  });

  test(
    'school year, holidays, breaks, and ambiguous periods do not infer a class',
    () {
      workspace.savePeriod(period());
      workspace.setSchoolYear(DateTime(2026, 9, 1), DateTime(2027, 6, 15));
      expect(workspace.schoolWeek(DateTime(2026, 9, 7)), 2);
      expect(workspace.currentPeriod(DateTime(2026, 8, 25, 12, 10)), isNull);
      expect(workspace.currentPeriod(DateTime(2027, 6, 16, 11, 30)), isNull);
      workspace.setDayOff(DateTime(2026, 10, 7), true);
      expect(workspace.currentClass(DateTime(2026, 10, 7, 11, 30)), isNull);
      workspace.setDayOff(DateTime(2026, 10, 7), false);
      expect(workspace.currentClass(DateTime(2026, 10, 7, 11, 30)), isNotNull);
      workspace.upsertPeriod(period(id: 'legacy-overlap'));
      expect(workspace.currentClass(DateTime(2026, 10, 7, 11, 30)), isNull);
      workspace.deletePeriod('legacy-overlap');
      workspace.upsertPeriod(period().copyWith(kind: PeriodKind.prep));
      expect(workspace.currentClass(DateTime(2026, 10, 7, 11, 30)), isNull);
    },
  );

  test(
    'overlaps rejected, adjacent periods allowed and overrides validated',
    () {
      workspace.savePeriod(period());
      expect(
        () => workspace.savePeriod(period(id: 'overlap')),
        throwsArgumentError,
      );
      workspace.savePeriod(
        period(id: 'next', start: 780, end: 840).copyWith(dayTimes: {}),
      );
      expect(
        () => workspace.savePeriod(period().copyWith(weekdays: [])),
        throwsArgumentError,
      );
      expect(
        () => workspace.savePeriod(
          period().copyWith(
            dayTimes: const {
              3: PeriodTimes(TimeOfDayMinutes(700), TimeOfDayMinutes(660)),
            },
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'dated points separate classes and weeks, undo removes only its entry',
    () async {
      workspace.savePeriod(period());
      final student = section.studentIds.first;
      final other = ClassSection.create(
        name: 'Other',
        subjectId: section.subjectId,
        studentIds: [student],
      );
      workspace.upsertClass(other);
      final a = workspace.addParticipation(
        studentId: student,
        classSectionId: section.id,
        delta: 1,
        at: DateTime(2026, 10, 7, 11, 30),
      );
      workspace.addParticipation(
        studentId: student,
        classSectionId: section.id,
        delta: -1,
        at: DateTime(2026, 10, 8, 12, 30),
      );
      workspace.addParticipation(
        studentId: student,
        classSectionId: other.id,
        delta: 1,
        at: DateTime(2026, 10, 8),
      );
      workspace.addParticipation(
        studentId: student,
        classSectionId: section.id,
        delta: 1,
        at: DateTime(2026, 10, 12),
      );
      expect(a.periodId, 'p4');
      expect(
        workspace.participationTotal(
          student,
          section.id,
          DateTime(2026, 10, 5),
          DateTime(2026, 10, 12),
        ),
        0,
      );
      workspace.undoParticipation(a.id);
      workspace.undoParticipation(a.id);
      expect(
        workspace.participationTotal(
          student,
          section.id,
          DateTime(2026, 10, 5),
          DateTime(2026, 10, 12),
        ),
        -1,
      );
      workspace.setSchoolYear(DateTime(2026, 9), DateTime(2027, 6, 15));
      workspace.setDayOff(DateTime(2026, 12, 25), true);
      await workspace.flush();
      final restored = (await repository.load())!;
      expect(restored.participation.length, 3);
      expect(restored.schoolYearStart, DateTime(2026, 9));
      expect(restored.daysOff, [DateTime(2026, 12, 25)]);
      expect(restored.periods.single.dayTimes[3]!.start.minutes, 660);
      expect(
        () => workspace.addParticipation(
          studentId: 'missing',
          classSectionId: section.id,
          delta: 1,
        ),
        throwsArgumentError,
      );
    },
  );

  test('old saved documents migrate without losing schedule or rosters', () {
    final legacy = period().toJson()
      ..remove('weekdays')
      ..remove('dayTimes');
    final document = WorkspaceDocument.fromJson(
      jsonDecode(
            jsonEncode({
              'periods': [legacy],
              'classes': [section.toJson()],
              'schemaVersion': 1,
            }),
          )
          as Map<String, Object?>,
    );
    expect(document.periods.single.weekdays, [1, 2, 3, 4, 5]);
    expect(document.periods.single.dayTimes, isEmpty);
    expect(document.participation, isEmpty);
    expect(document.classes.single.studentIds, section.studentIds);
  });

  test('desk pairs are twelve linked, nonoverlapping groups of two', () {
    final layout = buildPresetLayout(preset: 'pairs', name: 'Partners');
    expect(layout.seatCount, 24);
    expect(layout.groups.length, 12);
    for (final group in layout.groups) {
      final seats = layout.desksInGroup(group.id);
      expect(seats.length, 2);
      expect(seats[0].y, seats[1].y);
      expect(seats[0].rotation, 0);
      for (final seat in seats) {
        expect(seat.x - seat.width / 2, greaterThanOrEqualTo(0));
        expect(seat.x + seat.width / 2, lessThanOrEqualTo(layout.roomWidth));
        expect(seat.y + seat.height / 2, lessThanOrEqualTo(layout.roomHeight));
      }
    }
    expect(calendarDaysBetween(DateTime(2026, 3, 2), DateTime(2026, 3, 9)), 7);
  });
}
