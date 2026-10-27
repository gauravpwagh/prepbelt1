import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/db_watch.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';

/// One row of Due now, Up next or Coming up (design D16).
class TodayEntry {
  const TodayEntry({
    required this.node,
    required this.parentTitle,
    required this.state,
    required this.minutes,
    required this.reason,
    this.fits = false,
    this.daysOverdue = 0,
    this.due,
    this.doneToday = false,
  });

  final NodeRow node;
  final String? parentTitle;
  final ItemState state;
  final int minutes;
  final Reason reason;

  /// Above the line: the row is in today's frozen plan.
  final bool fits;
  final int daysOverdue;

  /// Coming up: the effective due date.
  final LocalDate? due;
  final bool doneToday;

  /// "Laxmikant · Ch 3" for a subtask, "Spectrum · next part" for a task
  /// split as you go (design §10b); the task title otherwise.
  String get title => parentTitle != null
      ? '$parentTitle · ${node.title}'
      : node.splitAsIGo == SplitAsIGo.open
          ? '${node.title} · next part'
          : node.title;
}

/// One group of Coming up: a day, next week or later.
class ComingUpGroup {
  const ComingUpGroup(this.label, this.bucket, this.entries);
  final String label;
  final UpcomingBucket bucket;
  final List<TodayEntry> entries;

  int get minutes => entries.fold(0, (s, e) => s + e.minutes);
  int get doneToday => entries.where((e) => e.doneToday).length;
}

class TodayView {
  const TodayView({
    required this.date,
    required this.header,
    required this.plannedMinutes,
    required this.doneCount,
    required this.dueNow,
    required this.upNext,
    required this.comingUp,
    required this.hasItems,
  });

  final LocalDate date;
  final DayPlanHeaderRow header;

  /// Minutes of every plan row, done or not.
  final int plannedMinutes;
  final int doneCount;
  final List<TodayEntry> dueNow;
  final List<TodayEntry> upNext;
  final List<ComingUpGroup> comingUp;

  /// Whether there is anything outside the Inbox to plan at all.
  final bool hasItems;

  int get budget => header.budgetMinutes;

  /// "1 done · 30 of 45 min".
  String get summary => '$doneCount done · $plannedMinutes of $budget min';
}

/// Today's frozen plan plus what it leaves out (design D16): rows below the
/// line and Coming up. Building the plan the first time it is read is part
/// of this.
final todayViewProvider = StreamProvider.autoDispose<TodayView>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final plans = ref.watch(buildTodayPlanProvider);
  final today = ref.watch(todayProvider);
  return watchTables(db, {
    db.dayPlans,
    db.dayPlanRows,
    db.itemStates,
    db.studyNodes,
    db.subjects,
    db.exams,
    db.examSubjects,
    db.reviewEvents,
  }, () async {
    final plan = await plans.get();
    final (:input, :nodes) = await plans.inputWithNodes(today);
    final items = {for (final i in input.items) i.nodeId: i};
    final planned = {for (final r in plan.rows) r.nodeId};
    final doneIds = {
      for (final r in plan.rows)
        if (r.doneAtUtc != null) r.nodeId,
    };
    final lists = todayLists(input, planned);

    // Plan rows whose node left the planning set (moved to the Inbox) still
    // show; deleted ones don't.
    for (final r in plan.rows) {
      if (r.doneAtUtc == null && !nodes.containsKey(r.nodeId)) {
        final n = await db.nodesDao.byId(r.nodeId);
        if (n != null && n.deletedAt == null) nodes[r.nodeId] = n;
      }
    }
    final parents = await db.nodesDao.titlesOf([
      for (final n in nodes.values)
        if (n.kind == NodeKind.subtask && n.parentId != null) n.parentId!,
    ]);
    String? parentOf(NodeRow n) => n.kind == NodeKind.subtask ? parents[n.parentId] : null;

    int overdue(PlanItem i) {
      final d = effectiveDue(i.state, i.deadline);
      return d == null || d >= today ? 0 : d.daysUntil(today);
    }

    TodayEntry fromItem(PlanItem i, {required bool fits, required int minutes, Reason? reason}) =>
        TodayEntry(
          node: nodes[i.nodeId]!,
          parentTitle: parentOf(nodes[i.nodeId]!),
          state: i.state,
          minutes: minutes,
          reason: reason ?? (i.isUnread ? Reason.firstRead : reasonFor(i, today)),
          fits: fits,
          daysOverdue: i.isUnread ? 0 : overdue(i),
        );

    final dueNow = <TodayEntry>[];
    final upNext = <TodayEntry>[];
    for (final r in plan.rows) {
      final node = nodes[r.nodeId];
      if (r.doneAtUtc != null || node == null) continue;
      final item = items[r.nodeId];
      final entry = item != null
          ? fromItem(item, fits: true, minutes: r.estimatedMinutes, reason: r.reason)
          : TodayEntry(
              node: node,
              parentTitle: parentOf(node),
              state: await db.itemStateDao.stateOf(node.id),
              minutes: r.estimatedMinutes,
              reason: r.reason,
              fits: true,
            );
      (r.rowType == RowType.review ? dueNow : upNext).add(entry);
    }
    for (final i in lists.dueBeyond) {
      dueNow.add(fromItem(i, fits: false, minutes: reviewCost(i.baseMinutes)));
    }
    for (final i in lists.unreadBeyond) {
      upNext.add(fromItem(i, fits: false, minutes: i.baseMinutes));
    }

    final groups = <ComingUpGroup>[];
    for (final u in lists.upcoming) {
      final bucket = upcomingBucket(u.due, today);
      final label = switch (bucket) {
        UpcomingBucket.day => formatWeekdayDay(u.due, today),
        UpcomingBucket.nextWeek => 'Next week',
        UpcomingBucket.later => 'Later',
      };
      if (groups.isEmpty || groups.last.label != label) {
        groups.add(ComingUpGroup(label, bucket, []));
      }
      final node = nodes[u.item.nodeId]!;
      groups.last.entries.add(TodayEntry(
        node: node,
        parentTitle: parentOf(node),
        state: u.item.state,
        minutes: reviewCost(u.item.baseMinutes),
        reason: Reason.due,
        due: u.due,
        doneToday: doneIds.contains(node.id),
      ));
    }

    return TodayView(
      date: today,
      header: plan.header,
      plannedMinutes: plan.rows.fold(0, (s, r) => s + r.estimatedMinutes),
      doneCount: doneIds.length,
      dueNow: dueNow,
      upNext: upNext,
      comingUp: groups,
      hasItems: input.items.isNotEmpty,
    );
  });
});

/// The sections left open today, or null for the default (design D16).
final todayOpenSectionsProvider = StreamProvider.autoDispose<Set<String>?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = ref.watch(todayProvider);
  return watchTables(db, {db.settings}, () => db.settingsDao.todayOpenSections(today));
});
