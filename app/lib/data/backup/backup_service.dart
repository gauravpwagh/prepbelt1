// Whole-app backups (design §8, plan item 59): a consistent SQLite copy made
// with VACUUM INTO while the app keeps running.
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../platform/folder_access.dart';
import '../db/app_database.dart';

final _log = Logger('backup');

/// The backup file format recorded in `backup_meta`.
const backupFormatVersion = 1;

/// `prepbelt-YYYYMMDD-HHMM-s{schema}.db`: the rotating backups. Pre-migration
/// and safety copies have other prefixes and are never rotated.
final rotatingBackupName = RegExp(r'^prepbelt-\d{8}-\d{4}-s\d+\.db$');

/// Any PrepBelt backup file (what Restore lists).
final anyBackupName = RegExp(r'^prepbelt-.*\.db$');

String backupStamp(DateTime local) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}${two(local.month)}${two(local.day)}-${two(local.hour)}${two(local.minute)}';
}

/// Where the last backup went.
enum BackupDestination { folder, private }

class BackupResult {
  const BackupResult(this.name, this.destination);
  final String name;
  final BackupDestination destination;
}

class BackupService {
  BackupService(
    this._db,
    this._folders, {
    required Future<Directory> Function() cacheDir,
    required Future<Directory> Function() privateDir,
    required this.appVersion,
    required DateTime Function() now,
    required DateTime Function(DateTime utc) toLocal,
  })  : _cacheDir = cacheDir,
        _privateDir = privateDir,
        _now = now,
        _toLocal = toLocal;

  final AppDatabase _db;
  final FolderAccess _folders;
  final Future<Directory> Function() _cacheDir;
  final Future<Directory> Function() _privateDir;
  final String appVersion;
  final DateTime Function() _now;
  final DateTime Function(DateTime utc) _toLocal;

  static const keepInFolder = 7;
  static const keepPrivate = 3;
  static const dueAfter = Duration(hours: 20);

  Future<bool> isDue() async {
    final last = await _db.settingsDao.lastBackupAtUtc();
    return last == null || _now().difference(last) > dueAfter;
  }

  /// The backup folder's tree URI, or null when none is chosen or its grant
  /// was lost.
  Future<String?> backupTree() async {
    final id = await _db.settingsDao.backupFolderId();
    if (id == null) return null;
    return (await _db.sourcesDao.folderById(id))?.treeUri;
  }

  Future<Directory> _privateBackups() async {
    final d = Directory(p.join((await _privateDir()).path, 'backups'));
    await d.create(recursive: true);
    return d;
  }

  /// Routine backup: copy, rotate, record the time.
  Future<BackupResult> runRoutine() async {
    final r = await writeTo('prepbelt');
    await _rotate(r.destination);
    await _db.settingsDao.setLastBackupAtUtc(_now());
    _log.info('Backup ${r.name} → ${r.destination.name}');
    return r;
  }

  /// A copy taken before a restore replaces the data; never rotated.
  Future<BackupResult> writeSafety() => writeTo('prepbelt-safety');

  /// Writes `{prefix}-{stamp}-s{schema}.db` to the backup folder, or to
  /// app-private storage when no folder is usable.
  Future<BackupResult> writeTo(String prefix) async {
    await _updateMeta();
    final name = '$prefix-${backupStamp(_toLocal(_now()))}-s${AppDatabase.currentSchema}.db';
    final tmp = File(p.join((await _cacheDir()).path, name));
    if (await tmp.exists()) await tmp.delete();
    await _db.customStatement("VACUUM INTO '${tmp.path.replaceAll("'", "''")}'");
    try {
      final tree = await backupTree();
      if (tree != null) {
        try {
          await _folders.writeFile(tree, name, tmp);
          return BackupResult(name, BackupDestination.folder);
        } on FolderException catch (e) {
          _log.warning('Backup folder not writable; using app storage', e);
        }
      }
      await tmp.copy(p.join((await _privateBackups()).path, name));
      return BackupResult(name, BackupDestination.private);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<void> _updateMeta() => _db.transaction(() async {
        await _db.delete(_db.backupMeta).go();
        await _db.into(_db.backupMeta).insert(BackupMetaCompanion.insert(
              formatVersion: backupFormatVersion,
              schemaVersion: AppDatabase.currentSchema,
              appVersion: appVersion,
              createdAtUtc: _now(),
            ));
      });

  Future<void> _rotate(BackupDestination where) async {
    if (where == BackupDestination.folder) {
      final tree = (await backupTree())!;
      final files = [
        for (final f in await _folders.list(tree))
          if (rotatingBackupName.hasMatch(f.name)) f,
      ]..sort((a, b) => b.name.compareTo(a.name));
      for (final old in files.skip(keepInFolder)) {
        await _folders.delete(old.uri);
      }
    } else {
      final files = [
        await for (final f in (await _privateBackups()).list())
          if (f is File && rotatingBackupName.hasMatch(p.basename(f.path))) f,
      ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final old in files.skip(keepPrivate)) {
        await old.delete();
      }
    }
  }
}
