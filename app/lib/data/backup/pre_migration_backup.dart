// Before Drift opens (and migrates) the database (design §8, plan item 60).
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../platform/folder_access.dart';
import '../db/app_database.dart';
import 'backup_service.dart';

final _log = Logger('migration');

/// A `prepbelt-premigration-…` copy waiting to be saved out.
class PreMigrationCopy {
  const PreMigrationCopy(this.file, this.fromSchema, this.backupTreeUri);
  final File file;
  final int fromSchema;

  /// The backup folder recorded in the old database, if any.
  final String? backupTreeUri;
}

abstract final class PreMigrationBackup {
  /// Before Drift opens [dbPath]: when it needs a migration, copies it and
  /// saves the copy into the backup folder recorded in it, or else into the
  /// app-private `backups` folder. Never throws; a failure is logged.
  static Future<void> saveIfNeeded(
    String dbPath, {
    required String cacheDir,
    required String privateDir,
    required FolderAccess folders,
    required DateTime localNow,
  }) async {
    try {
      final copy = runIfNeeded(File(dbPath), cacheDir: Directory(cacheDir), localNow: localNow);
      if (copy == null) return;
      final name = p.basename(copy.file.path);
      try {
        if (copy.backupTreeUri != null) {
          await folders.writeFile(copy.backupTreeUri!, name, copy.file.path);
        } else {
          final dir = Directory(p.join(privateDir, 'backups'));
          await dir.create(recursive: true);
          await copy.file.copy(p.join(dir.path, name));
        }
      } finally {
        await copy.file.delete();
      }
    } catch (e, st) {
      _log.severe('Pre-migration backup failed', e, st);
    }
  }

  /// Normally a single `user_version` read. When the file's schema is older
  /// than [currentSchema], copies it with VACUUM INTO into [cacheDir].
  static PreMigrationCopy? runIfNeeded(
    File db, {
    required Directory cacheDir,
    required DateTime localNow,
    int currentSchema = AppDatabase.currentSchema,
  }) {
    if (!db.existsSync()) return null;
    Database? raw;
    try {
      raw = sqlite3.open(db.path, mode: OpenMode.readOnly);
      final version = raw.select('PRAGMA user_version').single.values.first as int;
      if (version == 0 || version >= currentSchema) return null;

      final name = 'prepbelt-premigration-${backupStamp(localNow)}-s$version.db';
      final copy = File(p.join(cacheDir.path, name));
      if (copy.existsSync()) copy.deleteSync();
      raw.execute("VACUUM INTO '${copy.path.replaceAll("'", "''")}'");
      String? tree;
      try {
        final rows = raw.select(
            'SELECT f.tree_uri FROM settings s JOIN source_folders f ON f.id = s.value'
            " WHERE s.key = 'backup_folder_id'");
        tree = rows.isEmpty ? null : rows.single.values.first as String?;
      } on SqliteException {
        tree = null;
      }
      _log.info('Pre-migration copy of schema $version: $name');
      return PreMigrationCopy(copy, version, tree);
    } on SqliteException catch (e) {
      _log.severe('Pre-migration check failed', e);
      return null;
    } finally {
      raw?.close();
    }
  }
}
