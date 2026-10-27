import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db_watch.dart';
import '../../core/providers.dart';

class SettingsView {
  const SettingsView({
    required this.dailyMinutes,
    required this.dayStartHour,
    required this.reminder,
  });

  final int dailyMinutes;
  final int dayStartHour;
  final ({int hour, int minute}) reminder;
}

final settingsViewProvider = StreamProvider.autoDispose<SettingsView>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final s = db.settingsDao;
  return watchTables(db, {db.settings}, () async => SettingsView(
        dailyMinutes: await s.dailyMinutes(),
        dayStartHour: await s.dayStartHour(),
        reminder: await s.reminderTime(),
      ));
});

/// Changing the daily minutes or the day-start hour refreshes today's plan
/// (design §4).
class SettingsActions {
  SettingsActions(this._ref);
  final Ref _ref;

  Future<void> setDailyMinutes(int minutes) async {
    await _ref.read(appDatabaseProvider).settingsDao.setDailyMinutes(minutes);
    await _ref.read(buildTodayPlanProvider).refresh();
  }

  Future<void> setDayStartHour(int hour) async {
    await _ref.read(appDatabaseProvider).settingsDao.setDayStartHour(hour);
    _ref.read(dayStartHourProvider.notifier).set(hour);
    await _ref.read(buildTodayPlanProvider).refresh();
  }

  Future<void> setReminderTime(int hour, int minute) async {
    await _ref.read(appDatabaseProvider).settingsDao.setReminderTime(hour, minute);
    await _ref.read(reminderChangedProvider)();
  }
}

final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);

/// Reschedules the daily reminder after a change; notifications fill it in.
final reminderChangedProvider = Provider<Future<void> Function()>((ref) => () async {});
