import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';

/// Creates or edits an exam and its subject links, and creates subjects.
class SaveExam {
  SaveExam(this._db, {required String Function() newId, required DateTime Function() now})
      : _newId = newId,
        _now = now;

  final AppDatabase _db;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Creates an exam linked to [subjectIds]; returns its ID.
  Future<String> create(String name, LocalDate date, Set<String> subjectIds) =>
      _db.transaction(() async {
        final id = _newId();
        await _db.examsDao.insertExam(ExamsCompanion.insert(
            id: id, name: _name(name), examDate: date, createdAt: _now()));
        await _link(id, subjectIds);
        return id;
      });

  /// Renames, re-dates and re-links an exam. Links to subjects not in
  /// [subjectIds] are removed; subjects themselves are never deleted.
  Future<void> update(String id, String name, LocalDate date, Set<String> subjectIds) =>
      _db.transaction(() async {
        await _db.examsDao.updateExam(
            id, ExamsCompanion(name: Value(_name(name)), examDate: Value(date)));
        for (final s in await _db.subjectsDao.forExam(id)) {
          if (!subjectIds.contains(s.id)) await _db.subjectsDao.unlink(id, s.id);
        }
        await _link(id, subjectIds);
      });

  /// Archive (keep in app): the exam stops capping and planning; its history
  /// stays. [archived] false brings it back.
  Future<void> setArchived(String id, {required bool archived}) =>
      _db.examsDao.updateExam(
          id, ExamsCompanion(archivedAt: Value(archived ? _now() : null)));

  /// Creates a subject, sorted after the existing ones; returns its ID.
  Future<String> createSubject(String name) => _db.transaction(() async {
        final id = _newId();
        await _db.subjectsDao.insertSubject(SubjectsCompanion.insert(
          id: id,
          name: _name(name),
          sortOrder: await _db.subjectsDao.nextSortOrder(),
          createdAt: _now(),
        ));
        return id;
      });

  Future<void> _link(String examId, Set<String> subjectIds) async {
    for (final s in subjectIds) {
      final subject = await _db.subjectsDao.byId(s);
      if (subject == null) throw StateError('No subject $s');
      // The Inbox is never linked to an exam (design §8a).
      if (subject.isInbox) continue;
      await _db.subjectsDao.link(examId, s);
    }
  }
}

String _name(String name) {
  final n = name.trim();
  if (n.isEmpty) throw ArgumentError('A name is needed');
  return n;
}
