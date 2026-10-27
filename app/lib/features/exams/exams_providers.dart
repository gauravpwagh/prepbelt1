import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db_watch.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';

class ExamEntry {
  const ExamEntry(this.exam, this.subjects);
  final ExamRow exam;
  final List<SubjectRow> subjects;
}

class ExamsView {
  const ExamsView(this.exams, this.allSubjects);
  final List<ExamEntry> exams;

  /// Every subject except the Inbox, for linking.
  final List<SubjectRow> allSubjects;
}

final examsViewProvider = StreamProvider.autoDispose<ExamsView>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return watchTables(db, {db.exams, db.examSubjects, db.subjects}, () async {
    final exams = await db.examsDao.all();
    exams.sort((a, b) => (a.archivedAt == null ? 0 : 1).compareTo(b.archivedAt == null ? 0 : 1));
    return ExamsView(
      [for (final e in exams) ExamEntry(e, await db.subjectsDao.forExam(e.id))],
      [for (final s in await db.subjectsDao.all()) if (!s.isInbox) s],
    );
  });
});
