import '../../common/ids.dart';

/// What happens during a block of the teaching day.
enum PeriodKind {
  classTime('Class'),
  passing('Passing'),
  lunch('Lunch'),
  recess('Recess'),
  prep('Prep'),
  duty('Duty');

  const PeriodKind(this.label);
  final String label;

  /// Breaks between classes are everything that is not instruction.
  bool get isBreak => this != PeriodKind.classTime;

  static PeriodKind fromJson(String value) => PeriodKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => PeriodKind.classTime,
  );

  String toJson() => name;
}

/// Minutes since midnight, kept as a plain int so it serializes cleanly and
/// never drags a timezone into a schedule that is purely local wall-clock.
class TimeOfDayMinutes implements Comparable<TimeOfDayMinutes> {
  const TimeOfDayMinutes(this.minutes);
  const TimeOfDayMinutes.at(int hour, int minute)
    : minutes = hour * 60 + minute;

  final int minutes;

  static TimeOfDayMinutes? tryParse(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return TimeOfDayMinutes.at(hour, minute);
  }

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  String format({bool use24Hour = false}) {
    if (use24Hour) {
      return '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
    }
    final suffix = hour < 12 ? 'AM' : 'PM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  int compareTo(TimeOfDayMinutes other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) =>
      other is TimeOfDayMinutes && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;
}

/// One block on the daily schedule — either a class or a break between
/// classes.
class SchedulePeriod {
  const SchedulePeriod({
    required this.id,
    required this.name,
    required this.kind,
    required this.start,
    required this.end,
    this.classSectionId,
    this.weekdays = const [1, 2, 3, 4, 5],
    this.dayTimes = const {},
  });

  SchedulePeriod.create({
    required this.name,
    required this.kind,
    required this.start,
    required this.end,
    this.classSectionId,
    this.weekdays = const [1, 2, 3, 4, 5],
    this.dayTimes = const {},
  }) : id = newId();

  final String id;
  final String name;
  final PeriodKind kind;
  final TimeOfDayMinutes start;
  final TimeOfDayMinutes end;

  /// Set only when [kind] is [PeriodKind.classTime].
  final String? classSectionId;

  final List<int> weekdays;

  /// Overrides retain the same period and roster identity across the week.
  final Map<int, PeriodTimes> dayTimes;

  SchedulePeriod? onDate(DateTime date) {
    if (!weekdays.contains(date.weekday)) return null;
    final times = dayTimes[date.weekday];
    return times == null ? this : copyWith(start: times.start, end: times.end);
  }

  int get durationMinutes => end.minutes - start.minutes;

  SchedulePeriod copyWith({
    String? name,
    PeriodKind? kind,
    TimeOfDayMinutes? start,
    TimeOfDayMinutes? end,
    String? classSectionId,
    bool clearSection = false,
    List<int>? weekdays,
    Map<int, PeriodTimes>? dayTimes,
  }) => SchedulePeriod(
    id: id,
    weekdays: weekdays ?? this.weekdays,
    dayTimes: dayTimes ?? this.dayTimes,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    start: start ?? this.start,
    end: end ?? this.end,
    classSectionId: clearSection
        ? null
        : (classSectionId ?? this.classSectionId),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.toJson(),
    'start': start.minutes,
    'end': end.minutes,
    'classSectionId': classSectionId,
    'weekdays': weekdays,
    'dayTimes': {
      for (final e in dayTimes.entries) '${e.key}': e.value.toJson(),
    },
  };

  factory SchedulePeriod.fromJson(Map<String, Object?> json) => SchedulePeriod(
    weekdays: (json['weekdays'] as List<Object?>? ?? [1, 2, 3, 4, 5])
        .cast<int>(),
    dayTimes: {
      for (final e in (json['dayTimes'] as Map<String, Object?>? ?? {}).entries)
        int.parse(e.key): PeriodTimes.fromJson(
          e.value! as Map<String, Object?>,
        ),
    },
    id: json['id']! as String,
    name: json['name']! as String,
    kind: PeriodKind.fromJson(json['kind'] as String? ?? 'classTime'),
    start: TimeOfDayMinutes((json['start'] as num?)?.toInt() ?? 0),
    end: TimeOfDayMinutes((json['end'] as num?)?.toInt() ?? 0),
    classSectionId: json['classSectionId'] as String?,
  );
}

class PeriodTimes {
  const PeriodTimes(this.start, this.end);
  final TimeOfDayMinutes start;
  final TimeOfDayMinutes end;
  Map<String, Object?> toJson() => {'start': start.minutes, 'end': end.minutes};
  factory PeriodTimes.fromJson(Map<String, Object?> json) => PeriodTimes(
    TimeOfDayMinutes((json['start']! as num).toInt()),
    TimeOfDayMinutes((json['end']! as num).toInt()),
  );
}

DateTime schoolDate(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime weekStart(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + 1);
// UTC arithmetic counts calendar days across daylight-saving changes.
int calendarDaysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
