import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/data/backup/backup_service.dart';
import 'package:prepbelt/data/backup/pre_migration_backup.dart';
import 'package:prepbelt/data/backup/restore_service.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/db/converters.dart';
import 'package:prepbelt/data/db/db_file.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fakes.dart';
import 'helpers.dart';

void main() {
  late Directory tmp;
  late Directory cache;
  late Directory private;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tmp = await Directory.systemTemp.createTemp('prepbelt_backup');
    cache = await Directory(p.join(tmp.path, 'cache')).create();
    private = await Directory(p.join(tmp.path, 'support')).create();
  });
  tearDown(() => tmp.delete(recursive: true));

  BackupService service(AppDatabase db, FakeFolderAccess folders, {DateTime? at}) => BackupService(
        db,
        folders,
        cacheDir: () async => cache.path,
        privateDir: () async => private.path,
        appVersion: '0.1.0',
        now: () => at ?? t0,
        toLocal: (u) => u.add(ist),
      );

  AppDatabase fileDb(String name) => AppDatabase(NativeDatabase(File(p.join(tmp.path, name))));

  Future<void> seed(AppDatabase db, {required String subject}) async {
    await db.subjectsDao.insertSubject(
        SubjectsCompanion.insert(id: subject, name: subject, sortOrder: 0, createdAt: t0));
    await db.sourcesDao.insertFolder(SourceFoldersCompanion.insert(
        id: 'f1',
        treeUri: const Value('tree:old-phone'),
        displayName: 'Books',
        purpose: FolderPurpose.sources,
        grantedAt: t0));
    await db.nodesDao.insertNode(StudyNodesCompanion.insert(
        id: 'n-$subject',
        subjectId: subject,
        kind: NodeKind.task,
        taskKind: const Value(TaskKind.reading),
        baseMinutes: const Value(30),
        title: 'T',
        sortOrder: 0,
        createdAt: t0));
    await db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
        nodeId: 'n-$subject',
        sourceType: SourceType.pdf,
        linkStatus: LinkStatus.ok,
        folderId: const Value('f1'),
        relativePath: const Value('a.pdf'),
        fileName: const Value('a.pdf')));
    await db.settingsDao.setBackupFolderId('f1');
  }

  group('backup', () {
    test('no folder: app-private storage, newest 3 kept, meta and time recorded', () async {
      final db = memoryDb();
      final backups = Directory(p.join(private.path, 'backups'))..createSync();
      for (final old in ['20250101-0000', '20250102-0000', '20250103-0000']) {
        File(p.join(backups.path, 'prepbelt-$old-s1.db')).writeAsStringSync('x');
      }
      File(p.join(backups.path, 'prepbelt-safety-20240101-0000-s1.db')).writeAsStringSync('x');

      final s = service(db, FakeFolderAccess());
      expect(await s.isDue(), isTrue);
      final r = await s.runRoutine();
      expect(r.name, 'prepbelt-20260301-1130-s2.db');
      expect(r.destination, BackupDestination.private);
      final names = backups.listSync().map((f) => p.basename(f.path)).toList()..sort();
      expect(names, [
        'prepbelt-20250102-0000-s1.db',
        'prepbelt-20250103-0000-s1.db',
        'prepbelt-20260301-1130-s2.db',
        'prepbelt-safety-20240101-0000-s1.db',
      ]);
      final meta = (await db.select(db.backupMeta).get()).single;
      expect([meta.formatVersion, meta.schemaVersion, meta.appVersion], [1, 2, '0.1.0']);
      expect(await db.settingsDao.lastBackupAtUtc(), t0);
      expect(await s.isDue(), isFalse);
      expect(cache.listSync(), isEmpty);
      await db.close();
    });

    test('backup folder: newest 7 kept; an unwritable folder falls back', () async {
      final db = memoryDb();
      final folders = FakeFolderAccess();
      folders.addTree('Drive', {
        for (var d = 1; d <= 8; d++) 'prepbelt-2025010$d-0000-s1.db': 1,
        'prepbelt-premigration-20240101-0000-s1.db': 1,
      });
      await db.sourcesDao.insertFolder(SourceFoldersCompanion.insert(
          id: 'b', treeUri: const Value('tree:Drive'), displayName: 'Drive',
          purpose: FolderPurpose.backup, grantedAt: t0));
      await db.settingsDao.setBackupFolderId('b');

      final r = await service(db, folders).runRoutine();
      expect(r.destination, BackupDestination.folder);
      final kept = folders.trees['tree:Drive']!.keys.toList()..sort();
      expect(kept.length, 8); // 7 rotating + the pre-migration copy
      expect(kept, contains('prepbelt-premigration-20240101-0000-s1.db'));
      expect(kept, isNot(contains('prepbelt-20250101-0000-s1.db')));
      expect(kept, isNot(contains('prepbelt-20250102-0000-s1.db')));

      folders.trees.remove('tree:Drive');
      await db.sourcesDao.setTreeUri('b', 'tree:Gone');
      final fallback = await service(db, folders, at: t0.add(const Duration(minutes: 1))).writeSafety();
      expect(fallback.destination, BackupDestination.private);
      expect(fallback.name, startsWith('prepbelt-safety-'));
      await db.close();
    });
  });

  group('restore', () {
    test('round trip: data comes back, side files go, folders need picking again', () async {
      final a = fileDb('a.sqlite');
      await seed(a, subject: 'polity');
      final r = await service(a, FakeFolderAccess()).runRoutine();
      await a.close();
      final backup = File(p.join(private.path, 'backups', r.name));

      final target = File(p.join(tmp.path, 'live.sqlite'));
      var live = AppDatabase(NativeDatabase(target));
      await seed(live, subject: 'history');
      await live.close();
      for (final f in sideFiles(target)) {
        f.writeAsStringSync('stale');
      }

      final restore = RestoreService(dbPath: () async => target.path);
      var safety = 0;
      final result = await restore.restore(
        backup.path,
        writeSafety: () async => safety++,
        closeDatabase: () => live.close(),
        openDatabase: () async => live = AppDatabase(NativeDatabase(target)),
      );
      expect(result, isA<RestoreOk>());
      expect(safety, 1);
      expect(
          sideFiles(target)
              .where((f) => f.existsSync() && String.fromCharCodes(f.readAsBytesSync()) == 'stale'),
          isEmpty);
      expect(await live.subjectsDao.byId('polity'), isNotNull);
      expect(await live.subjectsDao.byId('history'), isNull);
      expect((await live.sourcesDao.folderById('f1'))!.treeUri, isNull);
      expect(await live.settingsDao.backupFolderId(), isNull);
      expect((await live.sourcesDao.sourceFor('n-polity'))!.linkStatus, LinkStatus.needsRelink);
      await live.close();
    });

    test('refuses newer schemas, unknown files and damaged files', () async {
      final restore = RestoreService(dbPath: () async => p.join(tmp.path, 'unused'));

      final newer = File(p.join(tmp.path, 'newer.db'));
      sqlite3.open(newer.path)
        ..execute('CREATE TABLE backup_meta (format_version INT, schema_version INT,'
            ' app_version TEXT, created_at_utc INT)')
        ..execute("INSERT INTO backup_meta VALUES (1, 99, 'x', 0)")
        ..close();
      expect(restore.check(newer.path), isA<RestoreNewerSchema>());

      final unknown = File(p.join(tmp.path, 'unknown.db'));
      sqlite3.open(unknown.path)
        ..execute('CREATE TABLE t (x)')
        ..close();
      expect(restore.check(unknown.path), isA<RestoreUnknownFormat>());

      final garbage = File(p.join(tmp.path, 'garbage.db'))..writeAsStringSync('not sqlite ' * 100);
      expect(restore.check(garbage.path), isA<RestoreCorrupt>());

      var closed = false;
      final r = await restore.restore(newer.path,
          writeSafety: () async {},
          closeDatabase: () async => closed = true,
          openDatabase: () async => throw StateError('must not open'));
      expect(r, isA<RestoreNewerSchema>());
      expect(closed, isFalse);
    });
  });

  group('pre-migration backup', () {
    test('copies an older schema before migrating, and only then', () async {
      final db = File(p.join(tmp.path, 'old.sqlite'));
      sqlite3.open(db.path)
        ..execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)')
        ..execute('CREATE TABLE source_folders (id TEXT PRIMARY KEY, tree_uri TEXT)')
        ..execute("INSERT INTO settings VALUES ('backup_folder_id', 'b')")
        ..execute("INSERT INTO source_folders VALUES ('b', 'tree:Drive')")
        ..execute('PRAGMA user_version = 1')
        ..close();

      final local = DateTime(2026, 3, 1, 11, 30);
      expect(PreMigrationBackup.runIfNeeded(db, cacheDir: cache, localNow: local, currentSchema: 1),
          isNull);
      final copy = PreMigrationBackup.runIfNeeded(db,
          cacheDir: cache, localNow: local, currentSchema: 2)!;
      expect(p.basename(copy.file.path), 'prepbelt-premigration-20260301-1130-s1.db');
      expect(copy.file.existsSync(), isTrue);
      expect(copy.fromSchema, 1);
      expect(copy.backupTreeUri, 'tree:Drive');

      expect(PreMigrationBackup.runIfNeeded(File(p.join(tmp.path, 'none')),
          cacheDir: cache, localNow: local, currentSchema: 2), isNull);
    });
  });
}
