import 'package:extensions_flutter/extensions_flutter.dart';

import 'app/app.dart';
import 'app/service_registration.dart';

/// Boots the app on the `extensions` host, so Flutter, DI, logging, and
/// lifecycle all share one pipeline.
final _builder = Host.createApplicationBuilder()
  ..environment.applicationName = 'teacher_ai';

Future<void> main() async {
  _builder.logging
    ..addSimpleConsole()
    ..setMinimumLevel(LogLevel.information);

  _builder.services
    ..addTeacherServices()
    ..addFlutter((flutter) => flutter.runApp((services) => TeacherApp(services: services)));

  await _builder.build().run();
}
