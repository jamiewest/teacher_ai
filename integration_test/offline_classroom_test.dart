import 'dart:convert';

import 'package:extensions/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:teacher_ai/common/ids.dart';
import 'package:teacher_ai/data/classroom_backup.dart';
import 'package:teacher_ai/data/seed_data.dart';
import 'package:teacher_ai/data/sync/cloud_api.dart';
import 'package:teacher_ai/data/sync/cloud_repository.dart';
import 'package:teacher_ai/data/sync/local_store.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';
import 'package:teacher_ai/domain/models/models.dart';
import 'package:teacher_ai/features/seating/seating_editor_controller.dart';

class _DisconnectedApi extends CloudApi {
  @override
  Future<String> identity() async => throw StateError('Offline');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'manual classroom work survives reopening the native replica offline',
    (tester) async {
      final account = newId();
      final api = _DisconnectedApi()..account = account;
      final repo = CloudRepository(Replica.forAccount(account), api);
      final workspace = TeacherWorkspace(repo, NullLoggerFactory.instance);
      await workspace.load();
      final sample = buildSeedWorkspace();
      await repo.importBackup(readClassroomBackup(jsonEncode(sample.toJson())));
      final section = workspace.classes.first;
      final student = workspace.students.first.copyWith(firstName: 'Robin');
      workspace.saveStudent(student, classIds: {section.id});
      final period = workspace.periods.first;
      workspace.savePeriod(
        period.copyWith(name: 'Morning class', classSectionId: section.id),
      );
      final today = DateTime(2026, 11, 18);
      workspace.setSchoolYear(DateTime(2026, 8), DateTime(2027, 6));
      workspace.setDayOff(DateTime(2026, 11, 26), true);
      workspace.addParticipation(
        studentId: student.id,
        classSectionId: section.id,
        delta: 1,
        at: today,
      );
      final editor = SeatingEditorController(
        workspace: workspace,
        layout: workspace.layout(section.activeLayoutId!)!,
        classSectionId: section.id,
      );
      final desk = editor.layout.seats.first;
      editor.selectOnly(desk.id);
      editor.nudgeSelection(const Offset(1, 0));
      expect(editor.layout.deskById(desk.id)!.x, isNot(desk.x));
      editor.placeStudent(desk.id, student.id);
      editor.togglePinned(desk.id);
      editor.shuffleSeating(seed: 42);
      expect(workspace.assignments, isEmpty);
      final chart = editor.saveAssignment(
        name: 'Morning',
        source: AssignmentSource.shuffle,
      );
      final expected = workspace.snapshot.toJson();
      await workspace.flush();
      editor.dispose();
      workspace.dispose();
      await repo.stop();
      await repo.db.close();
      repo.dispose();

      final reopened = Replica.forAccount(account);
      try {
        final restored = await reopened.document();
        expect(restored.toJson(), expected);
        expect(restored.assignments.single.seatToStudent[desk.id], student.id);
        expect(restored.assignments.single.id, chart.id);
        expect(await reopened.freeze(), isNotNull);
      } finally {
        await reopened.erase();
        await reopened.close();
        api.dispose();
      }
    },
  );
}
