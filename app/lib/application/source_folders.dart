import 'package:drift/drift.dart';

import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import '../platform/folder_access.dart';

/// Granting and re-granting folders (design §7).
class SourceFolders {
  SourceFolders(this._db, this._folders,
      {required String Function() newId, required DateTime Function() now})
      : _newId = newId,
        _now = now;

  final AppDatabase _db;
  final FolderAccess _folders;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Opens the system picker and records the grant. Returns the folder ID,
  /// or null when cancelled. Picking a folder that is already recorded
  /// refreshes its grant instead of adding a second row.
  Future<String?> add(FolderPurpose purpose) async {
    final g = await _folders.pickFolder();
    if (g == null) return null;
    for (final f in await _db.sourcesDao.folders(purpose)) {
      if (f.treeUri == g.treeUri) {
        await _db.sourcesDao.setTreeUri(f.id, g.treeUri, grantedAt: _now());
        return f.id;
      }
    }
    final id = _newId();
    await _db.sourcesDao.insertFolder(SourceFoldersCompanion.insert(
      id: id,
      treeUri: Value(g.treeUri),
      displayName: g.displayName,
      purpose: purpose,
      grantedAt: _now(),
    ));
    return id;
  }

  /// "Pick again" for a folder whose grant was lost (after a restore).
  Future<bool> regrant(String folderId) async {
    final g = await _folders.pickFolder();
    if (g == null) return false;
    await _db.sourcesDao.setTreeUri(folderId, g.treeUri, grantedAt: _now());
    return true;
  }

  /// Forgets a source folder; its PDFs become `needs_relink`.
  Future<void> forget(String folderId) => _db.transaction(() async {
        await _db.customUpdate(
          "UPDATE node_sources SET folder_id = NULL, relative_path = NULL,"
          " link_status = 'needs_relink' WHERE folder_id = ?1",
          variables: [Variable.withString(folderId)],
          updates: {_db.nodeSources},
          updateKind: UpdateKind.update,
        );
        if (await _db.settingsDao.backupFolderId() == folderId) {
          await _db.settingsDao.setBackupFolderId(null);
        }
        await _db.sourcesDao.deleteFolder(folderId);
      });
}
