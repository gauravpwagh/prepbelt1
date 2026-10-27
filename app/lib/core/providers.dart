// Root providers: the single place where the app is wired (plan item 50).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../application/add_item.dart';
import '../application/archive_and_remove.dart';
import '../application/build_today_plan.dart';
import '../application/capture_shared.dart';
import '../application/catch_up.dart';
import '../application/complete_onboarding.dart';
import '../application/delete_item.dart';
import '../application/move_item.dart';
import '../application/discard_session.dart';
import '../application/exam_exchange.dart';
import '../application/explain_due.dart';
import '../application/finish_session.dart';
import '../application/grade_review.dart';
import '../application/mark_studied.dart';
import '../application/reconcile_notifications.dart';
import '../application/relink_sources.dart';
import '../application/restore_backup.dart';
import '../application/run_backup.dart';
import '../application/save_exam.dart';
import '../application/source_folders.dart';
import '../application/share_logs.dart';
import '../application/split_item.dart';
import '../application/start_session.dart';
import '../application/undo_latest.dart';
import '../data/backup/backup_service.dart';
import '../data/backup/restore_service.dart';
import '../data/db/app_database.dart';
import '../data/db/db_file.dart';
import '../data/exchange/exam_exporter.dart';
import '../data/exchange/exam_importer.dart';
import '../data/study_writer.dart';
import '../platform/clock.dart';
import '../platform/device_status.dart';
import '../platform/file_sharer.dart';
import '../platform/folder_access.dart';
import '../platform/local_files.dart';
import '../platform/logging.dart';
import '../platform/notification_port.dart';
import '../platform/share_receiver.dart';
import '../platform/source_opener.dart';
import 'app_info.dart';

/// The open database. Restore closes it, swaps the file and invalidates this
/// provider, which opens the restored file (design §8). Tests override it.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The device's IANA time zone, stored on each event. Set in bootstrap.
final tzIdProvider = Provider<String>((ref) => 'UTC');

/// UTC offset at an instant, from the `timezone` database (`tz.local` is set
/// in bootstrap). Tests override it.
final offsetFnProvider = Provider<OffsetFn>(
    (ref) => (utc) => tz.local.timeZone(utc.millisecondsSinceEpoch).offset);

/// The day-start hour setting; bootstrap seeds it from the database.
final dayStartHourProvider =
    NotifierProvider<DayStartHour, int>(DayStartHour.new);

class DayStartHour extends Notifier<int> {
  @override
  int build() => Defaults.dayStartHour;

  void set(int hour) => state = hour;
}

final localDayClockProvider = Provider<LocalDayClock>((ref) => LocalDayClock(
      ref.watch(clockProvider),
      ref.watch(offsetFnProvider),
      dayStartHour: ref.watch(dayStartHourProvider),
    ));

final idGeneratorProvider = Provider<String Function()>((ref) {
  const uuid = Uuid();
  return uuid.v7;
});

DateTime Function() _now(Ref ref) {
  final clock = ref.watch(clockProvider);
  return clock.nowUtc;
}

final studyWriterProvider = Provider<StudyWriter>((ref) => StudyWriter(
      ref.watch(appDatabaseProvider),
      dayClock: ref.watch(localDayClockProvider),
      newId: ref.watch(idGeneratorProvider),
      tzId: () => ref.read(tzIdProvider),
    ));

// ---- use cases ----

final buildTodayPlanProvider = Provider<BuildTodayPlan>((ref) => BuildTodayPlan(
    ref.watch(appDatabaseProvider), ref.watch(localDayClockProvider),
    now: _now(ref)));

final markStudiedProvider = Provider<MarkStudied>((ref) => MarkStudied(
    ref.watch(appDatabaseProvider),
    ref.watch(studyWriterProvider),
    ref.watch(buildTodayPlanProvider),
    ref.watch(localDayClockProvider),
    newId: ref.watch(idGeneratorProvider)));

final gradeReviewProvider = Provider<GradeReview>((ref) => GradeReview(
    ref.watch(appDatabaseProvider),
    ref.watch(studyWriterProvider),
    ref.watch(buildTodayPlanProvider),
    ref.watch(localDayClockProvider)));

final undoLatestProvider =
    Provider<UndoLatest>((ref) => UndoLatest(ref.watch(studyWriterProvider)));

final addItemProvider = Provider<AddItem>((ref) => AddItem(
    ref.watch(appDatabaseProvider),
    newId: ref.watch(idGeneratorProvider),
    now: _now(ref)));

final splitItemProvider = Provider<SplitItem>((ref) => SplitItem(
    ref.watch(appDatabaseProvider),
    newId: ref.watch(idGeneratorProvider),
    now: _now(ref)));

final deleteItemProvider = Provider<DeleteItem>((ref) => DeleteItem(
    ref.watch(appDatabaseProvider),
    newId: ref.watch(idGeneratorProvider),
    now: _now(ref)));

final moveItemProvider = Provider<MoveItem>((ref) => MoveItem(ref.watch(appDatabaseProvider)));

final explainDueProvider = Provider<ExplainDue>((ref) =>
    ExplainDue(ref.watch(appDatabaseProvider), ref.watch(localDayClockProvider)));

final saveExamProvider = Provider<SaveExam>((ref) => SaveExam(
    ref.watch(appDatabaseProvider),
    newId: ref.watch(idGeneratorProvider),
    now: _now(ref)));

final completeOnboardingProvider = Provider<CompleteOnboarding>((ref) =>
    CompleteOnboarding(
        ref.watch(appDatabaseProvider),
        ref.watch(saveExamProvider),
        ref.watch(addItemProvider),
        ref.watch(buildTodayPlanProvider),
        ref.watch(markStudiedProvider)));

/// Today's study day. Invalidate on app resume so a day change is noticed.
final todayProvider =
    Provider<LocalDate>((ref) => ref.watch(localDayClockProvider).today());

/// Whether onboarding is finished; bootstrap seeds it from the database and
/// the router redirects to `/onboarding` while it is false.
final onboardingDoneProvider =
    NotifierProvider<OnboardingDone, bool>(OnboardingDone.new);

class OnboardingDone extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool done) => state = done;
}

// ---- platform ports ----

final notificationPortProvider =
    Provider<NotificationPort>((ref) => LocalNotificationPort(ref.watch(clockProvider)));

final deviceStatusProvider = Provider<DeviceStatus>((ref) => const AndroidDeviceStatus());

final folderAccessProvider = Provider<FolderAccess>((ref) => SafFolderAccess());

final sourceOpenerProvider = Provider<SourceOpener>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return IntentSourceOpener(ref.watch(folderAccessProvider),
      treeUriOf: (id) async => (await db.sourcesDao.folderById(id))?.treeUri);
});

final shareReceiverProvider = Provider<ShareReceiver>((ref) => IntentShareReceiver());

// ---- folders, sources and sharing ----

final sourceFoldersProvider = Provider<SourceFolders>((ref) => SourceFolders(
    ref.watch(appDatabaseProvider), ref.watch(folderAccessProvider),
    newId: ref.watch(idGeneratorProvider), now: _now(ref)));

final relinkSourcesProvider = Provider<RelinkSources>(
    (ref) => RelinkSources(ref.watch(appDatabaseProvider), ref.watch(folderAccessProvider)));

final captureSharedProvider = Provider<CaptureShared>((ref) => CaptureShared(
    ref.watch(appDatabaseProvider), ref.watch(folderAccessProvider), ref.watch(addItemProvider)));

// ---- sessions and notifications ----

final startSessionProvider = Provider<StartSession>((ref) => StartSession(
    ref.watch(appDatabaseProvider),
    ref.watch(notificationPortProvider),
    ref.watch(sourceOpenerProvider),
    newId: ref.watch(idGeneratorProvider),
    now: _now(ref)));

final finishSessionProvider = Provider<FinishSession>((ref) => FinishSession(
    ref.watch(appDatabaseProvider), ref.watch(notificationPortProvider),
    now: _now(ref)));

final discardSessionProvider = Provider<DiscardSession>((ref) => DiscardSession(
    ref.watch(appDatabaseProvider), ref.watch(notificationPortProvider),
    now: _now(ref)));

final reconcileNotificationsProvider = Provider<ReconcileNotifications>((ref) =>
    ReconcileNotifications(ref.watch(appDatabaseProvider), ref.watch(notificationPortProvider),
        now: _now(ref)));

// ---- backups, restore and catch-up ----

/// The cache and app-private directories; tests override them.
final cacheDirProvider = Provider<Future<String> Function()>((ref) => appCacheDir);
final privateDirProvider = Provider<Future<String> Function()>((ref) => appPrivateDir);
final databasePathProvider = Provider<Future<String> Function()>((ref) => databasePath);
final localFilesProvider = Provider<LocalFiles>((ref) => const IoLocalFiles());

final backupServiceProvider = Provider<BackupService>((ref) {
  final offset = ref.watch(offsetFnProvider);
  return BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(folderAccessProvider),
    cacheDir: ref.watch(cacheDirProvider),
    privateDir: ref.watch(privateDirProvider),
    appVersion: appVersion,
    now: _now(ref),
    toLocal: (utc) => utc.add(offset(utc)),
  );
});

final runBackupProvider = Provider<RunBackup>((ref) => RunBackup(
    ref.watch(appDatabaseProvider), ref.watch(backupServiceProvider), ref.watch(sourceFoldersProvider)));

final catchUpProvider = Provider<CatchUp>((ref) => CatchUp(
    ref.watch(appDatabaseProvider),
    ref.watch(studyWriterProvider),
    ref.watch(buildTodayPlanProvider),
    ref.watch(localDayClockProvider),
    newId: ref.watch(idGeneratorProvider)));

/// Restore replaces the database under every provider, so it is built from
/// the root container rather than from a provider that would be reset
/// mid-restore.
RestoreBackup restoreBackupFor(ProviderContainer c) => RestoreBackup(
      folders: c.read(folderAccessProvider),
      service: RestoreService(dbPath: c.read(databasePathProvider)),
      backups: c.read(backupServiceProvider),
      files: c.read(localFilesProvider),
      cacheDir: c.read(cacheDirProvider),
      closeDatabase: () => c.read(appDatabaseProvider).close(),
      reopenDatabase: () async {
        c.invalidate(appDatabaseProvider);
        return c.read(appDatabaseProvider);
      },
      newId: c.read(idGeneratorProvider),
      now: c.read(clockProvider).nowUtc,
    );

/// After a restore: re-seed settings-backed state and rebuild today.
Future<void> afterRestore(ProviderContainer c) async {
  final settings = c.read(appDatabaseProvider).settingsDao;
  c.read(dayStartHourProvider.notifier).set(await settings.dayStartHour());
  c.invalidate(todayProvider);
  await c.read(buildTodayPlanProvider).refresh();
  await c.read(reconcileNotificationsProvider)();
  c.read(onboardingDoneProvider.notifier).set(await settings.onboardingDone());
}

// ---- exam files ----

final fileSharerProvider = Provider<FileSharer>((ref) => const SystemFileSharer());

final examExporterProvider = Provider<ExamExporter>((ref) =>
    ExamExporter(ref.watch(appDatabaseProvider), appVersion: appVersion, now: _now(ref)));

final examImporterProvider = Provider<ExamImporter>((ref) => ExamImporter(
    ref.watch(appDatabaseProvider), ref.watch(studyWriterProvider),
    newId: ref.watch(idGeneratorProvider), now: _now(ref)));

final exportExamProvider = Provider<ExportExam>((ref) => ExportExam(
    ref.watch(examExporterProvider),
    ref.watch(folderAccessProvider),
    ref.watch(backupServiceProvider),
    ref.watch(fileSharerProvider),
    files: ref.watch(localFilesProvider),
    cacheDir: ref.watch(cacheDirProvider)));

final importExamProvider = Provider<ImportExam>((ref) =>
    ImportExam(ref.watch(examImporterProvider), ref.watch(buildTodayPlanProvider)));

final copyAsNewAttemptProvider = Provider<CopyAsNewAttempt>((ref) => CopyAsNewAttempt(
    ref.watch(examExporterProvider), ref.watch(examImporterProvider), ref.watch(buildTodayPlanProvider)));

final archiveAndRemoveProvider = Provider<ArchiveAndRemove>((ref) => ArchiveAndRemove(
    ref.watch(appDatabaseProvider),
    ref.watch(examExporterProvider),
    ref.watch(folderAccessProvider),
    ref.watch(backupServiceProvider),
    ref.watch(studyWriterProvider),
    ref.watch(buildTodayPlanProvider),
    files: ref.watch(localFilesProvider),
    cacheDir: ref.watch(cacheDirProvider)));

// ---- logging and diagnostics ----

/// Set in bootstrap once the log directory is known.
final logSinkProvider = Provider<FileLogSink>(
    (ref) => throw UnimplementedError('logSinkProvider is set in bootstrap'));

final shareLogsProvider = Provider<ShareLogs>((ref) => ShareLogs(
      ref.watch(logSinkProvider),
      ref.watch(deviceStatusProvider),
      ref.watch(notificationPortProvider),
      ref.watch(fileSharerProvider),
      appVersion: appVersion,
      tzId: ref.watch(tzIdProvider),
      cacheDir: ref.watch(cacheDirProvider),
      now: _now(ref),
    ));
