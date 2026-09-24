import '../../common/ids.dart';

/// Broad subject area. Math is the focus for now, but a teacher may teach
/// several subjects, so the rest are modelled from the start.
enum SubjectArea {
  math('Math'),
  ela('English / Language Arts'),
  science('Science'),
  socialStudies('Social Studies'),
  world('World Language'),
  arts('Arts'),
  pe('Physical Education'),
  other('Other');

  const SubjectArea(this.label);
  final String label;

  static SubjectArea fromJson(String value) => SubjectArea.values.firstWhere(
    (s) => s.name == value,
    orElse: () => SubjectArea.other,
  );

  String toJson() => name;
}

/// A subject the teacher teaches, e.g. "Algebra I" or "6th Grade Math".
class Subject {
  const Subject({
    required this.id,
    required this.name,
    this.area = SubjectArea.math,
    this.colorValue = 0xFF3B6EA5,
  });

  Subject.create({
    required this.name,
    this.area = SubjectArea.math,
    this.colorValue = 0xFF3B6EA5,
  }) : id = newId();

  final String id;
  final String name;
  final SubjectArea area;

  /// ARGB color used to tint schedule blocks and class cards.
  final int colorValue;

  Subject copyWith({String? name, SubjectArea? area, int? colorValue}) =>
      Subject(
        id: id,
        name: name ?? this.name,
        area: area ?? this.area,
        colorValue: colorValue ?? this.colorValue,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'area': area.toJson(),
    'colorValue': colorValue,
  };

  factory Subject.fromJson(Map<String, Object?> json) => Subject(
    id: json['id']! as String,
    name: json['name']! as String,
    area: SubjectArea.fromJson(json['area'] as String? ?? 'math'),
    colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF3B6EA5,
  );
}
