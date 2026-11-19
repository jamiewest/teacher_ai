import 'dart:async';

import 'package:flutter/foundation.dart';

import '../teacher_repository.dart';
import '../workspace_document.dart';
import 'cloud_api.dart';
import 'local_store.dart';
import 'records.dart';

class CloudRepository extends ChangeNotifier
    implements SyncingTeacherRepository {
  CloudRepository(this.db, this.api);
  final Replica db;
  final CloudApi api;
  WorkspaceDocument _shown = const WorkspaceDocument();
  @override
  void Function(WorkspaceDocument)? onRemote;
  VoidCallback? onAccountDeleted;
  String status = 'Opening classroom';
  List<Json> conflicts = [];
  bool restorePending = false;
  Json? _conflictingBatch;
  Future<void> _writes = Future.value();
  Future<void>? _sync;
  int _generation = 0;
  Timer? _schedule;
  bool _closed = false;
  bool _writeFailed = false;

  void _status(String value) {
    status = value;
    if (!_closed) notifyListeners();
  }

  @override
  Future<WorkspaceDocument> load() async => _shown = await db.document();

  @override
  Future<void> save(WorkspaceDocument document) {
    final previous = _shown;
    _shown = document;
    _generation++;
    // Keep the last durable snapshot as the retry base if a disk write fails.
    _writes = _writes.then((_) async {
      final base = _writeFailed ? await db.document() : previous;
      try {
        await db.edit(base, document);
        _writeFailed = false;
      } catch (_) {
        _writeFailed = true;
        _status('Device save failed. Keep this app open and retry.');
        rethrow;
      }
    });
    final result = _writes;
    _writes = result.catchError((Object _) {});
    return result.then((_) {
      _status('Saved on this device');
      _schedule?.cancel();
      _schedule = Timer(const Duration(milliseconds: 400), sync);
    });
  }

  @override
  Future<void> flush() async {
    await _writes;
    if (_writeFailed) await save(_shown);
  }

  Future<void> importBackup(WorkspaceDocument incoming) async {
    await flush();
    await db.importBackup(incoming);
    await _refreshView();
    _status('Saved on this device');
    unawaited(sync());
  }

  @override
  Future<void> clear() async {
    // resetToSeed immediately calls save(), which records the replacements
    // and deletions in the same transaction.
  }

  Future<void> sync() => _sync ??= _exchange().whenComplete(() {
    _sync = null;
  });

  Future<void> _exchange() async {
    if (_closed) return;
    try {
      await flush();
      if (await api.identity() != api.account) {
        _status('Account changed. Sign in to this workspace again.');
        return;
      }
      if (await db.generation != api.generation) {
        if (!await _replaceRestoredClassroom()) return;
      }
      restorePending = false;
      final batch = await db.freeze();
      if (batch != null) {
        try {
          await api.call('mutations', body: batch);
        } on ApiFailure catch (e) {
          if (e.status == 422 || e.status == 400) {
            await db.releaseRejected(batch);
            await db.pull(await api.call('changes?after=${await db.cursor}'));
            await _refreshView();
            _status(
              'Server rejected the edit. Review roster memberships and tags.',
            );
            return;
          }
          if (e.status != 409) rethrow;
          final remote = await api.call('workspace');
          final revisions = {
            for (final edit in (batch['edits'] as List).cast<Json>())
              edit['key']: edit['revision'],
          };
          conflicts = (remote['records'] as List)
              .cast<Json>()
              .where(
                (row) =>
                    revisions.containsKey(row['key']) &&
                    revisions[row['key']] != row['revision'],
              )
              .toList();
          _conflictingBatch = batch;
          _status('Review concurrent edits');
          return;
        }
        await db.acknowledge(batch);
        conflicts = [];
      }
      final changes = await api.call('changes?after=${await db.cursor}');
      await db.pull(changes);
      await _refreshView();
      _status((await db.freeze()) == null ? 'Synced' : 'Saved on this device');
    } on ApiFailure catch (e) {
      if (e.deletedAccount != null && e.deletedAccount == api.account) {
        onAccountDeleted?.call();
        return;
      }
      _status(
        e.status == 401 || e.status == 403
            ? 'Sign in again to sync'
            : 'Sync failed. Edits stay on this device.',
      );
    } catch (_) {
      if (!_writeFailed) _status('Offline · edits stay on this device');
    }
  }

  Future<bool> _replaceRestoredClassroom({bool discardPending = false}) async {
    final generation = api.generation;
    if ((discardPending || await db.freeze() == null) &&
        await db.replaceAfterRestore(
          generation,
          await api.call('workspace'),
          discardPending: discardPending,
        )) {
      conflicts = [];
      _conflictingBatch = null;
      restorePending = false;
      await _refreshView();
      return true;
    }
    restorePending = true;
    _status('Server restored. Export your pending edits before reloading.');
    return false;
  }

  Future<void> acceptRestoredClassroom() async {
    await _sync;
    await flush();
    if (await api.identity() != api.account || !restorePending) return;
    if (await db.generation != api.generation) {
      await _replaceRestoredClassroom(discardPending: true);
    }
    await sync();
  }

  Future<void> _refreshView() async {
    final generation = _generation;
    await _writes;
    final document = await db.document();
    if (_closed || _writeFailed || _generation != generation) return;
    if (!sameValue.equals(document.toJson(), _shown.toJson())) {
      _shown = document;
      onRemote?.call(document);
    }
  }

  Future<void> resolve(bool keepLocal) async {
    await _sync;
    final batch = _conflictingBatch;
    if (batch == null) return;
    await flush();
    await db.resolve(batch, conflicts, keepLocal);
    conflicts = [];
    _conflictingBatch = null;
    await _refreshView();
    await sync();
  }

  Future<void> stop({bool discardPending = false}) async {
    _closed = true;
    _schedule?.cancel();
    await _sync;
    if (discardPending) {
      await _writes;
    } else {
      await flush();
    }
    _schedule?.cancel();
  }
}
