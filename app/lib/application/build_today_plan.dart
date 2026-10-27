import 'package:prep_core/prep_core.dart';

import '../data/daos/plans_dao.dart';
import '../data/db/app_database.dart';

/// Builds, freezes and refreshes today's plan (design §4, plan item 80).
class BuildTodayPlan {
  BuildTodayPlan(this._db, this._dayClock, {required DateTime Function() now})
      : _now = now;

  final AppDatabase _db;
  final LocalDayClock _dayClock;
  final DateTime Function() _now;

  /// Today's frozen plan, built and saved the first time it is asked for.
  Future<StoredPlan> get() async {
    final today = _dayClock.today();
    return await _db.plansDao.planFor(today) ?? await _build(today);
  }

  /// Rebuilds today's plan, keeping the rows already done.
  Future<StoredPlan> refresh() async {
    final today = _dayClock.today();
    return _build(today, done: await _db.plansDao.doneRows(today));
  }

  /// The plan as `buildPlan` computes it now, without saving (catch-up uses
  /// this for the waiting items and the review share).
  Future<(PlanInput, DayPlan)> compute() async {
    final today = _dayClock.today();
    final in_ = await input(today, done: await _db.plansDao.doneRows(today));
    return (in_, buildPlan(in_));
  }

  Future<StoredPlan> _build(LocalDate today, {List<DoneRow> done = const []}) =>
      _db.transaction(() async {
        final in_ = await input(today, done: done);
        await _db.plansDao.savePlan(today, buildPlan(in_),
            budget: in_.budget, builtAt: _now());
        return (await _db.plansDao.planFor(today))!;
      });

  /// Every reviewable item outside the Inbox, with its state, deadline and
  /// sort key.
  Future<PlanInput> input(LocalDate today,
      {List<DoneRow> done = const []}) async {
    final (:nodes, :keys) = await _db.nodesDao.planning();
    final states = await _db.itemStateDao.all();
    final refs = await _db.examsDao.examRefsBySubject();

    final rescheduled = <String>{};
    for (final id in await _db.eventsDao.nodesWithReschedule()) {
      if (undoableEvent(await _db.eventsDao.eventsFor(id)) is Reschedule) {
        rescheduled.add(id);
      }
    }
    final deadlines = <String, Deadline?>{};
    Deadline? deadlineOf(String subjectId) => deadlines.putIfAbsent(
        subjectId, () => resolveDeadline(refs[subjectId] ?? const [], today));

    return PlanInput(
      today: today,
      budget: await _db.settingsDao.dailyMinutes(),
      done: done,
      items: [
        for (final n in nodes)
          PlanItem(
            nodeId: n.id,
            state: states[n.id] ?? ItemState.unread,
            baseMinutes: n.baseMinutes!,
            sortKey: keys[n.id]!,
            deadline: deadlineOf(n.subjectId),
            newestIsReschedule: rescheduled.contains(n.id),
          ),
      ],
    );
  }
}

/// The deadline that caps items of [subjectId] today.
Future<Deadline?> deadlineForSubject(
    AppDatabase db, String subjectId, LocalDate today) async {
  final refs = await db.examsDao.examRefsBySubject();
  return resolveDeadline(refs[subjectId] ?? const [], today);
}
