// Root providers: the single place where the app is wired (plan item 50).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../application/add_item.dart';
import '../application/build_today_plan.dart';
import '../application/capture_shared.dart';
import '../application/complete_onboarding.dart';
import '../application/delete_item.dart';
import '../application/discard_session.dart';
import '../application/explain_due.dart';
import '../application/finish_session.dart';
import '../application/grade_review.dart';
import '../application/mark_studied.dart';
import '../application/reconcile_notifications.dart';
import '../application/relink_sources.dart';
import '../application/save_exam.dart';
import '../application/source_folders.dart';
import '../application/split_item.dart';
import '../application/start_session.dart';
import '../application/undo_latest.dart';
import '../data/db/app_database.dart';
import '../data/study_writer.dart';
import '../platform/clock.dart';
import '../platform/device_status.dart';
import '../platform/folder_access.dart';
import '../platform/notification_port.dart';
import '../platform/share_receiver.dart';
import '../platform/source_opener.dart';

/// Overridden by `bootstrap()` with the opened database.
final appDatabaseProvider = Provider<AppDatabase>(
    (ref) => throw UnimplementedError('appDatabaseProvider is set in bootstrap'));

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
    ref.watch(localDayClockProvider)));

final gradeReviewProvider = Provider<GradeReview>((ref) => GradeReview(
    ref.watch(appDatabaseProvider),
    ref.watch(studyWriterProvider),
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

final deleteItemProvider = Provider<DeleteItem>(
    (ref) => DeleteItem(ref.watch(appDatabaseProvider), now: _now(ref)));

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
    Provider<NotificationPort>((ref) => LocalNotificationPort());

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
