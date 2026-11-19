import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/data/classroom_backup.dart';
import 'package:teacher_ai/data/seed_data.dart';
import 'package:teacher_ai/data/sync/local_store.dart';
import 'package:teacher_ai/data/workspace_document.dart';

void main() {
  test(
    'reads the original schema and preserves IDs, desk groups and links',
    () {
      final sample = buildSeedWorkspace();
      final legacy = sample.toJson()
        ..remove('participation')
        ..remove('daysOff')
        ..remove('schoolYearStart')
        ..remove('schoolYearEnd');
      expect(readClassroomBackup(jsonEncode(legacy)).toJson(), sample.toJson());
    },
  );

  test('rejects unsupported, duplicate and dangling records before import', () {
    final sample = buildSeedWorkspace();
    final badClass = sample.classes.first.copyWith(studentIds: ['missing']);
    for (final bad in [
      {...sample.toJson(), 'schemaVersion': 2},
      sample
          .copyWith(students: [...sample.students, sample.students.first])
          .toJson(),
      sample.copyWith(classes: [badClass]).toJson(),
    ]) {
      expect(() => readClassroomBackup(jsonEncode(bad)), throwsFormatException);
    }
  });

  test(
    'reimport is idempotent, merge preserves edits, conflicting files roll back',
    () async {
      final db = Replica(NativeDatabase.memory());
      addTearDown(db.close);
      final sample = buildSeedWorkspace();
      final another = buildSeedWorkspace().students.first.copyWith(tagIds: []);
      await db.importBackup(WorkspaceDocument(students: [another]));
      await db.importBackup(sample);
      await db.acknowledge((await db.freeze())!);
      await db.importBackup(sample);
      expect(await db.freeze(), isNull);
      final before = await db.document();
      expect(before.students.length, sample.students.length + 1);
      final different = sample.copyWith(
        students: [sample.students.first.copyWith(firstName: 'Conflicting')],
      );
      await expectLater(db.importBackup(different), throwsFormatException);
      expect((await db.document()).toJson(), before.toJson());
      expect(await db.freeze(), isNull);
    },
  );
}
