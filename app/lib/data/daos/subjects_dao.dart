import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

part 'subjects_dao.g.dart';

const inboxName = 'Inbox';

@DriftAccessor(tables: [Subjects, ExamSubjects])
class SubjectsDao extends DatabaseAccessor<AppDatabase>
    with _$SubjectsDaoMixin {
  SubjectsDao(super.db);

  Future<void> insertSubject(SubjectsCompanion subject) =>
      into(subjects).insert(subject);

  Future<SubjectRow?> byId(String id) =>
      (select(subjects)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<void> updateSubject(String id, SubjectsCompanion changes) =>
      (update(subjects)..where((s) => s.id.equals(id))).write(changes);

  /// Fails on a foreign key if the subject still has nodes.
  Future<void> deleteSubject(String id) => transaction(() async {
        await (delete(examSubjects)..where((l) => l.subjectId.equals(id))).go();
        await (delete(subjects)..where((s) => s.id.equals(id))).go();
      });

  Future<List<SubjectRow>> all() => (select(subjects)
        ..orderBy([
          (s) => OrderingTerm.asc(s.sortOrder),
          (s) => OrderingTerm.asc(s.createdAt),
        ]))
      .get();

  Future<SubjectRow?> inbox() =>
      (select(subjects)..where((s) => s.isInbox.equals(true)))
          .getSingleOrNull();

  /// Returns the Inbox, creating it first if it is missing. Exactly one
  /// subject is the Inbox; a unique partial index guards the "at most".
  Future<SubjectRow> ensureInbox({
    required String Function() newId,
    required DateTime now,
  }) =>
      transaction(() async {
        final existing = await inbox();
        if (existing != null) return existing;
        final id = newId();
        await into(subjects).insert(SubjectsCompanion.insert(
          id: id,
          name: inboxName,
          sortOrder: 0,
          isInbox: const Value(true),
          createdAt: now,
        ));
        return (await byId(id))!;
      });

  /// The next `sort_order`, after every existing subject.
  Future<int> nextSortOrder() async {
    final max = subjects.sortOrder.max();
    final row = await (selectOnly(subjects)..addColumns([max])).getSingle();
    final m = row.read(max);
    return m == null ? 0 : m + 1;
  }

  /// Links [subjectId] to [examId]; linking twice is a no-op.
  Future<void> link(String examId, String subjectId) => into(examSubjects)
      .insert(
          ExamSubjectsCompanion.insert(examId: examId, subjectId: subjectId),
          mode: InsertMode.insertOrIgnore);

  Future<void> unlink(String examId, String subjectId) => (delete(examSubjects)
        ..where((l) => l.examId.equals(examId) & l.subjectId.equals(subjectId)))
      .go();

  Future<List<SubjectRow>> forExam(String examId) {
    final q = select(subjects).join([
      innerJoin(examSubjects, examSubjects.subjectId.equalsExp(subjects.id)),
    ])
      ..where(examSubjects.examId.equals(examId))
      ..orderBy([OrderingTerm.asc(subjects.sortOrder)]);
    return q.map((r) => r.readTable(subjects)).get();
  }

  /// Subjects named [name], ignoring case (as `firstFreeName` does), the
  /// Inbox included; callers that must never match the Inbox filter on
  /// `isInbox`.
  Future<List<SubjectRow>> findByName(String name) => (select(subjects)
        ..where((s) => s.name.lower().equals(name.trim().toLowerCase())))
      .get();
}
