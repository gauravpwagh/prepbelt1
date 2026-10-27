// Archive and remove (design §8a, CUJ 12, plan item 87).
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:prep_core/prep_core.dart';

import '../data/backup/backup_service.dart';
import '../data/db/app_database.dart';
import '../data/exchange/exam_exporter.dart';
import '../data/study_writer.dart';
import '../platform/folder_access.dart';
import 'build_today_plan.dart';

final _log = Logger('archive');

class ArchiveBlocked implements Exception {
  const ArchiveBlocked(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A verified archive file, ready for the typed confirmation.
class ArchivePlan {
  const ArchivePlan({
    required this.examId,
    required this.examName,
    required this.fileName,
    required this.folderName,
    required this.removeSubjects,
    required this.keptSubjects,
  });

  final String examId;
  final String examName;
  final String fileName;
  final String folderName;

  /// Subjects linked to no other exam: deleted with all their rows.
  final Set<String> removeSubjects;

  /// Subjects another exam still uses: kept unchanged.
  final List<String> keptSubjects;
}

class ArchiveAndRemove {
  ArchiveAndRemove(this._db, this._exporter, this._folders, this._backups, this._writer,
      this._plans, {required Future<Directory> Function() cacheDir})
      : _cacheDir = cacheDir;

  final AppDatabase _db;
  final ExamExporter _exporter;
  final FolderAccess _folders;
  final BackupService _backups;
  final StudyWriter _writer;
  final BuildTodayPlan _plans;
  final Future<Directory> Function() _cacheDir;

  /// Steps 1–3: check, export with progress (notes always on) into the backup
  /// folder, then read the file back and compare counts. Nothing is deleted.
  Future<ArchivePlan> prepare(String examId) async {
    final tree = await _backups.backupTree();
    if (tree == null) throw const ArchiveBlocked('Choose a backup folder first');
    final exam = (await _db.examsDao.byId(examId))!;

    final remove = <String>{};
    final kept = <String>[];
    for (final s in await _db.subjectsDao.forExam(examId)) {
      if (s.isInbox) continue;
      final others = (await _db.examsDao.examsForSubject(s.id)).where((e) => e.id != examId);
      if (others.isEmpty) {
        remove.add(s.id);
      } else {
        kept.add(s.name);
      }
    }
    final open = await _db.sessionsDao.open();
    if (open != null) {
      final node = await _db.nodesDao.byId(open.nodeId);
      if (node != null && remove.contains(node.subjectId)) {
        throw const ArchiveBlocked('Finish or discard the running session first');
      }
    }

    final pkg = await _exporter.build(examId, PackageMode.progress, includeNotes: true);
    final cache = await _cacheDir();
    final out = File(p.join(cache.path, examFileName(exam.name)));
    await out.writeAsString(pkg.encode());
    final name = p.basename(out.path);
    try {
      await _folders.writeFile(tree, name, out, mime: 'application/json');
    } on FolderException catch (e) {
      throw ArchiveBlocked('The backup folder is not writable: ${e.message}');
    } finally {
      await out.delete();
    }

    // Read the file back from the folder and check it.
    final entry = (await _folders.list(tree)).where((f) => f.name == name).firstOrNull;
    if (entry == null) throw const ArchiveBlocked('The archive file was not found after writing');
    final back = File(p.join(cache.path, 'readback-$name'));
    try {
      await _folders.copyToLocal(entry.uri, back);
      final read = ExamPackage.decode(await back.readAsString());
      final errors = validate(read);
      if (errors.isNotEmpty) throw ArchiveBlocked('The archive file is invalid: ${errors.first}');
      if (read.nodes.length != pkg.nodes.length || read.events.length != pkg.events.length) {
        throw const ArchiveBlocked('The archive file does not match the database');
      }
    } on FormatException catch (e) {
      throw ArchiveBlocked('The archive file could not be read: ${e.message}');
    } finally {
      if (await back.exists()) await back.delete();
    }

    final folder = await _db.sourcesDao.folderById((await _db.settingsDao.backupFolderId())!);
    return ArchivePlan(
      examId: examId,
      examName: exam.name,
      fileName: name,
      folderName: folder?.displayName ?? 'the backup folder',
      removeSubjects: remove,
      keptSubjects: kept,
    );
  }

  /// Step 5, after the user typed the exam name: one transaction.
  Future<void> remove(ArchivePlan plan, {required String typedName}) async {
    if (typedName.trim() != plan.examName.trim()) {
      throw const ArchiveBlocked('Type the exam name exactly to confirm');
    }
    await _db.transaction(() async {
      await _writer.deleteSubjectsHard(plan.removeSubjects);
      await _db.examsDao.deleteExam(plan.examId);
    });
    _log.info('Archived and removed ${plan.examName} to ${plan.fileName}');
    await _plans.refresh();
  }
}
