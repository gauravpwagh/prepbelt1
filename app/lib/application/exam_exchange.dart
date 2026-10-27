// Exam files (design §8a, plan items 84–86).
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:prep_core/prep_core.dart';

import '../data/backup/backup_service.dart';
import '../data/exchange/exam_exporter.dart';
import '../data/exchange/exam_importer.dart';
import '../platform/file_sharer.dart';
import '../platform/folder_access.dart';
import '../platform/local_files.dart';
import 'build_today_plan.dart';

final _log = Logger('exchange');

/// Shown before a progress export goes out through the share sheet.
const historyWarning = 'Includes your notes and history';

/// Export (plan item 84): share the file, or save it into the backup folder.
class ExportExam {
  ExportExam(this._exporter, this._folders, this._backups, this._sharer,
      {required LocalFiles files, required Future<String> Function() cacheDir})
      : _files = files,
        _cacheDir = cacheDir;

  final ExamExporter _exporter;
  final FolderAccess _folders;
  final BackupService _backups;
  final FileSharer _sharer;
  final LocalFiles _files;
  final Future<String> Function() _cacheDir;

  /// "Polity is also used by UPSC Prelims." for every shared subject.
  Future<List<String>> alsoUsedNotices(String examId) async {
    final pkg = await _exporter.build(examId, PackageMode.structure, includeNotes: true);
    return [
      for (final s in pkg.subjects)
        if (s.alsoUsedBy.isNotEmpty) '${s.name} is also used by ${s.alsoUsedBy.join(', ')}.',
    ];
  }

  Future<String> _file(String examId, PackageMode mode, bool includeNotes) async =>
      _exporter.export(examId, mode, includeNotes: includeNotes, dir: await _cacheDir());

  Future<void> share(String examId, PackageMode mode, {required bool includeNotes}) async {
    final f = await _file(examId, mode, includeNotes);
    await _sharer.shareFile(f);
  }

  /// Saves into the backup folder; returns the file name. Throws
  /// [FolderException] when no backup folder is usable.
  Future<String> saveToFolder(String examId, PackageMode mode, {required bool includeNotes}) async {
    final tree = await _backups.backupTree();
    if (tree == null) {
      throw const FolderException(FolderError.noPermission, 'Choose a backup folder first');
    }
    final f = await _file(examId, mode, includeNotes);
    final name = p.basename(f);
    try {
      await _folders.writeFile(tree, name, f, mime: 'application/json');
      return name;
    } finally {
      await _files.deleteIfExists(f);
    }
  }
}

/// Import (plan item 85): preview, then import, then refresh today's plan.
class ImportExam {
  ImportExam(this._importer, this._plans);

  final ExamImporter _importer;
  final BuildTodayPlan _plans;

  /// [path] is a local copy of the exam file.
  Future<ImportPreview> preview(String path) => _importer.previewFile(path);

  Future<String> call(ImportPreview p,
      {required String examName,
      required LocalDate examDate,
      Map<String, ClashChoice> choices = const {}}) async {
    final id = await _importer.import(p, examName: examName, examDate: examDate, choices: choices);
    _log.info('Imported exam $id (${p.package.mode.key}, ${p.itemCount} items)');
    await _plans.refresh();
    return id;
  }
}

/// Copy as new attempt (plan item 86): a structure export and import in
/// memory that never merges into the old attempt.
class CopyAsNewAttempt {
  CopyAsNewAttempt(this._exporter, this._importer, this._plans);

  final ExamExporter _exporter;
  final ExamImporter _importer;
  final BuildTodayPlan _plans;

  Future<String> call(String examId, {required String name, required LocalDate date}) async {
    final pkg = await _exporter.build(examId, PackageMode.structure, includeNotes: true);
    final id = await _importer.import(await _importer.preview(pkg),
        examName: name, examDate: date, forceSeparate: true);
    await _plans.refresh();
    return id;
  }
}
