import 'package:extensions/dependency_injection.dart';
import 'package:extensions/logging.dart';

import '../data/key_value_store.dart';
import '../data/teacher_repository.dart';
import '../data/teacher_workspace.dart';

/// Registers the app's services with the host container.
///
/// Everything the seating editor needs is resolved from here, so a test can
/// swap the store for [InMemoryStore] without touching a widget.
extension TeacherServiceRegistration on ServiceCollection {
  ServiceCollection addTeacherServices({KeyValueStore? store}) {
    addSingleton<KeyValueStore>((_) => store ?? SharedPreferencesStore());

    addSingleton<TeacherRepository>(
      (sp) => StoredTeacherRepository(
        sp.getRequiredService<KeyValueStore>(),
        sp.getRequiredService<LoggerFactory>(),
      ),
    );

    addSingleton<TeacherWorkspace>(
      (sp) => TeacherWorkspace(
        sp.getRequiredService<TeacherRepository>(),
        sp.getRequiredService<LoggerFactory>(),
      ),
    );

    return this;
  }
}
