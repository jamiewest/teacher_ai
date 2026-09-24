/// Grade levels a student can belong to. A single class section may mix
/// several grade levels, so this lives on the student rather than the class.
enum GradeLevel {
  prek('PK', 'Pre-K', -1),
  kindergarten('K', 'Kindergarten', 0),
  grade1('1', '1st Grade', 1),
  grade2('2', '2nd Grade', 2),
  grade3('3', '3rd Grade', 3),
  grade4('4', '4th Grade', 4),
  grade5('5', '5th Grade', 5),
  grade6('6', '6th Grade', 6),
  grade7('7', '7th Grade', 7),
  grade8('8', '8th Grade', 8),
  grade9('9', '9th Grade', 9),
  grade10('10', '10th Grade', 10),
  grade11('11', '11th Grade', 11),
  grade12('12', '12th Grade', 12);

  const GradeLevel(this.code, this.label, this.ordinal);

  /// Short code used in dense UI (chips, seat cards).
  final String code;

  /// Human readable label used in menus.
  final String label;

  /// Sortable ordinal; Pre-K is -1 so K stays 0.
  final int ordinal;

  static GradeLevel fromJson(String value) => GradeLevel.values.firstWhere(
    (g) => g.name == value,
    orElse: () => GradeLevel.grade6,
  );

  String toJson() => name;
}
