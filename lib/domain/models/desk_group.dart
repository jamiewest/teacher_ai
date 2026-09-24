import '../../common/ids.dart';

/// A named cluster of desks — "Group 1", "Team Blue", a Kagan team.
///
/// Groups are how Kagan structures get expressed spatially: a team of four
/// facing inward gives every student a shoulder partner and a face partner,
/// which several structures depend on.
class DeskGroup {
  const DeskGroup({
    required this.id,
    required this.name,
    this.deskIds = const <String>[],
    this.colorValue = 0xFF4C8C7B,
    this.isKaganTeam = false,
  });

  DeskGroup.create({
    required this.name,
    this.deskIds = const <String>[],
    this.colorValue = 0xFF4C8C7B,
    this.isKaganTeam = false,
  }) : id = newId();

  final String id;
  final String name;

  /// Desks belonging to this group, in seat order.
  final List<String> deskIds;
  final int colorValue;

  /// Marks the group as a Kagan team, which implies a target size of four and
  /// enables shoulder/face partner roles.
  final bool isKaganTeam;

  int get seatCount => deskIds.length;

  DeskGroup copyWith({
    String? name,
    List<String>? deskIds,
    int? colorValue,
    bool? isKaganTeam,
  }) => DeskGroup(
    id: id,
    name: name ?? this.name,
    deskIds: deskIds ?? this.deskIds,
    colorValue: colorValue ?? this.colorValue,
    isKaganTeam: isKaganTeam ?? this.isKaganTeam,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'deskIds': deskIds,
    'colorValue': colorValue,
    'isKaganTeam': isKaganTeam,
  };

  factory DeskGroup.fromJson(Map<String, Object?> json) => DeskGroup(
    id: json['id']! as String,
    name: json['name']! as String,
    deskIds: (json['deskIds'] as List<Object?>? ?? const [])
        .map((e) => e! as String)
        .toList(growable: false),
    colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF4C8C7B,
    isKaganTeam: json['isKaganTeam'] as bool? ?? false,
  );
}

/// Palette cycled through when new groups are created so adjacent groups stay
/// visually distinct.
const kGroupColors = <int>[
  0xFF4C8C7B,
  0xFF3B6EA5,
  0xFFB4713D,
  0xFF8B5FA8,
  0xFF3F7D4C,
  0xFFA8495C,
  0xFF5C6BC0,
  0xFF8A7B3F,
];
