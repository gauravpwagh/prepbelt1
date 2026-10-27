import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

part 'settings_dao.g.dart';

/// Typed access to the settings in design §2. A missing row means the
/// default.
@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  static const dailyMinutesKey = 'daily_minutes';
  static const dayStartHourKey = 'day_start_hour';
  static const reminderTimeKey = 'reminder_time';
  static const backupFolderIdKey = 'backup_folder_id';
  static const lastBackupAtUtcKey = 'last_backup_at_utc';
  static const onboardingDoneKey = 'onboarding_done';
  static const lastUsedSubjectIdKey = 'last_used_subject_id';
  static const lastUsedTopicIdKey = 'last_used_topic_id';

  Future<String?> _get(String key) async =>
      (await (select(settings)..where((s) => s.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  Future<void> _set(String key, String? value) => into(settings)
      .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: Value(value)));

  Future<int> dailyMinutes() async =>
      int.tryParse(await _get(dailyMinutesKey) ?? '') ?? Defaults.dailyMinutes;

  Future<void> setDailyMinutes(int minutes) {
    RangeError.checkValueInInterval(minutes, Defaults.dailyMinutesMin,
        Defaults.dailyMinutesMax, 'minutes');
    return _set(dailyMinutesKey, '$minutes');
  }

  Future<int> dayStartHour() async =>
      int.tryParse(await _get(dayStartHourKey) ?? '') ?? Defaults.dayStartHour;

  Future<void> setDayStartHour(int hour) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    return _set(dayStartHourKey, '$hour');
  }

  /// `HH:MM`, 24-hour; default 07:00.
  Future<({int hour, int minute})> reminderTime() async {
    final m = RegExp(r'^(\d{2}):(\d{2})$')
        .firstMatch(await _get(reminderTimeKey) ?? '');
    return m == null
        ? (hour: 7, minute: 0)
        : (hour: int.parse(m[1]!), minute: int.parse(m[2]!));
  }

  Future<void> setReminderTime(int hour, int minute) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
    String two(int v) => v.toString().padLeft(2, '0');
    return _set(reminderTimeKey, '${two(hour)}:${two(minute)}');
  }

  Future<String?> backupFolderId() => _get(backupFolderIdKey);
  Future<void> setBackupFolderId(String? id) => _set(backupFolderIdKey, id);

  Future<DateTime?> lastBackupAtUtc() async {
    final ms = int.tryParse(await _get(lastBackupAtUtcKey) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> setLastBackupAtUtc(DateTime at) =>
      _set(lastBackupAtUtcKey, '${at.toUtc().millisecondsSinceEpoch}');

  Future<bool> onboardingDone() async =>
      await _get(onboardingDoneKey) == 'true';
  Future<void> setOnboardingDone(bool done) =>
      _set(onboardingDoneKey, done ? 'true' : 'false');

  Future<String?> lastUsedSubjectId() => _get(lastUsedSubjectIdKey);
  Future<void> setLastUsedSubjectId(String? id) =>
      _set(lastUsedSubjectIdKey, id);

  Future<String?> lastUsedTopicId() => _get(lastUsedTopicIdKey);
  Future<void> setLastUsedTopicId(String? id) => _set(lastUsedTopicIdKey, id);
}
