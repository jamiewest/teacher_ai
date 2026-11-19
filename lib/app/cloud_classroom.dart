import 'dart:async';
import 'dart:convert';

import 'package:extensions/logging.dart';
import 'package:flutter/material.dart';

import '../data/key_value_store.dart';
import '../data/sync/cloud_api.dart';
import '../data/sync/cloud_repository.dart';
import '../data/sync/local_store.dart';
import '../data/sync/records.dart';
import '../data/teacher_workspace.dart';
import '../data/teacher_repository.dart';
import '../features/settings/classroom_files.dart';
import 'app_settings.dart';
import 'home_shell.dart';
import 'classroom_sign_in.dart';

class CloudClassroom extends StatefulWidget {
  const CloudClassroom({
    super.key,
    required this.settings,
    required this.loggerFactory,
    required this.store,
  });
  final AppSettingsController settings;
  final LoggerFactory loggerFactory;
  final KeyValueStore store;
  @override
  State<CloudClassroom> createState() => _CloudClassroomState();
}

class _CloudClassroomState extends State<CloudClassroom>
    with WidgetsBindingObserver {
  final _api = CloudApi();
  static const _key = 'teacher.cloud.account';
  CloudRepository? _repo;
  TeacherWorkspace? _workspace;
  Timer? _poll;
  bool _busy = true;
  Future<void>? _removal;
  String? _error;
  String? _cachedAccount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  Future<void> _restore({bool login = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (login) await _api.signIn();
      final cached = _cachedAccount = await widget.store.read(_key);
      String account;
      try {
        account = await _api.identity();
      } on ApiFailure catch (error) {
        if (error.deletedAccount != null &&
            error.deletedAccount == (_api.account ?? cached)) {
          await _removeDeletedAccount(error.deletedAccount!);
          return;
        }
        // A public tunnel can return a gateway error while the Pi is offline.
        if (login || cached == null || error.status < 500) rethrow;
        account = cached;
      } catch (_) {
        if (login || cached == null) rethrow;
        account = cached;
      }
      if (_repo != null && account != _api.account) {
        throw StateError('Sign out before switching classrooms.');
      }
      _api.account = account;
      if (_repo == null) {
        final repo = CloudRepository(Replica.forAccount(account), _api);
        repo.onAccountDeleted = () => unawaited(_removeDeletedAccount(account));
        final workspace = TeacherWorkspace(repo, widget.loggerFactory);
        await workspace.load();
        await widget.store.write(_key, account);
        _cachedAccount = account;
        _repo = repo;
        _workspace = workspace;
        _poll = Timer.periodic(const Duration(seconds: 15), (_) => repo.sync());
      }
      unawaited(_repo!.sync());
    } on ApiFailure catch (e) {
      if (e.deletedAccount != null) {
        _error = 'This classroom has been deleted.';
      } else if (e.status != 401) {
        _error = 'Could not reach the classroom service.';
      }
    } catch (_) {
      _error =
          'Could not open the classroom. Check sign-in, connectivity, and device storage.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _repo?.sync();
  }

  Future<void> _signOut() async {
    final repo = _repo!;
    setState(() => _busy = true);
    try {
      await repo.flush();
      await repo.sync();
      if (await repo.db.freeze() != null) {
        setState(() => _error = 'Sync your pending edits before signing out.');
        return;
      }
      await _api.signOut();
      await _clearReplica(repo);
      _error = null;
    } catch (_) {
      _error = 'Sign-out could not finish. Reconnect and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearReplica(
    CloudRepository repo, {
    bool discardPending = false,
  }) async {
    _poll?.cancel();
    repo.onAccountDeleted = null;
    await repo.stop(discardPending: discardPending);
    await repo.db.erase();
    await widget.store.remove(_key);
    _cachedAccount = null;
    await repo.db.close();
    _workspace?.dispose();
    repo.dispose();
    _workspace = null;
    _repo = null;
  }

  Future<void> _removeDeletedAccount(String account) =>
      _removal ??= _finishRemoval(account).whenComplete(() => _removal = null);

  Future<void> _clearDeviceCopy() async {
    final account = _cachedAccount;
    if (account == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the classroom from this device?'),
        content: const Text(
          'This erases the saved copy and any unsynced edits on this device. Your online account stays available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove device copy'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await (_removal ??= _finishRemoval(
        account,
        deviceOnly: true,
      ).whenComplete(() => _removal = null));
    }
  }

  Future<void> _finishRemoval(String account, {bool deviceOnly = false}) async {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _busy = true);
    try {
      if (_repo case final repo?) {
        await _clearReplica(repo, discardPending: true);
      } else {
        final db = Replica.forAccount(account);
        try {
          await db.erase();
          await widget.store.remove(_key);
          _cachedAccount = null;
        } finally {
          await db.close();
        }
      }
      await _api.forgetSession();
      _error = deviceOnly
          ? 'The classroom was removed from this device.'
          : 'Your classroom was deleted. Account removal has been requested.';
    } catch (_) {
      _error =
          'Could not finish clearing this device. Reopen the app to retry.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete your account?'),
        content: const Text(
          'Your classroom and pending edits on this device will be erased. Export a classroom file first if you want a copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _api.account == null) return;
    final account = _api.account!;
    setState(() => _busy = true);
    try {
      // Refresh the browser antiforgery token and confirm the active identity.
      if (await _api.identity() != account) throw StateError('Account changed');
      await _api.call('account', delete: true);
      await _removeDeletedAccount(account);
    } on ApiFailure catch (error) {
      if (error.deletedAccount == account) {
        await _removeDeletedAccount(account);
      } else {
        _error =
            'Account deletion could not be confirmed. Reconnect and try again.';
      }
    } catch (_) {
      _error =
          'Account deletion could not be confirmed. Reconnect and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadRestored() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reload the restored classroom?'),
        content: const Text(
          'This replaces your device copy, including pending edits. You can export it first in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reload'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo!.acceptRestoredClassroom();
    } catch (_) {
      _error = 'Could not load the restored classroom. Reconnect and retry.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final repo = _repo!;
    final local = recordsOf(await repo.db.document());
    if (!mounted) return;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review concurrent edits'),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              for (final row in repo.conflicts)
                '${row['key']}\nOn this device: ${jsonEncode(local[row['key']])}\nOn the server: ${jsonEncode(row['value'])}',
            ].join('\n\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Use server edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keep device edits'),
          ),
        ],
      ),
    );
    if (choice != null) await repo.resolve(choice);
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    if (_busy && repo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (repo == null) {
      return ClassroomSignIn(
        message: _error,
        onSignIn: () => _restore(login: true),
        onRemoveCopy: _cachedAccount == null ? null : _clearDeviceCopy,
      );
    }
    return AbsorbPointer(
      absorbing: _busy,
      child: Column(
        children: [
          Expanded(
            child: HomeShell(
              workspace: _workspace!,
              settings: widget.settings,
              classroomFiles: ClassroomFiles(
                workspace: _workspace!,
                importBackup: repo.importBackup,
                deleteAccount: _deleteAccount,
                readLegacy: () =>
                    widget.store.read(StoredTeacherRepository.storageKey),
              ),
              accountSettings: _AccountSettings(
                repo: repo,
                onSignOut: _signOut,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: repo,
            builder: (context, _) {
              final message = _error ?? repo.status;
              if (_error == null &&
                  const {
                    'Synced',
                    'Opening classroom',
                    'Saved on this device',
                  }.contains(message)) {
                return const SizedBox.shrink();
              }
              final signIn = repo.status.toLowerCase().contains('sign in');
              return Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(message),
                          ),
                        ),
                        if (repo.restorePending)
                          Tooltip(
                            message:
                                'Replace this device’s copy with the restored server classroom',
                            excludeFromSemantics: true,
                            child: TextButton(
                              onPressed: _reloadRestored,
                              child: const Text('Reload'),
                            ),
                          )
                        else if (repo.conflicts.isNotEmpty)
                          Tooltip(
                            message:
                                'Compare edits made on this device and another device',
                            excludeFromSemantics: true,
                            child: TextButton(
                              onPressed: _review,
                              child: const Text('Review'),
                            ),
                          ),
                        if (signIn)
                          Tooltip(
                            message: 'Sign in again to resume syncing',
                            excludeFromSemantics: true,
                            child: TextButton(
                              onPressed: () => _restore(login: true),
                              child: const Text('Sign in'),
                            ),
                          ),
                        if (signIn && _cachedAccount != null)
                          IconButton(
                            tooltip: 'Remove device copy',
                            onPressed: _clearDeviceCopy,
                            icon: const Icon(Icons.phonelink_erase),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    final repo = _repo;
    if (repo != null) {
      repo.onRemote = null;
      unawaited(repo.stop().then((_) => repo.db.close()));
    }
    _workspace?.dispose();
    _api.dispose();
    super.dispose();
  }
}

class _AccountSettings extends StatefulWidget {
  const _AccountSettings({required this.repo, required this.onSignOut});

  final CloudRepository repo;
  final VoidCallback onSignOut;

  @override
  State<_AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<_AccountSettings> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await widget.repo.sync();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListenableBuilder(
        listenable: widget.repo,
        builder: (context, _) => Tooltip(
          message: 'Upload local edits and check for updates from other devices',
          excludeFromSemantics: true,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _syncing
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            title: const Text('Sync now'),
            subtitle: Text(_syncing ? 'Syncing…' : widget.repo.status),
            onTap: _syncing ? null : _sync,
          ),
        ),
      ),
      Tooltip(
        message: 'Sign out and clear this account’s local copy after syncing',
        excludeFromSemantics: true,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () {
            Navigator.pop(context);
            widget.onSignOut();
          },
        ),
      ),
    ],
  );
}
