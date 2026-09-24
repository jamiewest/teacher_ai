import '../../common/ids.dart';

/// Why a tag exists. The category is what a future AI layer keys off of when
/// it decides whether a tag should pull students together or push them apart.
enum TagCategory {
  behavior('Behavior'),
  academic('Academic'),
  social('Social'),
  accessibility('Accessibility'),
  language('Language'),
  custom('Custom');

  const TagCategory(this.label);
  final String label;

  static TagCategory fromJson(String value) => TagCategory.values.firstWhere(
    (c) => c.name == value,
    orElse: () => TagCategory.custom,
  );

  String toJson() => name;
}

/// How a tag should influence automatic seating.
///
/// This is deliberately structured rather than free text: the seating engine
/// (and later the AI) reads [SeatingHint], not the tag's display label.
enum SeatingHint {
  none('No preference'),
  frontOfRoom('Seat near the front'),
  nearTeacher('Seat near the teacher'),
  lowDistraction('Seat away from high-traffic areas'),
  needsPartner('Pair with a supportive peer'),
  separateFromSameTag('Keep apart from others with this tag'),
  anchorsGroup('Can anchor a group as a helper');

  const SeatingHint(this.label);
  final String label;

  static SeatingHint fromJson(String value) => SeatingHint.values.firstWhere(
    (h) => h.name == value,
    orElse: () => SeatingHint.none,
  );

  String toJson() => name;
}

/// A teacher-defined label applied to students, e.g. "Talks a lot" or
/// "Needs extra help".
///
/// Tags are first-class records with stable ids so assignment history stays
/// meaningful after a tag is renamed.
class StudentTag {
  const StudentTag({
    required this.id,
    required this.label,
    this.category = TagCategory.custom,
    this.hint = SeatingHint.none,
    this.description = '',
    this.colorValue = 0xFF6D7A8C,
  });

  StudentTag.create({
    required this.label,
    this.category = TagCategory.custom,
    this.hint = SeatingHint.none,
    this.description = '',
    this.colorValue = 0xFF6D7A8C,
  }) : id = newId();

  final String id;
  final String label;
  final TagCategory category;
  final SeatingHint hint;

  /// Optional teacher note giving the tag context; surfaced to the AI later.
  final String description;
  final int colorValue;

  StudentTag copyWith({
    String? label,
    TagCategory? category,
    SeatingHint? hint,
    String? description,
    int? colorValue,
  }) => StudentTag(
    id: id,
    label: label ?? this.label,
    category: category ?? this.category,
    hint: hint ?? this.hint,
    description: description ?? this.description,
    colorValue: colorValue ?? this.colorValue,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'category': category.toJson(),
    'hint': hint.toJson(),
    'description': description,
    'colorValue': colorValue,
  };

  factory StudentTag.fromJson(Map<String, Object?> json) => StudentTag(
    id: json['id']! as String,
    label: json['label']! as String,
    category: TagCategory.fromJson(json['category'] as String? ?? 'custom'),
    hint: SeatingHint.fromJson(json['hint'] as String? ?? 'none'),
    description: json['description'] as String? ?? '',
    colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF6D7A8C,
  );
}
