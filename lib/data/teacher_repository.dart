import 'dart:convert';

import 'package:extensions/logging.dart';

import 'key_value_store.dart';
import 'workspace_document.dart';

/// Loads and saves the teacher's workspace document.
abstract interface class TeacherRepository {
  Future<WorkspaceDocument?> load();
  Future<void> save(WorkspaceDocument document);
  Future<void> clear();
}

/// Stores the whole workspace as one JSON blob in a [KeyValueStore].
class StoredTeacherRepository implements TeacherRepository {
  StoredTeacherRepository(this._store, LoggerFactory loggerFactory)
    : _logger = loggerFactory.createLogger('TeacherRepository');

  static const String storageKey = 'teacher_ai.workspace.v1';

  final KeyValueStore _store;
  final Logger _logger;

  @override
  Future<WorkspaceDocument?> load() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) {
      _logger.logInformation('No saved workspace found; starting fresh.');
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final document = WorkspaceDocument.fromJson(json);
      _logger.logInformation(
        'Loaded workspace: ${document.classes.length} classes, '
        '${document.layouts.length} layouts, '
        '${document.students.length} students.',
      );
      return document;
    } on Object catch (error) {
      // A corrupt document should not brick the app; fall back to seed data
      // and leave the bad copy in place so it can be recovered manually.
      _logger.logError(
        'Failed to parse saved workspace; starting fresh.',
        error: error,
      );
      return null;
    }
  }

  @override
  Future<void> save(WorkspaceDocument document) async {
    await _store.write(storageKey, jsonEncode(document.toJson()));
    _logger.logDebug('Workspace saved.');
  }

  @override
  Future<void> clear() => _store.remove(storageKey);
}
