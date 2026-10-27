import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/backup/backup_service.dart';
import '../data/backup/restore_service.dart';
import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import '../data/integrity.dart';
import '../platform/folder_access.dart';
import '../platform/local_files.dart';

/// The backup folder the user picked to restore from, and its backups.
class BackupChoice {
  const BackupChoice(this.grant, this.files);
  final FolderGrant grant;

  /// `prepbelt-*.db`, newest name first.
  final List<FolderEntry> files;
}

/// Restore (CUJ 7, design §8).
class RestoreBackup {
  RestoreBackup({
    required FolderAccess folders,
    required RestoreService service,
    required BackupService backups,
    required LocalFiles files,
    required Future<String> Function() cacheDir,
    required Future<void> Function() closeDatabase,
    required Future<AppDatabase> Function() reopenDatabase,
    required String Function() newId,
    required DateTime Function() now,
  })  : _folders = folders,
        _service = service,
        _backups = backups,
        _files = files,
        _cacheDir = cacheDir,
        _close = closeDatabase,
        _reopen = reopenDatabase,
        _newId = newId,
        _now = now;

  final FolderAccess _folders;
  final RestoreService _service;
  final BackupService _backups;
  final LocalFiles _files;
  final Future<String> Function() _cacheDir;
  final Future<void> Function() _close;
  final Future<AppDatabase> Function() _reopen;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Step 1: the user picks the backup folder. Null when cancelled.
  Future<BackupChoice?> pickFolder() async {
    final g = await _folders.pickFolder();
    if (g == null) return null;
    final files = [
      for (final f in await _folders.list(g.treeUri))
        if (!f.isDir && anyBackupName.hasMatch(f.name)) f,
    ]..sort((a, b) => b.name.compareTo(a.name));
    return BackupChoice(g, files);
  }

  /// Steps 2–6, then the backup folder is re-granted from the folder the user
  /// just picked, and the integrity check runs.
  Future<(RestoreResult, IntegrityReport?)> restore(BackupChoice choice, FolderEntry file) async {
    final local = p.join(await _cacheDir(), 'restore-${file.name}');
    try {
      await _folders.copyToLocal(file.uri, local);
    } on FolderException catch (e) {
      return (RestoreIoError(e.message), null);
    }
    try {
      AppDatabase? restored;
      final r = await _service.restore(
        local,
        writeSafety: () => _backups.writeSafety(),
        closeDatabase: _close,
        openDatabase: () async => restored = await _reopen(),
      );
      if (r is! RestoreOk) return (r, null);
      final db = restored!;
      // The folder just picked is a fresh grant: keep it as the backup folder.
      final id = _newId();
      await db.sourcesDao.insertFolder(SourceFoldersCompanion.insert(
        id: id,
        treeUri: Value(choice.grant.treeUri),
        displayName: choice.grant.displayName,
        purpose: FolderPurpose.backup,
        grantedAt: _now(),
      ));
      await db.settingsDao.setBackupFolderId(id);
      return (r, await runIntegrityCheck(db));
    } finally {
      await _files.deleteIfExists(local);
    }
  }
}
