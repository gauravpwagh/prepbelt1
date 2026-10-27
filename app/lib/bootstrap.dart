import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'router.dart';

final _log = Logger('bootstrap');

/// Everything that runs before the first frame (plan item 47, design §8).
/// Returns the root container with the opened database.
Future<ProviderContainer> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final db = AppDatabase.open();
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    tzIdProvider.overrideWithValue(tzId),
    ...appOverrides,
  ]);

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
