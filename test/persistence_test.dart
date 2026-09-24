import 'package:extensions/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/data/key_value_store.dart';
import 'package:teacher_ai/data/seed_data.dart';
import 'package:teacher_ai/data/teacher_repository.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';
import 'package:teacher_ai/data/workspace_document.dart';
import 'package:teacher_ai/domain/models/models.dart';

void main() {
  group('workspace document', () {
    test('survives a full JSON round trip', () {
      final original = buildSeedWorkspace();
      final restored = WorkspaceDocument.fromJson(original.toJson());

      expect(restored.students, hasLength(original.students.length));
      expect(restored.tags, hasLength(original.tags.length));
      expect(restored.layouts, hasLength(original.layouts.length));

      final layoutBefore = original.layouts.last;
      final layoutAfter = restored.layouts.last;
      expect(layoutAfter.id, layoutBefore.id);
      expect(layoutAfter.desks, hasLength(layoutBefore.desks.length));
      expect(layoutAfter.groups, hasLength(layoutBefore.groups.length));

      // Desk placement is the thing that must not drift across a save.
      for (var i = 0; i < layoutBefore.desks.length; i++) {
        expect(layoutAfter.desks[i].x, layoutBefore.desks[i].x);
        expect(layoutAfter.desks[i].y, layoutBefore.desks[i].y);
        expect(layoutAfter.desks[i].rotation, layoutBefore.desks[i].rotation);
        expect(layoutAfter.desks[i].groupId, layoutBefore.desks[i].groupId);
      }
    });

    test('seeded groups resolve back to real desks', () {
      final doc = buildSeedWorkspace();
      final pods = doc.layouts.firstWhere((l) => l.groups.isNotEmpty);
      for (final group in pods.groups) {
        expect(pods.desksInGroup(group.id), hasLength(group.deskIds.length));
      }
    });

    test('an assignment round-trips with its seed and pins', () {
      final assignment = SeatingAssignment.create(
        layoutId: 'layout',
        classSectionId: 'class',
        seatToStudent: const {'seat0': 'student0'},
        name: 'Week 1',
        source: AssignmentSource.shuffle,
        seed: 1234,
        lockedDeskIds: const {'seat0'},
      );
      final restored = SeatingAssignment.fromJson(assignment.toJson());

      expect(restored.seed, 1234);
      expect(restored.lockedDeskIds, {'seat0'});
      expect(restored.seatToStudent, {'seat0': 'student0'});
      expect(restored.source, AssignmentSource.shuffle);
    });
  });

  group('repository', () {
    test('saves and reloads through the store', () async {
      final store = InMemoryStore();
      final repository = StoredTeacherRepository(
        store,
        NullLoggerFactory.instance,
      );

      expect(await repository.load(), isNull);

      final document = buildSeedWorkspace();
      await repository.save(document);

      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.students, hasLength(document.students.length));
    });

    test('a corrupt document falls back instead of throwing', () async {
      final store = InMemoryStore();
      await store.write(StoredTeacherRepository.storageKey, 'not json at all');

      final repository = StoredTeacherRepository(
        store,
        NullLoggerFactory.instance,
      );
      expect(await repository.load(), isNull);
    });
  });

  group('workspace', () {
    test('seeds a math class on first run', () async {
      final workspace = TeacherWorkspace(
        StoredTeacherRepository(InMemoryStore(), NullLoggerFactory.instance),
        NullLoggerFactory.instance,
      );
      await workspace.load();

      expect(workspace.isLoaded, isTrue);
      expect(workspace.classes, isNotEmpty);
      expect(workspace.layoutsFor(workspace.classes.first.id), hasLength(2));
      expect(
        workspace.subjects.any((s) => s.area == SubjectArea.math),
        isTrue,
      );
    });

    test('the seeded roster spans more than one grade level', () async {
      final workspace = TeacherWorkspace(
        StoredTeacherRepository(InMemoryStore(), NullLoggerFactory.instance),
        NullLoggerFactory.instance,
      );
      await workspace.load();

      final grades = workspace
          .rosterFor(workspace.classes.first.id)
          .map((s) => s.gradeLevel)
          .toSet();
      expect(grades.length, greaterThan(1));
    });

    test('deleting a tag strips it from every student', () async {
      final workspace = TeacherWorkspace(
        StoredTeacherRepository(InMemoryStore(), NullLoggerFactory.instance),
        NullLoggerFactory.instance,
      );
      await workspace.load();

      final tag = workspace.tags.first;
      expect(workspace.students.any((s) => s.hasTag(tag.id)), isTrue);

      workspace.deleteTag(tag.id);
      expect(workspace.tag(tag.id), isNull);
      expect(workspace.students.any((s) => s.hasTag(tag.id)), isFalse);
    });

    test('deleting a layout also clears its saved history', () async {
      final workspace = TeacherWorkspace(
        StoredTeacherRepository(InMemoryStore(), NullLoggerFactory.instance),
        NullLoggerFactory.instance,
      );
      await workspace.load();

      final layout = workspace.layouts.first;
      workspace.saveAssignment(
        SeatingAssignment.create(
          layoutId: layout.id,
          classSectionId: layout.classSectionId ?? '',
          seatToStudent: const {},
        ),
      );
      expect(workspace.historyForLayout(layout.id), hasLength(1));

      workspace.deleteLayout(layout.id);
      expect(workspace.layout(layout.id), isNull);
      expect(workspace.historyForLayout(layout.id), isEmpty);
    });
  });
}
