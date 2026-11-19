import 'package:collection/collection.dart';

import '../workspace_document.dart';

typedef Json = Map<String, dynamic>;
const sameValue = DeepCollectionEquality();
const collections = [
  'subjects',
  'tags',
  'students',
  'classes',
  'layouts',
  'assignments',
  'periods',
  'participation',
];

/// Layouts are a single record so a drag and its group changes stay atomic.
Map<String, Json> recordsOf(WorkspaceDocument document) {
  final json = document.toJson();
  return {
    for (final name in collections)
      for (final row in (json[name] as List).cast<Json>())
        '$name/${row['id']}': row,
    'calendar': {
      for (final key in ['schoolYearStart', 'schoolYearEnd', 'daysOff'])
        key: json[key],
    },
  };
}

WorkspaceDocument documentOf(Map<String, Json> records) =>
    WorkspaceDocument.fromJson({
      ...?records['calendar'],
      for (final name in collections)
        name: [
          for (final entry in records.entries)
            if (entry.key.startsWith('$name/')) entry.value,
        ],
    });
