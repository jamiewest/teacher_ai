import '../../common/ids.dart';

/// A class the teacher meets with, e.g. "Period 3 - Algebra I".
///
/// A section teaches exactly one subject but may hold students from several
/// grade levels, which is why grade lives on [Student].
class ClassSection {
  const ClassSection({
    required this.id,
    required this.name,
    required this.subjectId,
    this.studentIds = const <String>[],
    this.layoutIds = const <String>[],
    this.activeLayoutId,
    this.roomName = '',
  });

  ClassSection.create({
    required this.name,
    required this.subjectId,
    this.studentIds = const <String>[],
    this.layoutIds = const <String>[],
    this.activeLayoutId,
    this.roomName = '',
  }) : id = newId();

  final String id;
  final String name;
  final String subjectId;
  final List<String> studentIds;

  /// Layouts saved for this section. A teacher keeps several — rows for
  /// assessments, pods for Kagan work — and switches between them.
  final List<String> layoutIds;

  /// The layout currently in use, if any.
  final String? activeLayoutId;
  final String roomName;

  int get size => studentIds.length;

  ClassSection copyWith({
    String? name,
    String? subjectId,
    List<String>? studentIds,
    List<String>? layoutIds,
    String? activeLayoutId,
    bool clearActiveLayout = false,
    String? roomName,
  }) => ClassSection(
    id: id,
    name: name ?? this.name,
    subjectId: subjectId ?? this.subjectId,
    studentIds: studentIds ?? this.studentIds,
    layoutIds: layoutIds ?? this.layoutIds,
    activeLayoutId: clearActiveLayout
        ? null
        : (activeLayoutId ?? this.activeLayoutId),
    roomName: roomName ?? this.roomName,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'subjectId': subjectId,
    'studentIds': studentIds,
    'layoutIds': layoutIds,
    'activeLayoutId': activeLayoutId,
    'roomName': roomName,
  };

  factory ClassSection.fromJson(Map<String, Object?> json) => ClassSection(
    id: json['id']! as String,
    name: json['name']! as String,
    subjectId: json['subjectId'] as String? ?? '',
    studentIds: (json['studentIds'] as List<Object?>? ?? const [])
        .map((e) => e! as String)
        .toList(growable: false),
    layoutIds: (json['layoutIds'] as List<Object?>? ?? const [])
        .map((e) => e! as String)
        .toList(growable: false),
    activeLayoutId: json['activeLayoutId'] as String?,
    roomName: json['roomName'] as String? ?? '',
  );
}
