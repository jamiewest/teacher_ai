import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Creates a stable identifier for a persisted entity.
///
/// Ids are opaque and never recycled; tags and assignments in particular are
/// referenced by id so that a future AI layer can reason about them across
/// renames.
String newId() => _uuid.v4();
