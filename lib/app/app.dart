import 'package:extensions_flutter/extensions_flutter.dart';
import 'package:flutter/material.dart';

import '../data/teacher_workspace.dart';
import 'home_shell.dart';
import 'theme.dart';

/// Root widget. Resolves the workspace from the host container and holds the
/// app on a splash until the saved data has loaded.
class TeacherApp extends StatefulWidget {
  const TeacherApp({required this.services, super.key});

  final ServiceProvider services;

  @override
  State<TeacherApp> createState() => _TeacherAppState();
}

class _TeacherAppState extends State<TeacherApp> {
  late final TeacherWorkspace _workspace = widget.services
      .getRequiredService<TeacherWorkspace>();
  late final Future<void> _ready = _workspace.load();
  FlutterApplicationLifetime? _lifetime;

  @override
  void initState() {
    super.initState();
    // Saves are debounced, so a tab closed mid-edit would drop the last few
    // hundred milliseconds of work. The host's lifecycle events are the hook
    // for forcing that write out.
    _lifetime =
        widget.services.getService<HostApplicationLifetime>()
            as FlutterApplicationLifetime?;
    _lifetime?.applicationPaused.add(_flush);
    _lifetime?.applicationDetached.add(_flush);
  }

  @override
  void dispose() {
    _lifetime?.applicationPaused.remove(_flush);
    _lifetime?.applicationDetached.remove(_flush);
    super.dispose();
  }

  void _flush() => _workspace.flush();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teacher AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _SplashScreen();
          }
          if (snapshot.hasError) {
            return _StartupError(error: snapshot.error!);
          }
          return HomeShell(workspace: _workspace);
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text('Loading your classroom…'),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                'Could not start',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
