import '../../common/ids.dart';

/// A dated change, never a running total that gets reset at the end of a week.
class ParticipationEntry {
  const ParticipationEntry({
    required this.id,
    required this.studentId,
    required this.classSectionId,
    required this.delta,
    required this.occurredAt,
    this.periodId,
  });
  ParticipationEntry.create({
    required this.studentId,
    required this.classSectionId,
    required this.delta,
    required this.occurredAt,
    this.periodId,
  }) : id = newId();
  final String id;
  final String studentId;
  final String classSectionId;
  final String? periodId;
  final int delta;
  final DateTime occurredAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'studentId': studentId,
    'classSectionId': classSectionId,
    'delta': delta,
    'occurredAt': occurredAt.toIso8601String(),
    'periodId': periodId,
  };
  factory ParticipationEntry.fromJson(Map<String, Object?> json) =>
      ParticipationEntry(
        id: json['id']! as String,
        studentId: json['studentId']! as String,
        classSectionId: json['classSectionId']! as String,
        delta: (json['delta']! as num).toInt(),
        occurredAt: DateTime.parse(json['occurredAt']! as String),
        periodId: json['periodId'] as String?,
      );
}
