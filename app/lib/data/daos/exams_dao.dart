import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

part 'exams_dao.g.dart';

@DriftAccessor(tables: [Exams, ExamSubjects])
class ExamsDao extends DatabaseAccessor<AppDatabase> with _$ExamsDaoMixin {
  ExamsDao(super.db);

  Future<void> insertExam(ExamsCompanion exam) => into(exams).insert(exam);

  Future<ExamRow?> byId(String id) =>
      (select(exams)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<void> updateExam(String id, ExamsCompanion changes) =>
      (update(exams)..where((e) => e.id.equals(id))).write(changes);

  /// Removes the exam and its subject links. Subjects are left alone.
  Future<void> deleteExam(String id) => transaction(() async {
        await (delete(examSubjects)..where((l) => l.examId.equals(id))).go();
        await (delete(exams)..where((e) => e.id.equals(id))).go();
      });

  Future<List<ExamRow>> all() =>
      (select(exams)..orderBy([(e) => OrderingTerm.asc(e.examDate)])).get();

  /// Exams that are not archived, soonest first.
  Stream<List<ExamRow>> watchActive() => (select(exams)
        ..where((e) => e.archivedAt.isNull())
        ..orderBy([(e) => OrderingTerm.asc(e.examDate)]))
      .watch();

  /// Every exam linked to each subject, as `prep_core` refs.
  Future<Map<String, List<ExamRef>>> examRefsBySubject() async {
    final rows = await select(exams).join([
      innerJoin(examSubjects, examSubjects.examId.equalsExp(exams.id)),
    ]).get();
    final bySubject = <String, List<ExamRef>>{};
    for (final r in rows) {
      final e = r.readTable(exams);
      (bySubject[r.readTable(examSubjects).subjectId] ??= []).add(ExamRef(
          id: e.id, name: e.name, date: e.examDate, archived: e.archivedAt != null));
    }
    return bySubject;
  }

  /// Every exam (archived or not) linked to [subjectId].
  Future<List<ExamRow>> examsForSubject(String subjectId) {
    final q = select(exams).join([
      innerJoin(examSubjects, examSubjects.examId.equalsExp(exams.id)),
    ])
      ..where(examSubjects.subjectId.equals(subjectId))
      ..orderBy([OrderingTerm.asc(exams.examDate)]);
    return q.map((r) => r.readTable(exams)).get();
  }
}
