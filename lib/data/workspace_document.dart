import '../domain/models/models.dart';

/// Everything one teacher owns, as a single serializable document.
///
/// A teacher's data is small — a few hundred students at most — so one
/// document keeps reads atomic and avoids cross-collection drift. If this ever
/// outgrows a single blob, the repository is the only thing that changes.
class WorkspaceDocument {
  const WorkspaceDocument({
    this.subjects = const <Subject>[],
    this.students = const <Student>[],
    this.tags = const <StudentTag>[],
    this.classes = const <ClassSection>[],
    this.layouts = const <RoomLayout>[],
    this.assignments = const <SeatingAssignment>[],
    this.periods = const <SchedulePeriod>[],
  });

  /// Bumped whenever the on-disk shape changes incompatibly.
  static const int schemaVersion = 1;

  final List<Subject> subjects;
  final List<Student> students;
  final List<StudentTag> tags;
  final List<ClassSection> classes;
  final List<RoomLayout> layouts;

  /// Full assignment history, newest last.
  final List<SeatingAssignment> assignments;
  final List<SchedulePeriod> periods;

  WorkspaceDocument copyWith({
    List<Subject>? subjects,
    List<Student>? students,
    List<StudentTag>? tags,
    List<ClassSection>? classes,
    List<RoomLayout>? layouts,
    List<SeatingAssignment>? assignments,
    List<SchedulePeriod>? periods,
  }) => WorkspaceDocument(
    subjects: subjects ?? this.subjects,
    students: students ?? this.students,
    tags: tags ?? this.tags,
    classes: classes ?? this.classes,
    layouts: layouts ?? this.layouts,
    assignments: assignments ?? this.assignments,
    periods: periods ?? this.periods,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'subjects': subjects.map((e) => e.toJson()).toList(growable: false),
    'students': students.map((e) => e.toJson()).toList(growable: false),
    'tags': tags.map((e) => e.toJson()).toList(growable: false),
    'classes': classes.map((e) => e.toJson()).toList(growable: false),
    'layouts': layouts.map((e) => e.toJson()).toList(growable: false),
    'assignments': assignments.map((e) => e.toJson()).toList(growable: false),
    'periods': periods.map((e) => e.toJson()).toList(growable: false),
  };

  factory WorkspaceDocument.fromJson(Map<String, Object?> json) {
    List<T> parse<T>(String key, T Function(Map<String, Object?>) fromJson) =>
        (json[key] as List<Object?>? ?? const [])
            .map((e) => fromJson(e! as Map<String, Object?>))
            .toList(growable: false);

    return WorkspaceDocument(
      subjects: parse('subjects', Subject.fromJson),
      students: parse('students', Student.fromJson),
      tags: parse('tags', StudentTag.fromJson),
      classes: parse('classes', ClassSection.fromJson),
      layouts: parse('layouts', RoomLayout.fromJson),
      assignments: parse('assignments', SeatingAssignment.fromJson),
      periods: parse('periods', SchedulePeriod.fromJson),
    );
  }
}
