// Plan item 103: a file-backed database is backed up, changed, and restored.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:prepbelt/data/backup/backup_service.dart';
import 'package:prepbelt/data/backup/restore_service.dart';
import 'package:prepbelt/data/db/app_database.dart';

import '../test/application/app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('backup → restore round trip on the device file system', (tester) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'it-prepbelt.sqlite'));
    if (file.existsSync()) file.deleteSync();
    var db = AppDatabase(NativeDatabase(file));
    await db.subjectsDao.ensureInbox(newId: () => 'inbox', now: t0);
    final backups = BackupService(db, FakeFolderAccess(),
        cacheDir: () async => dir.path,
        privateDir: () async => dir.path,
        appVersion: 'it',
        now: () => t0,
        toLocal: (u) => u);
    final r = await backups.runRoutine();
    await db.settingsDao.setDailyMinutes(200);

    final result = await RestoreService(dbPath: () async => file.path).restore(
      p.join(dir.path, 'backups', r.name),
      writeSafety: () async {},
      closeDatabase: () => db.close(),
      openDatabase: () async => db = AppDatabase(NativeDatabase(file)),
    );
    expect(result, isA<RestoreOk>());
    expect(await db.settingsDao.dailyMinutes(), 90);
    await db.close();
  });
}
