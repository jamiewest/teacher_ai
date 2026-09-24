import 'package:extensions/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/data/key_value_store.dart';
import 'package:teacher_ai/data/teacher_repository.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';
import 'package:teacher_ai/domain/models/models.dart';
import 'package:teacher_ai/domain/ops/layout_ops.dart';
import 'package:teacher_ai/features/seating/seating_editor_controller.dart';

/// Builds a workspace backed by memory, with one class and one simple layout.
Future<(TeacherWorkspace, ClassSection, RoomLayout)> buildFixture() async {
  final workspace = TeacherWorkspace(
    StoredTeacherRepository(InMemoryStore(), NullLoggerFactory.instance),
    NullLoggerFactory.instance,
  );
  await workspace.load();

  final students = [
    for (var i = 0; i < 4; i++)
      Student.create(
        firstName: 'Kid$i',
        lastName: 'Test',
        gradeLevel: GradeLevel.grade6,
      ),
  ];
  for (final s in students) {
    workspace.upsertStudent(s);
  }

  final layout = RoomLayout.create(
    name: 'Test room',
    desks: [
      for (var i = 0; i < 4; i++)
        Desk(id: 'seat$i', x: 100.0 + i * 100, y: 300),
    ],
  );
  final section = ClassSection.create(
    name: 'Test class',
    subjectId: 'subject',
    studentIds: students.map((s) => s.id).toList(),
    layoutIds: [layout.id],
  );
  workspace
    ..upsertClass(section)
    ..upsertLayout(layout);

  return (workspace, section, layout);
}

SeatingEditorController editorFor(
  TeacherWorkspace workspace,
  ClassSection section,
  RoomLayout layout,
) => SeatingEditorController(
  workspace: workspace,
  layout: layout,
  classSectionId: section.id,
);

void main() {
  group('undo and redo', () {
    test('a move is undoable back to the original position', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout);

      expect(editor.canUndo, isFalse);
      editor
        ..selectOnly('seat0')
        ..beginInteraction()
        ..dragSelectionTo('seat0', const Offset(400, 400))
        ..endInteraction();

      expect(editor.layout.deskById('seat0')!.x, isNot(100));
      expect(editor.canUndo, isTrue);

      editor.undo();
      expect(editor.layout.deskById('seat0')!.x, 100);
      expect(editor.canRedo, isTrue);

      editor.redo();
      expect(editor.layout.deskById('seat0')!.x, isNot(100));
    });

    test('a whole drag collapses into one undo step', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..selectOnly('seat0')
        ..beginInteraction();

      // Simulates the stream of updates a real drag produces.
      for (var i = 1; i <= 10; i++) {
        editor.dragSelectionTo('seat0', Offset(100.0 + i * 10, 300));
      }
      editor.endInteraction();

      editor.undo();
      expect(editor.layout.deskById('seat0')!.x, 100);
      expect(editor.canUndo, isFalse, reason: 'one gesture, one history entry');
    });

    test('deleting a desk also drops its student and pin', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout);
      final studentId = editor.roster.first.id;

      editor
        ..assignStudent('seat0', studentId)
        ..togglePinned('seat0')
        ..selectOnly('seat0')
        ..deleteSelection();

      expect(editor.layout.deskById('seat0'), isNull);
      expect(editor.seating.containsKey('seat0'), isFalse);
      expect(editor.pinnedSeats, isEmpty);
    });
  });

  group('dragging', () {
    test('snapping is measured from the gesture start, not the last frame',
        () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..setSnapToGrid(true)
        ..selectOnly('seat0')
        ..beginInteraction();

      // Many small moves that each snap; the result must still land exactly on
      // the grid nearest the final pointer position.
      for (var i = 1; i <= 20; i++) {
        editor.dragSelectionTo('seat0', Offset(100.0 + i * 3.7, 300));
      }
      editor.endInteraction();

      final desk = editor.layout.deskById('seat0')!;
      final grid = editor.layout.gridSize;
      expect(desk.x % grid, closeTo(0, 0.001));
      expect(desk.x, closeTo(LayoutOps.snapPoint(const Offset(174, 300), 15).dx, 0.001));
    });

    test('a multi-desk drag keeps the spacing between desks', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..selectOnly('seat0')
        ..toggleSelection('seat1')
        ..beginInteraction()
        ..dragSelectionTo('seat0', const Offset(250, 450))
        ..endInteraction();

      final a = editor.layout.deskById('seat0')!;
      final b = editor.layout.deskById('seat1')!;
      expect(b.x - a.x, closeTo(100, 0.001));
      expect(b.y - a.y, closeTo(0, 0.001));
    });

    test('a locked desk does not move', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..toggleDeskLocked('seat0')
        ..selectOnly('seat0')
        ..beginInteraction()
        ..dragSelectionTo('seat0', const Offset(500, 500))
        ..endInteraction();

      expect(editor.layout.deskById('seat0')!.x, 100);
    });
  });

  group('grouping', () {
    test('names a selection and tags its desks with the group', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..selectOnly('seat0')
        ..toggleSelection('seat1');

      final group = editor.groupSelection(name: 'Group 1');
      expect(group, isNotNull);
      expect(editor.layout.groups, hasLength(1));
      expect(editor.layout.deskById('seat0')!.groupId, group!.id);
      expect(editor.layout.desksInGroup(group.id), hasLength(2));
    });

    test('a desk joining a new group leaves its old one', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..selectOnly('seat0')
        ..toggleSelection('seat1');
      final first = editor.groupSelection(name: 'Group 1')!;

      editor
        ..selectOnly('seat1')
        ..toggleSelection('seat2');
      final second = editor.groupSelection(name: 'Group 2')!;

      expect(editor.layout.deskById('seat1')!.groupId, second.id);
      expect(editor.layout.groupById(first.id)!.deskIds, ['seat0']);
    });

    test('ungrouping removes an emptied group entirely', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..selectOnly('seat0')
        ..toggleSelection('seat1');
      editor
        ..groupSelection(name: 'Group 1')
        ..selectOnly('seat0')
        ..toggleSelection('seat1')
        ..ungroupSelection();

      expect(editor.layout.groups, isEmpty);
      expect(editor.layout.deskById('seat0')!.groupId, isNull);
    });
  });

  group('seating', () {
    test('a student can only sit in one seat', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout);
      final studentId = editor.roster.first.id;

      editor
        ..assignStudent('seat0', studentId)
        ..assignStudent('seat2', studentId);

      expect(editor.seating.containsKey('seat0'), isFalse);
      expect(editor.seating['seat2'], studentId);
    });

    test('shuffle is undoable as a single step', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..assignStudent('seat0', '');
      editor.clearAllSeats();

      final before = Map.of(editor.seating);
      editor.shuffleSeating(seed: 12);
      expect(editor.seating, isNot(equals(before)));

      editor.undo();
      expect(editor.seating, equals(before));
    });

    test('saving an arrangement appends to the workspace history', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..shuffleSeating(seed: 4);

      final saved = editor.saveAssignment(
        name: 'Week 1',
        source: AssignmentSource.shuffle,
      );

      expect(workspace.historyForLayout(layout.id), hasLength(1));
      expect(saved.seed, isNotNull, reason: 'a shuffle records its seed');
      expect(saved.seatToStudent, equals(editor.seating));

      // History is append-only: a second save does not replace the first.
      editor.saveAssignment(name: 'Week 2');
      expect(workspace.historyForLayout(layout.id), hasLength(2));
    });

    test('restoring a past arrangement puts those students back', () async {
      final (workspace, section, layout) = await buildFixture();
      final editor = editorFor(workspace, section, layout)
        ..shuffleSeating(seed: 8);
      final first = editor.saveAssignment(name: 'First');

      editor.shuffleSeating(seed: 9);
      editor.applyAssignment(first);

      expect(editor.seating, equals(first.seatToStudent));
    });
  });

  test('resizing the room pulls stray desks back inside', () async {
    final (workspace, section, layout) = await buildFixture();
    final editor = editorFor(workspace, section, layout)
      ..setRoomSize(width: 400, height: 400);

    for (final desk in editor.layout.desks) {
      expect(desk.bounds.right, lessThanOrEqualTo(400.001));
      expect(desk.bounds.bottom, lessThanOrEqualTo(400.001));
    }
  });
}
