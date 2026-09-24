import '../../common/ids.dart';
import 'grade_level.dart';

/// A student on a roster. Students belong to the teacher, not to a class, so
/// the same student can appear in more than one class section.
class Student {
  const Student({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.gradeLevel,
    this.tagIds = const <String>[],
    this.notes = '',
  });

  Student.create({
    required this.firstName,
    required this.lastName,
    required this.gradeLevel,
    this.tagIds = const <String>[],
    this.notes = '',
  }) : id = newId();

  final String id;
  final String firstName;
  final String lastName;
  final GradeLevel gradeLevel;

  /// Ids of [StudentTag]s applied to this student.
  final List<String> tagIds;
  final String notes;

  String get fullName => '$firstName $lastName'.trim();

  /// "Jordan L." — what fits on a desk at normal zoom.
  String get shortName {
    if (lastName.isEmpty) return firstName;
    return '$firstName ${lastName[0]}.';
  }

  /// Initials used when a desk is too small for a name.
  String get initials {
    final first = firstName.isEmpty ? '' : firstName[0];
    final last = lastName.isEmpty ? '' : lastName[0];
    final value = '$first$last'.toUpperCase();
    return value.isEmpty ? '?' : value;
  }

  bool hasTag(String tagId) => tagIds.contains(tagId);

  Student copyWith({
    String? firstName,
    String? lastName,
    GradeLevel? gradeLevel,
    List<String>? tagIds,
    String? notes,
  }) => Student(
    id: id,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    gradeLevel: gradeLevel ?? this.gradeLevel,
    tagIds: tagIds ?? this.tagIds,
    notes: notes ?? this.notes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'gradeLevel': gradeLevel.toJson(),
    'tagIds': tagIds,
    'notes': notes,
  };

  factory Student.fromJson(Map<String, Object?> json) => Student(
    id: json['id']! as String,
    firstName: json['firstName'] as String? ?? '',
    lastName: json['lastName'] as String? ?? '',
    gradeLevel: GradeLevel.fromJson(json['gradeLevel'] as String? ?? 'grade6'),
    tagIds: (json['tagIds'] as List<Object?>? ?? const [])
        .map((e) => e! as String)
        .toList(growable: false),
    notes: json['notes'] as String? ?? '',
  );
}
