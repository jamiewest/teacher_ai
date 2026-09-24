import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';
import 'package:teacher_ai/domain/models/models.dart';
import 'package:teacher_ai/domain/ops/layout_ops.dart';
import 'package:teacher_ai/features/seating/seating_editor_controller.dart';

import 'seating_editor_test.dart' show buildFixture, editorFor;

Future<(TeacherWorkspace, SeatingEditorController, DeskGroup)>
groupedEditor() async {
  final (workspace, section, layout) = await buildFixture();
  final editor = editorFor(workspace, section, layout)
    ..setSnapToGrid(false)
    ..selectOnly('seat0')
    ..toggleSelection('seat1');
  final group = editor.groupSelection(name: 'Blue team')!;
  addTearDown(editor.dispose);
  addTearDown(workspace.dispose);
  return (workspace, editor, group);
}

void main() {
  test('selecting a group replaces an unrelated selection', () async {
    final (_, editor, group) = await groupedEditor();
    editor.selectOnly('seat3');
    editor.selectGroup(group.id);
    expect(editor.selection, group.deskIds.toSet());
    expect(editor.selectedGroup?.id, group.id);
    editor.selectOnly('seat0');
    expect(editor.selectedGroup, isNull);
    editor.selectGroup(group.id, additive: true);
    expect(editor.selectedGroup?.id, group.id);
    editor.toggleSelection('seat3');
    expect(editor.selectedGroup, isNull);
  });

  test(
    'group drag stops at walls without changing its shape and can return',
    () async {
      final (_, editor, _) = await groupedEditor();
      final original = editor.layout;
      editor.beginInteraction();
      editor.dragSelectionTo('seat0', const Offset(2000, -500));
      final a = editor.layout.deskById('seat0')!;
      final b = editor.layout.deskById('seat1')!;
      expect(b.center - a.center, const Offset(100, 0));
      expect(b.bounds.right, closeTo(editor.layout.roomWidth, 0.001));
      expect(a.bounds.top, closeTo(0, 0.001));
      expect(editor.layout.deskById('seat3'), original.deskById('seat3'));
      editor.dragSelectionTo('seat0', original.deskById('seat0')!.center);
      editor.endInteraction();
      expect(editor.layout.deskById('seat0')!.center, const Offset(100, 300));
      expect(editor.layout.deskById('seat1')!.center, const Offset(200, 300));
    },
  );

  test(
    'group rotation preserves spacing and facing with a single undo',
    () async {
      final (workspace, editor, group) = await groupedEditor();
      final before = editor.layout;
      editor.beginInteraction();
      for (final angle in [15.0, 30.0, 60.0, 89.0]) {
        editor.rotateSelectionFromStart(angle);
      }
      editor.endInteraction();
      final desks = editor.layout.desksInGroup(group.id);
      expect(desks[0].center.dx, closeTo(150, 0.001));
      expect(desks[0].center.dy, closeTo(250, 0.001));
      expect(desks[1].center.dx, closeTo(150, 0.001));
      expect(desks[1].center.dy, closeTo(350, 0.001));
      expect(desks.map((desk) => desk.rotation), everyElement(90));
      expect(LayoutOps.centroidOf(desks), const Offset(150, 300));
      expect(workspace.layout(before.id), editor.layout);
      editor.undo();
      expect(editor.layout, before);
    },
  );

  test(
    'locked members prevent a group from being partially moved or rotated',
    () async {
      final (_, editor, _) = await groupedEditor();
      editor.toggleDeskLocked('seat0');
      final before = editor.layout;
      editor.moveSelectionBy(const Offset(100, 100));
      editor.rotateSelectionBy(90);
      editor.setSelectionRotation(90);
      editor.beginInteraction();
      editor.dragSelectionTo('seat1', const Offset(500, 500));
      editor.rotateSelectionFromStart(90);
      editor.endInteraction();
      expect(editor.layout, before);
      editor.setSelectionLocked(false);
      editor.rotateSelectionBy(90);
      expect(
        editor.selectedDesks.map((desk) => desk.rotation),
        everyElement(90),
      );
    },
  );

  test(
    'duplicating and deleting groups retains metadata and undo restores seating',
    () async {
      final (_, editor, group) = await groupedEditor();
      final student = editor.roster.first.id;
      editor.assignStudent('seat0', student);
      editor.togglePinned('seat0');
      editor.duplicateSelection();
      final copy = editor.selectedGroup!;
      expect(copy.id, isNot(group.id));
      expect(copy.name, 'Blue team (copy)');
      expect(copy.colorValue, group.colorValue);
      expect(copy.isKaganTeam, group.isKaganTeam);
      expect(copy.deskIds.toSet().intersection(group.deskIds.toSet()), isEmpty);
      expect(
        editor.selectedDesks.map((desk) => desk.groupId),
        everyElement(copy.id),
      );
      expect(editor.seating, {'seat0': student});
      editor.undo();
      expect(editor.layout.groups, hasLength(1));
      editor.redo();
      expect(editor.layout.groups, hasLength(2));
      editor.selectGroup(group.id);
      editor.deleteSelection();
      expect(editor.layout.groupById(group.id), isNull);
      expect(editor.seating, isEmpty);
      expect(editor.pinnedSeats, isEmpty);
      editor.undo();
      expect(editor.layout.groupById(group.id), isNotNull);
      expect(editor.seating, {'seat0': student});
      expect(editor.pinnedSeats, {'seat0'});
    },
  );

  test(
    'group size and shape edits affect only its members and undo together',
    () async {
      final (_, editor, _) = await groupedEditor();
      final before = editor.layout;
      editor.beginInteraction();
      editor.resizeSelection(width: 80);
      editor.resizeSelection(width: 100, height: 70);
      editor.endInteraction();
      expect(editor.selectedDesks.map((desk) => desk.width), everyElement(100));
      expect(editor.selectedDesks.map((desk) => desk.height), everyElement(70));
      expect(editor.layout.deskById('seat3'), before.deskById('seat3'));
      editor.undo();
      expect(editor.layout, before);
      editor.setSelectionShape(DeskShape.circle);
      expect(
        editor.selectedDesks.map((desk) => desk.shape),
        everyElement(DeskShape.circle),
      );
      editor.undo();
      expect(editor.layout, before);
    },
  );
}
