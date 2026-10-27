import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import 'delete_item.dart';

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

  /// Creates a subject, sorted after the existing ones and linked to
  /// [examIds]; returns its ID.
  Future<String> createSubject(String name, {Set<String> examIds = const {}}) =>
      _db.transaction(() async {
        final id = _newId();
        await _db.subjectsDao.insertSubject(SubjectsCompanion.insert(
          id: id,
          name: _name(name),
          sortOrder: await _db.subjectsDao.nextSortOrder(),
          createdAt: _now(),
        ));
        for (final e in examIds) {
          await _db.subjectsDao.link(e, id);
        }
        return id;
      });

  /// Renames a subject. The Inbox keeps its name.
  Future<void> renameSubject(String id, String name) => _db.transaction(() async {
        final s = await _subject(id);
        await _db.subjectsDao.updateSubject(s.id, SubjectsCompanion(name: Value(_name(name))));
      });

  /// Deletes a subject (design §10a). With [keepItems] its items move to the
  /// top of the Inbox with their topics, tasks and history; otherwise they
  /// are soft-deleted. Either way every row of the subject, deleted ones
  /// included, is filed under the Inbox so that its history stays, and the
  /// subject's exam links go.
  Future<void> deleteSubject(String id, {required bool keepItems}) => _db.transaction(() async {
        final s = await _subject(id);
        final inbox = await _db.subjectsDao.ensureInbox(newId: _newId, now: _now());
        if (!keepItems) {
          for (final r in await _db.nodesDao.roots(s.id)) {
            await _db.nodesDao.softDelete(r.id, _now());
          }
        }
        for (final r in await _db.nodesDao.allRoots(s.id)) {
          await refile(_db, r, subjectId: inbox.id, parentId: null, kind: r.kind);
        }
        await _db.subjectsDao.deleteSubject(s.id);
        if (await _db.settingsDao.lastUsedSubjectId() == s.id) {
          await _db.settingsDao.setLastUsedSubjectId(null);
          await _db.settingsDao.setLastUsedTopicId(null);
        }
      });

  Future<SubjectRow> _subject(String id) async {
    final s = await _db.subjectsDao.byId(id);
    if (s == null) throw StateError('No subject $id');
    if (s.isInbox) throw StateError('The Inbox cannot be renamed or deleted');
    return s;
  }

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
