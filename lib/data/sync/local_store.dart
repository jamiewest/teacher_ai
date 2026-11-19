import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../common/ids.dart';
import '../classroom_backup.dart';
import '../workspace_document.dart';
import 'records.dart';

/// Local values and their last acknowledged server revisions are kept together.
/// A frozen request survives a lost response, even if the teacher keeps editing.
class Replica extends GeneratedDatabase {
  Replica(super.executor);
  factory Replica.forAccount(String account) => Replica(
    driftDatabase(
      name:
          'teacher_${base64Url.encode(utf8.encode(account)).replaceAll('=', '')}',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
        onResult: (result) {
          if ([
            WasmStorageImplementation.inMemory,
            WasmStorageImplementation.unsafeIndexedDb,
          ].contains(result.chosenImplementation)) {
            throw StateError(
              'Persistent classroom storage is unavailable in this browser.',
            );
          }
        },
      ),
    ),
  );

  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE records (key TEXT PRIMARY KEY, value TEXT, revision INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 0)',
      );
      await customStatement(
        'CREATE TABLE state (id INTEGER PRIMARY KEY, cursor INTEGER NOT NULL, request TEXT)',
      );
      await customStatement('INSERT INTO state VALUES (1, 0, NULL)');
      await _addGeneration();
    },
    onUpgrade: (_, from, _) async {
      if (from < 2) await _addGeneration();
    },
  );

  Future<void> _addGeneration() => customStatement(
    "ALTER TABLE state ADD COLUMN generation TEXT NOT NULL DEFAULT 'classroom'",
  );

  Future<String> get generation async => (await customSelect(
    'SELECT generation FROM state',
  ).getSingle()).read<String>('generation');

  Future<bool> replaceAfterRestore(
    String generation,
    Json snapshot, {
    bool discardPending = false,
  }) => transaction(() async {
    if (!discardPending && await freeze() != null) return false;
    await erase();
    await pull(snapshot);
    await customStatement('UPDATE state SET generation=?', [generation]);
    return true;
  });

  Future<WorkspaceDocument> document() async {
    final rows = await customSelect(
      'SELECT key, value FROM records WHERE value IS NOT NULL ORDER BY rowid',
    ).get();
    return documentOf({
      for (final row in rows)
        row.read<String>('key'): jsonDecode(row.read<String>('value')) as Json,
    });
  }

  Future<void> edit(
    WorkspaceDocument before,
    WorkspaceDocument after,
  ) => transaction(() async {
    final old = recordsOf(before);
    final next = recordsOf(after);
    for (final key in {...old.keys, ...next.keys}) {
      if (sameValue.equals(old[key], next[key])) continue;
      await customStatement(
        'INSERT INTO records(key,value,dirty) VALUES(?,?,1) ON CONFLICT(key) DO UPDATE SET value=excluded.value,dirty=1',
        [key, next[key] == null ? null : jsonEncode(next[key])],
      );
    }
  });

  Future<void> importBackup(
    WorkspaceDocument incoming,
  ) => transaction(() async {
    final before = await document();
    final merged = mergeClassroomBackup(before, incoming);
    await edit(before, merged);
    // Verify the persisted records before committing both the classroom and its pending edits.
    if (!sameValue.equals(recordsOf(merged), recordsOf(await document()))) {
      throw StateError('Could not verify the imported classroom.');
    }
  });

  Future<Json?> freeze() => transaction(() async {
    final existing = (await customSelect(
      'SELECT request FROM state',
    ).getSingle()).readNullable<String>('request');
    if (existing != null) return jsonDecode(existing) as Json;
    final rows = await customSelect(
      'SELECT * FROM records WHERE dirty=1 ORDER BY key',
    ).get();
    if (rows.isEmpty) return null;
    final request = {
      'operationId': newId(),
      'edits': [
        for (final row in rows)
          {
            'key': row.read<String>('key'),
            'revision': row.read<int>('revision'),
            'value': jsonDecode(row.readNullable<String>('value') ?? 'null'),
          },
      ],
    };
    await customStatement('UPDATE state SET request=?', [jsonEncode(request)]);
    return request;
  });

  Future<bool> _isCurrent(Json batch) async {
    final current = (await customSelect(
      'SELECT request FROM state',
    ).getSingle()).readNullable<String>('request');
    return current != null &&
        jsonDecode(current)['operationId'] == batch['operationId'];
  }

  Future<void> releaseRejected(Json batch) => transaction(() async {
    if (await _isCurrent(batch)) {
      await customStatement('UPDATE state SET request=NULL');
    }
  });

  Future<void> acknowledge(Json batch) => transaction(() async {
    if (!await _isCurrent(batch)) return;
    for (final edit in (batch['edits'] as List).cast<Json>()) {
      await customStatement(
        'UPDATE records SET revision=?, dirty=CASE WHEN value IS ? THEN 0 ELSE 1 END WHERE key=?',
        [
          (edit['revision'] as int) + 1,
          edit['value'] == null ? null : jsonEncode(edit['value']),
          edit['key'],
        ],
      );
    }
    await customStatement('UPDATE state SET request=NULL');
  });

  Future<int> get cursor async => (await customSelect(
    'SELECT cursor FROM state',
  ).getSingle()).read<int>('cursor');

  Future<void> pull(Json changes) => transaction(() async {
    // A local edit may arrive during the GET. Keep its original base revision
    // so the server will flag a concurrent edit instead of overwriting it.
    for (final row in (changes['records'] as List).cast<Json>()) {
      await customStatement(
        'INSERT INTO records(key,value,revision) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,revision=excluded.revision WHERE records.dirty=0 AND records.revision<=excluded.revision',
        [
          row['key'],
          row['value'] == null ? null : jsonEncode(row['value']),
          row['revision'],
        ],
      );
    }
    await customStatement('UPDATE state SET cursor=MAX(cursor,?)', [
      changes['cursor'],
    ]);
  });

  Future<void> resolve(Json batch, List<Json> conflicts, bool keepLocal) =>
      transaction(() async {
        if (!await _isCurrent(batch)) return;
        for (final row in conflicts) {
          if (keepLocal) {
            await customStatement('UPDATE records SET revision=? WHERE key=?', [
              row['revision'],
              row['key'],
            ]);
          } else {
            await customStatement(
              'UPDATE records SET revision=?,value=?,dirty=0 WHERE key=?',
              [
                row['revision'],
                row['value'] == null ? null : jsonEncode(row['value']),
                row['key'],
              ],
            );
          }
        }
        await customStatement('UPDATE state SET request=NULL');
      });

  Future<void> erase() => transaction(() async {
    await customStatement('DELETE FROM records');
    await customStatement('UPDATE state SET cursor=0,request=NULL');
  });
}
