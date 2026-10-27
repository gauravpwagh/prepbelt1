// Restore (design §8, plan item 61): replaces everything with a backup.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/sqlite3.dart';

import '../db/app_database.dart';
import '../db/db_file.dart';
import 'backup_service.dart';

final _log = Logger('restore');

sealed class RestoreResult {
  const RestoreResult();
}

final class RestoreOk extends RestoreResult {
  const RestoreOk(this.fromSchema);
  final int fromSchema;
}

final class RestoreUnknownFormat extends RestoreResult {
  const RestoreUnknownFormat();
}

/// "Update the app to restore this backup".
final class RestoreNewerSchema extends RestoreResult {
  const RestoreNewerSchema(this.schema);
  final int schema;
}

final class RestoreCorrupt extends RestoreResult {
  const RestoreCorrupt(this.detail);
  final String detail;
}

final class RestoreIoError extends RestoreResult {
  const RestoreIoError(this.detail);
  final String detail;
}

class RestoreService {
  RestoreService({required Future<File> Function() dbFile}) : _dbFile = dbFile;

  final Future<File> Function() _dbFile;

  /// Opens [candidate] read-only and checks it (step 3). Returns [RestoreOk]
  /// when it can be restored.
  RestoreResult check(File candidate) {
    Database? raw;
    try {
      raw = sqlite3.open(candidate.path, mode: OpenMode.readOnly);
      final hasMeta = raw.select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'backup_meta'");
      if (hasMeta.isEmpty) return const RestoreUnknownFormat();
      final meta = raw.select('SELECT format_version, schema_version FROM backup_meta');
      if (meta.length != 1 || meta.single['format_version'] != backupFormatVersion) {
        return const RestoreUnknownFormat();
      }
      final schema = meta.single['schema_version'] as int;
      if (schema > AppDatabase.currentSchema) return RestoreNewerSchema(schema);
      final integrity = raw.select('PRAGMA integrity_check');
      final lines = [for (final r in integrity) '${r.values.first}'];
      if (lines.length != 1 || lines.single != 'ok') return RestoreCorrupt(lines.join('; '));
      return RestoreOk(schema);
    } on SqliteException catch (e) {
      return RestoreCorrupt(e.message);
    } finally {
      raw?.close();
    }
  }

  /// Steps 4–6: [writeSafety] backs up the current data, [closeDatabase]
  /// closes it, the files are swapped, and [openDatabase] opens the restored
  /// file (migrations run on open). Folder grants from the old phone are
  /// invalid, so every folder is marked "pick again" and linked PDFs become
  /// `needs_relink`.
  Future<RestoreResult> restore(
    File candidate, {
    required Future<void> Function() writeSafety,
    required Future<void> Function() closeDatabase,
    required Future<AppDatabase> Function() openDatabase,
  }) async {
    final checked = check(candidate);
    if (checked is! RestoreOk) return checked;
    try {
      await writeSafety();
    } catch (e) {
      return RestoreIoError('Could not write the safety backup: $e');
    }
    try {
      final target = await _dbFile();
      await closeDatabase();
      for (final f in sideFiles(target)) {
        if (await f.exists()) await f.delete();
      }
      await candidate.copy(target.path);
    } on FileSystemException catch (e) {
      return RestoreIoError(e.message);
    }
    final db = await openDatabase();
    await db.transaction(() async {
      await db.customUpdate('UPDATE source_folders SET tree_uri = NULL',
          updates: {db.sourceFolders}, updateKind: UpdateKind.update);
      await db.settingsDao.setBackupFolderId(null);
      await db.customUpdate(
          "UPDATE node_sources SET link_status = 'needs_relink'"
          " WHERE source_type = 'pdf' AND link_status = 'ok'",
          updates: {db.nodeSources},
          updateKind: UpdateKind.update);
    });
    _log.info('Restored a schema ${checked.fromSchema} backup');
    return checked;
  }
}
