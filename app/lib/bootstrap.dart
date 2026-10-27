import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'core/providers.dart';
import 'data/backup/pre_migration_backup.dart';
import 'platform/clock.dart';
import 'platform/logging.dart';
import 'router.dart';

final _log = Logger('bootstrap');

/// Everything that runs before the first frame (plan item 47, design §8).
/// Returns the root container with the opened database.
Future<ProviderContainer> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  const clock = SystemClock();
  final sink = FileLogSink(
      Directory(p.join((await getApplicationSupportDirectory()).path, 'logs')),
      now: clock.nowUtc);
  initLogging(sink);
  installErrorHooks(sink);

  tzdata.initializeTimeZones();
  var tzId = 'UTC';
  try {
    tzId = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(tzId));
  } catch (e) {
    _log.warning('Time zone "$tzId" unavailable; using UTC', e);
    tzId = 'UTC';
    tz.setLocalLocation(tz.UTC);
  }

  final container = ProviderContainer(overrides: [
    logSinkProvider.overrideWithValue(sink),
    tzIdProvider.overrideWithValue(tzId),
    ...appOverrides,
  ]);
  await _preMigrationBackup(container);
  final db = container.read(appDatabaseProvider);

  final settings = db.settingsDao;
  container.read(dayStartHourProvider.notifier).set(await settings.dayStartHour());
  final onboarded = await settings.onboardingDone();
  container.read(onboardingDoneProvider.notifier).set(onboarded);

  await db.subjectsDao.ensureInbox(
      newId: container.read(idGeneratorProvider),
      now: container.read(clockProvider).nowUtc());
  if (onboarded) await container.read(buildTodayPlanProvider).get();

  try {
    await container
        .read(notificationPortProvider)
        .init((route) => container.read(routerProvider).go(route));
  } catch (e, st) {
    _log.warning('Notifications unavailable', e, st);
  }
  return container;
}

/// Design §8: before Drift opens (and migrates) an older file, copy it out.
Future<void> _preMigrationBackup(ProviderContainer c) async {
  try {
    final now = c.read(clockProvider).nowUtc();
    final copy = PreMigrationBackup.runIfNeeded(
      await c.read(databaseFileProvider)(),
      cacheDir: await c.read(cacheDirProvider)(),
      localNow: now.add(c.read(offsetFnProvider)(now)),
    );
    if (copy == null) return;
    final name = p.basename(copy.file.path);
    try {
      if (copy.backupTreeUri != null) {
        await c.read(folderAccessProvider).writeFile(copy.backupTreeUri!, name, copy.file);
      } else {
        final dir = Directory(p.join((await c.read(privateDirProvider)()).path, 'backups'));
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
