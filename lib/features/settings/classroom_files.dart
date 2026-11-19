import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/classroom_backup.dart';
import '../../data/teacher_workspace.dart';
import '../../data/workspace_document.dart';

class ClassroomFiles extends StatefulWidget {
  const ClassroomFiles({
    required this.workspace,
    this.importBackup,
    this.readLegacy,
    this.deleteAccount,
    super.key,
  });
  final TeacherWorkspace workspace;
  final VoidCallback? deleteAccount;
  final Future<void> Function(WorkspaceDocument)? importBackup;
  final Future<String?> Function()? readLegacy;

  @override
  State<ClassroomFiles> createState() => _ClassroomFilesState();
}

class _ClassroomFilesState extends State<ClassroomFiles> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    String? result;
    try {
      result = await action();
    } on FormatException catch (error) {
      result = error.message;
    } on TypeError {
      result = 'The file contains an invalid classroom record.';
    } catch (_) {
      result =
          'Could not finish the file operation. Check storage and try again.';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = result;
        });
      }
    }
  }

  Future<String?> _export() async {
    final bytes = utf8.encode(jsonEncode(widget.workspace.snapshot.toJson()));
    await FilePicker.saveFile(
      fileName: 'teacher-ai-classroom.json',
      mimeType: 'application/json',
      bytes: bytes,
    );
    return null;
  }

  Future<String?> _import({required bool fromDevice}) async {
    String? text;
    if (fromDevice) {
      text = await widget.readLegacy!();
      if (text == null) return 'No local classroom was found on this device.';
    } else {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return null;
      text = utf8.decode(await file.readAsBytes());
    }
    final incoming = readClassroomBackup(text);
    // Check again inside the SQLite transaction when the teacher confirms.
    mergeClassroomBackup(widget.workspace.snapshot, incoming);
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import into your signed-in classroom?'),
        content: Text(
          'This backup contains ${incoming.classes.length} classes, ${incoming.students.length} students, ${incoming.layouts.length} layouts, ${incoming.assignments.length} saved charts, and ${incoming.participation.length} participation entries. New records will sync to your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return null;
    await widget.importBackup!(incoming);
    return 'Classroom import verified on this device.';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Tooltip(
        message: 'Download a JSON backup of your classes, layouts, and history',
        excludeFromSemantics: true,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download),
          title: const Text('Export classroom file'),
          onTap: _busy ? null : () => _run(_export),
        ),
      ),
      if (widget.importBackup != null) ...[
        Tooltip(
          message: 'Merge a saved classroom JSON file into this account',
          excludeFromSemantics: true,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file),
            title: const Text('Import classroom file'),
            onTap: _busy ? null : () => _run(() => _import(fromDevice: false)),
          ),
        ),
        if (widget.readLegacy != null)
          Tooltip(
            message: 'Bring in a local classroom saved on this device',
            excludeFromSemantics: true,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices),
              title: const Text('Import local classroom on this device'),
              onTap: _busy ? null : () => _run(() => _import(fromDevice: true)),
            ),
          ),
      ],
      if (widget.deleteAccount != null)
        Tooltip(
          message: 'Permanently erase your cloud classroom and account',
          excludeFromSemantics: true,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_remove_outlined),
            title: const Text('Delete account'),
            onTap: _busy
                ? null
                : () {
                    Navigator.pop(context);
                    widget.deleteAccount!();
                  },
          ),
        ),
      if (_message != null) Semantics(liveRegion: true, child: Text(_message!)),
    ],
  );
}
