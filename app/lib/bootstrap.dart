import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'core/providers.dart';
import 'data/backup/pre_migration_backup.dart';
import 'platform/clock.dart';
import 'platform/local_files.dart';
import 'platform/logging.dart';
import 'platform/time_zone.dart';
import 'router.dart';

final _log = Logger('bootstrap');

/// Everything that runs before the first frame (plan item 47, design §8).
/// Returns the root container with the opened database.
Future<ProviderContainer> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  const clock = SystemClock();
  final sink = FileLogSink(p.join(await appPrivateDir(), 'logs'), now: clock.nowUtc);
  initLogging(sink);
  installErrorHooks(sink);

  String? deviceZone;
  try {
    deviceZone = (await FlutterTimezone.getLocalTimezone()).identifier;
  } catch (e) {
    _log.warning('Could not read the device time zone', e);
  }
  final tzId = setLocalTimeZone(deviceZone);
  if (tzId != deviceZone) _log.warning('Time zone "$deviceZone" unknown; using UTC');

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
  final now = c.read(clockProvider).nowUtc();
  await PreMigrationBackup.saveIfNeeded(
    await c.read(databasePathProvider)(),
    cacheDir: await c.read(cacheDirProvider)(),
    privateDir: await c.read(privateDirProvider)(),
    folders: c.read(folderAccessProvider),
    localNow: now.add(c.read(offsetFnProvider)(now)),
  );
}
