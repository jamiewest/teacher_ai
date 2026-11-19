import 'dart:convert';

import 'sync/records.dart';
import 'workspace_document.dart';

/// Reads the same versioned JSON written by the original local app.
WorkspaceDocument readClassroomBackup(String text) {
  final data = jsonDecode(text);
  if (data is! Json ||
      data['schemaVersion'] != WorkspaceDocument.schemaVersion) {
    throw const FormatException(
      'Choose a version 1 Teacher AI classroom file.',
    );
  }
  for (final key in collections) {
    // Participation was added after the first version 1 documents shipped.
    if (key == 'participation' && !data.containsKey(key)) continue;
    final rows = data[key];
    if (rows is! List) throw FormatException('Missing or invalid $key list.');
    final ids = <String>{};
    for (final row in rows) {
      final id = row is Json ? row['id'] : null;
      if (id is! String ||
          id.trim().isEmpty ||
          id.contains('/') ||
          id.length + key.length + 1 > 180 ||
          !ids.add(id)) {
        throw FormatException(
          'A record in $key has a duplicate or invalid ID.',
        );
      }
      for (final field in ['createdAt', if (key == 'layouts') 'updatedAt']) {
        if ((key == 'layouts' || key == 'assignments') &&
            DateTime.tryParse('${row[field]}') == null) {
          throw FormatException('A date in $key is missing or invalid.');
        }
      }
    }
  }
  for (final field in ['schoolYearStart', 'schoolYearEnd']) {
    if (data[field] != null && DateTime.tryParse('${data[field]}') == null) {
      throw const FormatException('The school year contains an invalid date.');
    }
  }
  final document = WorkspaceDocument.fromJson(data);
  final rows = recordsOf(document);
  void requireLink(String collection, String? id) {
    if (id != null && !rows.containsKey('$collection/$id')) {
      throw FormatException(
        'The file refers to a missing record in $collection.',
      );
    }
  }

  for (final section in document.classes) {
    requireLink('subjects', section.subjectId);
    for (final id in section.studentIds) {
      requireLink('students', id);
    }
    for (final id in section.layoutIds) {
      requireLink('layouts', id);
    }
    requireLink('layouts', section.activeLayoutId);
  }
  for (final student in document.students) {
    for (final id in student.tagIds) {
      requireLink('tags', id);
    }
  }
  for (final layout in document.layouts) {
    requireLink('classes', layout.classSectionId);
    final desks = layout.desks.map((d) => d.id).toSet();
    final groups = layout.groups.map((g) => g.id).toSet();
    if (desks.length != layout.desks.length ||
        groups.length != layout.groups.length ||
        layout.groups.any((g) => g.deskIds.any((id) => !desks.contains(id))) ||
        layout.desks.any(
          (d) => d.groupId != null && !groups.contains(d.groupId),
        )) {
      throw const FormatException(
        'A room contains invalid desk or group links.',
      );
    }
  }
  for (final period in document.periods) {
    requireLink('classes', period.classSectionId);
  }
  // Historical seat/student/period IDs can outlive a desk, roster or period.
  for (final assignment in document.assignments) {
    requireLink('layouts', assignment.layoutId);
    requireLink('classes', assignment.classSectionId);
  }
  return document;
}

/// Adds records with stable IDs. Reimporting an identical file is a no-op.
/// A divergent copy requires teacher attention before any changes are written.
WorkspaceDocument mergeClassroomBackup(
  WorkspaceDocument current,
  WorkspaceDocument incoming,
) {
  final result = recordsOf(current);
  final emptyCalendar = recordsOf(const WorkspaceDocument())['calendar'];
  for (final entry in recordsOf(incoming).entries) {
    final existing = result[entry.key];
    if (sameValue.equals(existing, entry.value)) continue;
    if (entry.key == 'calendar' &&
        sameValue.equals(entry.value, emptyCalendar)) {
      continue;
    }
    if (existing != null &&
        !(entry.key == 'calendar' &&
            sameValue.equals(existing, emptyCalendar))) {
      final kind = entry.key.split('/').first;
      throw FormatException(
        'The file and this classroom contain different versions of $kind. Import cancelled.',
      );
    }
    result[entry.key] = entry.value;
  }
  return documentOf(result);
}
