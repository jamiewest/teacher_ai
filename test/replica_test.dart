import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/data/seed_data.dart';
import 'package:teacher_ai/data/sync/local_store.dart';
import 'package:teacher_ai/data/workspace_document.dart';

void main() {
  test(
    'an existing replica retains its frozen request when the sync generation is added',
    () async {
      final db = Replica(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute(
              'CREATE TABLE state (id INTEGER PRIMARY KEY, cursor INTEGER NOT NULL, request TEXT)',
            );
            sqlite.execute(
              'CREATE TABLE records (key TEXT PRIMARY KEY, value TEXT, revision INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 0)',
            );
            sqlite.execute('INSERT INTO state VALUES (1, 9, ?)', [
              '{"operationId":"pending","edits":[]}',
            ]);
            sqlite.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(db.close);
      expect(await db.generation, 'classroom');
      expect(await db.cursor, 9);
      expect((await db.freeze())?['operationId'], 'pending');
    },
  );

  test(
    'a restored server preserves pending edits until their replacement is confirmed',
    () async {
      final db = Replica(NativeDatabase.memory());
      addTearDown(db.close);
      final local = WorkspaceDocument(
        students: [buildSeedWorkspace().students.first],
      );
      await db.edit(const WorkspaceDocument(), local);
      final batch = await db.freeze();
      final restored = {'cursor': 0, 'records': <dynamic>[]};
      expect(await db.replaceAfterRestore('restore_1', restored), isFalse);
      expect(await db.generation, 'classroom');
      expect(await db.freeze(), batch);
      expect(
        await db.replaceAfterRestore(
          'restore_1',
          restored,
          discardPending: true,
        ),
        isTrue,
      );
      expect(await db.generation, 'restore_1');
      expect(await db.freeze(), isNull);
      expect((await db.document()).students, isEmpty);
      expect(await db.replaceAfterRestore('restore_2', restored), isTrue);
    },
  );

  test(
    'offline edit survives restart and edits made during a lost acknowledgement',
    () async {
      final dir = await Directory.systemTemp.createTemp();
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/classroom.sqlite');
      var replica = Replica(NativeDatabase(file));
      final student = buildSeedWorkspace().students.first;
      final first = WorkspaceDocument(students: [student]);
      await replica.edit(const WorkspaceDocument(), first);
      final pending = await replica.freeze();
      await replica.close();
      replica = Replica(NativeDatabase(file));
      addTearDown(() => replica.close());
      expect(await replica.freeze(), pending);
      expect((await replica.document()).students.single.id, student.id);
      final changed = student.copyWith(firstName: 'Updated');
      await replica.edit(first, WorkspaceDocument(students: [changed]));
      await replica.acknowledge(pending!);
      final next = (await replica.freeze())!;
      expect(next['operationId'], isNot(pending['operationId']));
      expect(next['edits'].single['revision'], 1);
      expect(next['edits'].single['value']['firstName'], 'Updated');
      await replica.acknowledge(pending);
      expect(await replica.freeze(), next);
      await replica.acknowledge(next);
      expect(await replica.freeze(), isNull);
    },
  );

  test(
    'remote pull retains dirty edits and conflict resolution adopts the selected version',
    () async {
      final db = Replica(NativeDatabase.memory());
      addTearDown(db.close);
      final student = buildSeedWorkspace().students.first;
      final row = {
        'key': 'students/${student.id}',
        'value': student.toJson(),
        'revision': 1,
      };
      await db.pull({
        'records': [row],
        'cursor': 1,
      });
      final initial = await db.document();
      await db.edit(
        initial,
        WorkspaceDocument(students: [student.copyWith(firstName: 'Local')]),
      );
      final batch = (await db.freeze())!;
      final remote = {
        ...row,
        'revision': 2,
        'value': student.copyWith(firstName: 'Remote').toJson(),
      };
      await db.pull({
        'cursor': 2,
        'records': [remote],
      });
      expect((await db.document()).students.single.firstName, 'Local');
      await db.resolve(batch, [remote], true);
      final retry = (await db.freeze())!;
      expect(retry['edits'].single['revision'], 2);
      await db.resolve(retry, [remote], false);
      expect(await db.freeze(), isNull);
      expect((await db.document()).students.single.firstName, 'Remote');
    },
  );
}
