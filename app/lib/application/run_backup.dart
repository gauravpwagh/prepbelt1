import 'package:logging/logging.dart';

import '../data/backup/backup_service.dart';
import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import 'source_folders.dart';

final _log = Logger('backup');

/// Routine and manual backups, and choosing the backup folder.
class RunBackup {
  RunBackup(this._db, this._service, this._folders);

  final AppDatabase _db;
  final BackupService _service;
  final SourceFolders _folders;

  /// After the first frame: back up when the last one is over 20 hours old.
  Future<BackupResult?> ifDue() async {
    if (!await _service.isDue()) return null;
    try {
      return await _service.runRoutine();
    } catch (e, st) {
      _log.severe('Routine backup failed', e, st);
      return null;
    }
  }

  /// "Back up now".
  Future<BackupResult> now() => _service.runRoutine();

  /// Picks the backup folder and backs up into it. Returns false when the
  /// user cancelled.
  Future<bool> chooseFolder() async {
    final id = await _folders.add(FolderPurpose.backup);
    if (id == null) return false;
    await _db.settingsDao.setBackupFolderId(id);
    await _service.runRoutine();
    return true;
  }
}
