import 'package:extensions/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teacher_ai/data/key_value_store.dart';
import 'package:teacher_ai/data/seed_data.dart';
import 'package:teacher_ai/data/teacher_repository.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';

void main() {
  // Every other test injects InMemoryStore, so this file is the only place
  // the real SharedPreferences-backed store gets exercised.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('SharedPreferencesStore reads back what it writes', () async {
    final store = SharedPreferencesStore();

    expect(await store.read('missing'), isNull);

    await store.write('k', 'hello');
    expect(await store.read('k'), 'hello');

    await store.write('k', 'replaced');
    expect(await store.read('k'), 'replaced');

    await store.remove('k');
    expect(await store.read('k'), isNull);
  });

  test('a workspace saved through SharedPreferences reloads intact', () async {
    final repository = StoredTeacherRepository(
      SharedPreferencesStore(),
      NullLoggerFactory.instance,
    );
    final document = buildSeedWorkspace();
    await repository.save(document);

    // A fresh store instance, as a page reload would produce.
    final reloaded = await StoredTeacherRepository(
      SharedPreferencesStore(),
      NullLoggerFactory.instance,
    ).load();

    expect(reloaded, isNotNull);
    expect(reloaded!.layouts, hasLength(document.layouts.length));
    expect(reloaded.students, hasLength(document.students.length));
  });

  test('a debounced desk move lands in storage', () async {
    final store = SharedPreferencesStore();
    final workspace = TeacherWorkspace(
      StoredTeacherRepository(store, NullLoggerFactory.instance),
      NullLoggerFactory.instance,
    );
    await workspace.load();

    final layout = workspace.layouts.first;
    final desk = layout.seats.first;
    workspace.upsertLayout(
      layout.copyWith(
        desks: [
          for (final d in layout.desks)
            if (d.id == desk.id) d.copyWith(x: desk.x + 123) else d,
        ],
      ),
    );

    // Wait past the debounce window, the way closing a tab would not.
    await Future<void>.delayed(TeacherWorkspace.saveDebounce * 2);

    final reloaded = await StoredTeacherRepository(
      store,
      NullLoggerFactory.instance,
    ).load();
    final persisted = reloaded!.layouts
        .firstWhere((l) => l.id == layout.id)
        .deskById(desk.id)!;

    expect(
      persisted.x,
      desk.x + 123,
      reason: 'the autosaved position must reach storage',
    );
  });
}
