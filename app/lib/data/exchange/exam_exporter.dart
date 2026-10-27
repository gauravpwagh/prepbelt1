// Exam export (design §8a "Export rules", plan item 62).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:prep_core/prep_core.dart';

import '../daos/events_dao.dart';
import '../db/app_database.dart';

/// `<exam name>.prepbelt.json`, with characters Android file names reject
/// replaced.
String examFileName(String examName) =>
    '${examName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim()}.prepbelt.json';

class ExamExporter {
  ExamExporter(this._db, {required this.appVersion, required DateTime Function() now})
      : _now = now;

  final AppDatabase _db;
  final String appVersion;
  final DateTime Function() _now;

  /// The exam, every non-Inbox subject linked to it, their live nodes and
  /// sources, and in progress mode their events without `session_id`.
  /// `folder_id` and `relative_path` are phone-specific and never written.
  Future<ExamPackage> build(String examId, PackageMode mode,
      {required bool includeNotes}) async {
    final exam = (await _db.examsDao.byId(examId))!;
    final subjects = [
      for (final s in await _db.subjectsDao.forExam(examId))
        if (!s.isInbox) s,
    ];
    final subjectIds = {for (final s in subjects) s.id};
    final nodes = [
      for (final n in await _db.nodesDao.allLive())
        if (subjectIds.contains(n.subjectId)) n,
    ];

    final pkgSubjects = <PkgSubject>[];
    for (final s in subjects) {
      pkgSubjects.add(PkgSubject(
        id: s.id,
        name: s.name,
        sortOrder: s.sortOrder,
        alsoUsedBy: [
          for (final e in await _db.examsDao.examsForSubject(s.id))
            if (e.id != examId) e.name,
        ],
      ));
    }

    final sources = <PkgSource>[];
    final events = <PkgEvent>[];
    for (final n in nodes) {
      final s = await _db.sourcesDao.sourceFor(n.id);
      if (s != null) {
        sources.add(PkgSource(
          nodeId: n.id,
          sourceType: s.sourceType,
          url: s.url,
          fileName: s.fileName,
          fileSize: s.fileSize,
          locationNote: s.locationNote,
          excerpt: s.excerpt,
        ));
      }
      if (mode == PackageMode.progress) {
        for (final e in await _db.eventsDao.eventsFor(n.id)) {
          events.add(toPkgEvent(e));
        }
      }
    }

    final pkg = ExamPackage(
      appVersion: appVersion,
      exportedAtUtcMs: _now().millisecondsSinceEpoch,
      mode: mode,
      exam: PkgExam(id: exam.id, name: exam.name, examDate: exam.examDate),
      subjects: pkgSubjects,
      nodes: [
        for (final n in nodes)
          PkgNode(
            id: n.id,
            subjectId: n.subjectId,
            parentId: n.parentId,
            kind: n.kind,
            taskKind: n.taskKind,
            title: n.title,
            positionText: n.positionText,
            baseMinutes: n.baseMinutes,
            sortOrder: n.sortOrder,
            createdAtUtcMs: n.createdAt.millisecondsSinceEpoch,
            splitAsIGo: n.splitAsIGo,
          ),
      ],
      sources: sources,
      events: events,
    );
    return applyPrivacy(pkg, includeNotes: includeNotes);
  }

  /// Writes the package as pretty JSON into [dir] and returns its path.
  Future<String> export(String examId, PackageMode mode,
      {required bool includeNotes, required String dir}) async {
    final pkg = await build(examId, mode, includeNotes: includeNotes);
    final file = File(p.join(dir, examFileName(pkg.exam.name)));
    await file.writeAsString(pkg.encode());
    return file.path;
  }
}

/// One `review_events` row without `session_id`.
PkgEvent toPkgEvent(StudyEvent e) {
  final row = toEventRow(e);
  return PkgEvent(
    id: e.id,
    nodeId: e.nodeId,
    eventType: e.typeKey,
    atUtcMs: e.atUtc.millisecondsSinceEpoch,
    localDate: e.localDate,
    tzId: e.tzId,
    grade: row.grade.value,
    minutes: row.minutes.value,
    beltBefore: row.beltBefore.value,
    beltAfter: row.beltAfter.value,
    intervalDays: row.intervalDays.value,
    ladderDueAfter: row.ladderDueAfter.value,
    explanation: row.explanation.value,
    undoesEventId: row.undoesEventId.value,
    batchId: row.batchId.value,
  );
}
