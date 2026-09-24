import 'dart:async';

import 'package:collection/collection.dart';
import 'package:extensions/logging.dart';
import 'package:flutter/foundation.dart';

import '../domain/models/models.dart';
import 'seed_data.dart';
import 'teacher_repository.dart';
import 'workspace_document.dart';

/// The teacher's data, held in memory and persisted on change.
///
/// This is a [ChangeNotifier] registered as a DI singleton: the hosting stack
/// owns its lifetime, and widgets rebuild off it with [ListenableBuilder].
/// Keeping it a plain Listenable means every mutation stays unit-testable
/// without a widget tree.
class TeacherWorkspace extends ChangeNotifier {
  TeacherWorkspace(this._repository, LoggerFactory loggerFactory)
    : _logger = loggerFactory.createLogger('TeacherWorkspace');

  /// Writes are batched so dragging a desk does not hit storage per frame.
  static const Duration saveDebounce = Duration(milliseconds: 400);

  final TeacherRepository _repository;
  final Logger _logger;

  WorkspaceDocument _document = const WorkspaceDocument();
  Timer? _saveTimer;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<Subject> get subjects => _document.subjects;
  List<Student> get students => _document.students;
  List<StudentTag> get tags => _document.tags;
  List<ClassSection> get classes => _document.classes;
  List<RoomLayout> get layouts => _document.layouts;
  List<SeatingAssignment> get assignments => _document.assignments;
  List<SchedulePeriod> get periods => _document.periods;

  /// Tags keyed by id, for the seating rules and desk badges.
  Map<String, StudentTag> get tagsById => {for (final t in tags) t.id: t};

  Map<String, Student> get studentsById => {for (final s in students) s.id: s};

  Subject? subject(String id) => subjects.firstWhereOrNull((s) => s.id == id);
  Student? student(String id) => students.firstWhereOrNull((s) => s.id == id);
  StudentTag? tag(String id) => tags.firstWhereOrNull((t) => t.id == id);
  ClassSection? classSection(String id) =>
      classes.firstWhereOrNull((c) => c.id == id);
  RoomLayout? layout(String id) => layouts.firstWhereOrNull((l) => l.id == id);

  /// Students on a section's roster, in the roster's stored order.
  List<Student> rosterFor(String classSectionId) {
    final section = classSection(classSectionId);
    if (section == null) return const <Student>[];
    final byId = studentsById;
    return section.studentIds
        .map((id) => byId[id])
        .whereType<Student>()
        .toList(growable: false);
  }

  /// Layouts saved for a section, newest first.
  List<RoomLayout> layoutsFor(String classSectionId) =>
      layouts.where((l) => l.classSectionId == classSectionId).sorted(
        (a, b) => b.updatedAt.compareTo(a.updatedAt),
      );

  /// Assignment history for a layout, newest first.
  List<SeatingAssignment> historyForLayout(String layoutId) => assignments
      .where((a) => a.layoutId == layoutId)
      .sorted((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Assignment history for a class across all its layouts, newest first.
  List<SeatingAssignment> historyForClass(String classSectionId) => assignments
      .where((a) => a.classSectionId == classSectionId)
      .sorted((a, b) => b.createdAt.compareTo(a.createdAt));

  /// The arrangement currently in effect for a layout, if one was ever saved.
  SeatingAssignment? latestAssignment(String layoutId) =>
      historyForLayout(layoutId).firstOrNull;

  /// Periods in clock order, including the breaks between classes.
  List<SchedulePeriod> get orderedPeriods =>
      periods.sorted((a, b) => a.start.compareTo(b.start));

  /// Loads persisted data, seeding a sample math class on first run.
  Future<void> load() async {
    final stored = await _repository.load();
    if (stored == null) {
      _logger.logInformation('Seeding a starter workspace.');
      _document = buildSeedWorkspace();
      await _repository.save(_document);
    } else {
      _document = stored;
    }
    _loaded = true;
    notifyListeners();
  }

  // --- Mutations -----------------------------------------------------------

  void upsertSubject(Subject subject) =>
      _update(_document.copyWith(subjects: _upsert(subjects, subject, (e) => e.id)));

  void upsertStudent(Student student) =>
      _update(_document.copyWith(students: _upsert(students, student, (e) => e.id)));

  void upsertTag(StudentTag tag) =>
      _update(_document.copyWith(tags: _upsert(tags, tag, (e) => e.id)));

  void upsertClass(ClassSection section) =>
      _update(_document.copyWith(classes: _upsert(classes, section, (e) => e.id)));

  void upsertLayout(RoomLayout layout) =>
      _update(_document.copyWith(layouts: _upsert(layouts, layout, (e) => e.id)));

  void upsertPeriod(SchedulePeriod period) =>
      _update(_document.copyWith(periods: _upsert(periods, period, (e) => e.id)));

  /// Removes a tag and strips it from every student that carried it.
  void deleteTag(String tagId) {
    _update(
      _document.copyWith(
        tags: tags.where((t) => t.id != tagId).toList(growable: false),
        students: [
          for (final s in students)
            if (s.hasTag(tagId))
              s.copyWith(
                tagIds: s.tagIds.where((id) => id != tagId).toList(growable: false),
              )
            else
              s,
        ],
      ),
    );
  }

  /// Removes a student from the roster of every class and from the workspace.
  void deleteStudent(String studentId) {
    _update(
      _document.copyWith(
        students: students.where((s) => s.id != studentId).toList(growable: false),
        classes: [
          for (final c in classes)
            c.copyWith(
              studentIds:
                  c.studentIds.where((id) => id != studentId).toList(growable: false),
            ),
        ],
      ),
    );
  }

  /// Deletes a layout along with the assignment history that referenced it.
  void deleteLayout(String layoutId) {
    _update(
      _document.copyWith(
        layouts: layouts.where((l) => l.id != layoutId).toList(growable: false),
        assignments:
            assignments.where((a) => a.layoutId != layoutId).toList(growable: false),
        classes: [
          for (final c in classes)
            if (c.layoutIds.contains(layoutId) || c.activeLayoutId == layoutId)
              c.copyWith(
                layoutIds:
                    c.layoutIds.where((id) => id != layoutId).toList(growable: false),
                clearActiveLayout: c.activeLayoutId == layoutId,
              )
            else
              c,
        ],
      ),
    );
  }

  /// Adds a layout and links it to its class in one write.
  void addLayoutToClass(RoomLayout layout, String classSectionId) {
    final section = classSection(classSectionId);
    _update(
      _document.copyWith(
        layouts: _upsert(layouts, layout, (e) => e.id),
        classes: section == null
            ? classes
            : _upsert(
                classes,
                section.copyWith(
                  layoutIds: [...section.layoutIds, layout.id],
                  activeLayoutId: layout.id,
                ),
                (e) => e.id,
              ),
      ),
    );
  }

  void setActiveLayout(String classSectionId, String layoutId) {
    final section = classSection(classSectionId);
    if (section == null) return;
    upsertClass(section.copyWith(activeLayoutId: layoutId));
  }

  /// Appends an arrangement to the history. Assignments are never edited in
  /// place — that is what makes the history worth keeping.
  void saveAssignment(SeatingAssignment assignment) {
    _update(_document.copyWith(assignments: [...assignments, assignment]));
    _logger.logInformation(
      'Saved seating "${assignment.displayName()}" '
      '(${assignment.seatedCount} seated, ${assignment.source.label}).',
    );
  }

  void deleteAssignment(String assignmentId) => _update(
    _document.copyWith(
      assignments:
          assignments.where((a) => a.id != assignmentId).toList(growable: false),
    ),
  );

  /// Wipes stored data and re-seeds. Used by the "reset sample data" action.
  Future<void> resetToSeed() async {
    _saveTimer?.cancel();
    await _repository.clear();
    _document = buildSeedWorkspace();
    await _repository.save(_document);
    notifyListeners();
  }

  /// Forces a pending debounced write to land now.
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _repository.save(_document);
    }
  }

  void _update(WorkspaceDocument document) {
    _document = document;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, () {
      unawaited(
        _repository.save(_document).catchError((Object error) {
          _logger.logError('Failed to save workspace.', error: error);
        }),
      );
    });
  }

  /// Replaces an entry with a matching id, or appends it when new.
  static List<T> _upsert<T>(
    List<T> items,
    T value,
    String Function(T) idOf,
  ) {
    final id = idOf(value);
    final index = items.indexWhere((e) => idOf(e) == id);
    if (index < 0) return [...items, value];
    final copy = [...items];
    copy[index] = value;
    return copy;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
